"""Range selection and scale unification.

Tensors joined by Concat, Split, MaxPool, Upsample or a residual add share
one (scale, zero point) so that these ops move bytes without arithmetic.
The groups are built with union-find over the IR; every member takes the
union of the member ranges.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..frontend.graph import NpuGraph
from .qgraph import QuantParams


class _UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, x):
        self.parent.setdefault(x, x)
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def unification_groups(g: NpuGraph) -> list:
    uf = _UnionFind()
    for op in g.ops:
        if op.kind in ("CONCAT", "SPLIT"):
            names = op.inputs + op.outputs
        elif op.kind in ("MAXPOOL5", "UPSAMPLE2", "ADD"):
            names = op.inputs + op.outputs
        elif op.kind == "CONV" and op.attrs.get("residual"):
            names = [op.attrs["residual"], op.outputs[0]]
            if op.attrs.get("preadd"):
                names.append(op.attrs["preadd"])
        else:
            continue
        for n in names[1:]:
            uf.union(names[0], n)
    groups = {}
    for n in list(uf.parent):
        groups.setdefault(uf.find(n), set()).add(n)
    return [s for s in groups.values() if len(s) > 1]


def range_to_qparams(lo: float, hi: float) -> QuantParams:
    lo = min(lo, 0.0)
    hi = max(hi, 0.0)
    if hi-lo < 1e-8:
        hi = lo + 1e-8
    scale = (hi-lo) / 255.0
    zp = int(round(-128 - lo / scale))
    zp = max(-128, min(127, zp))
    return QuantParams(scale, zp)


@dataclass
class RangeReport:
    groups: list
    coarsening: dict   # tensor -> group range / own range

    def text(self, threshold: float = 4.0) -> str:
        lines = [f"unification groups: {len(self.groups)}"]
        worst = sorted(self.coarsening.items(), key=lambda kv: -kv[1])
        for name, f in worst:
            if f > threshold:
                lines.append(f"  coarsening {f:.1f}x on {name}")
        return "\n".join(lines)


def _silu(x):
    return x / (1.0 + np.exp(-x))


def mse_range(samples: np.ndarray, lo: float, hi: float, after_silu: bool = False,
              factors=None) -> tuple:
    """Shrink (lo, hi) by a common factor and keep the one with the lowest
    quantization error on the samples. For pre-activation tensors the error
    is measured after SiLU, which is what the activation table sees."""
    if samples.size == 0:
        return lo, hi
    if factors is None:
        factors = np.geomspace(0.02, 1.0, 80)
    x = samples.astype(np.float64)
    target = _silu(x) if after_silu else x
    best = (float("inf"), lo, hi)
    for f in factors:
        l, h = lo * f, hi * f
        q = range_to_qparams(l, h)
        xq = (np.clip(np.rint(x / q.scale) + q.zp, -128, 127) - q.zp) * q.scale
        err = ((_silu(xq) if after_silu else xq) - target)
        mse = float((err * err).mean())
        if mse < best[0]:
            best = (mse, l, h)
    return best[1], best[2]


def choose_qparams(g: NpuGraph, stats: dict, method: str = "percentile",
                   fixed: dict | None = None, overrides: dict | None = None):
    """Return ({tensor: QuantParams}, RangeReport).

    Methods: "mse" (search of the clipping range that minimises the
    quantization error on the collected samples, starting from the min/max
    range; best mAP on YOLOv8s), "minmax" and "percentile" (averaged per
    image percentiles).
    ``fixed`` gives tensors whose parameters are known (the image input).
    ``overrides`` maps tensor names to a method to deviate from the default.
    """
    fixed = fixed or {}
    overrides = overrides or {}
    preacts = {op.attrs["preact"] for op in g.ops if op.kind == "CONV" and op.attrs.get("preact")}

    def own_range(name):
        s = stats[name]
        m = overrides.get(name, method)
        if m == "minmax":
            return s.lo, s.hi
        if m == "mse":
            return mse_range(s.samples, s.lo, s.hi, after_silu=name in preacts)
        return s.p_lo, s.p_hi

    ranges = {}
    for name in stats:
        if name in fixed:
            q = fixed[name]
            ranges[name] = ((-128 - q.zp) * q.scale, (127 - q.zp) * q.scale)
        else:
            ranges[name] = own_range(name)

    groups = unification_groups(g)
    coarsening = {}
    tq = {}
    seen = set()
    for grp in groups:
        members = [n for n in grp if n in ranges]
        if not members:
            continue
        lo = min(ranges[n][0] for n in members)
        hi = max(ranges[n][1] for n in members)
        fixed_members = [n for n in members if n in fixed]
        q = fixed[fixed_members[0]] if fixed_members else range_to_qparams(lo, hi)
        for n in members:
            own = ranges[n][1] - ranges[n][0]
            coarsening[n] = (hi-lo) / own if own > 0 else 1.0
            tq[n] = q
            seen.add(n)
    for name, (lo, hi) in ranges.items():
        if name in seen:
            continue
        tq[name] = fixed[name] if name in fixed else range_to_qparams(lo, hi)
    return tq, RangeReport(groups, coarsening)
