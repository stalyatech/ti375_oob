"""Quantized graph container: the lowered IR plus tensor quantization
parameters and per conv integer weights, bias, requant factors and tables.

Saved as a directory with ``qgraph.json`` (graph, tensor params, scalar conv
parameters) and ``qgraph.npz`` (arrays).
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import numpy as np

from ..frontend.graph import NpuGraph, Op, TensorInfo


@dataclass
class QuantParams:
    scale: float
    zp: int

    def quantize(self, x: np.ndarray) -> np.ndarray:
        q = np.rint(x / self.scale) + self.zp
        return np.clip(q, -128, 127).astype(np.int8)

    def dequantize(self, q: np.ndarray) -> np.ndarray:
        return (q.astype(np.float32) - self.zp) * np.float32(self.scale)


@dataclass
class QConv:
    w_q: np.ndarray            # int8 [OC, IC, k, k]
    bias_q: np.ndarray         # int32 [OC], zero point of the input folded in
    mult: np.ndarray           # uint16 [OC]
    shift: np.ndarray          # uint8 [OC]
    zp_out: int                # zero point of the requantized value (preact or output)
    lut: np.ndarray | None = None   # int8 [256] when silu
    # Residual path (general two multiplier form of the epilogue).
    res: dict | None = None    # keys: mult_a, shift_a, mult_b, shift_b, zp_y, zp_r, zp_out


@dataclass
class QGraph:
    graph: NpuGraph
    tq: dict = field(default_factory=dict)      # tensor name -> QuantParams
    convs: dict = field(default_factory=dict)   # conv op name -> QConv
    luts: dict = field(default_factory=dict)    # standalone SILU op name -> int8[256]
    meta: dict = field(default_factory=dict)

    def save(self, out_dir: str) -> None:
        os.makedirs(out_dir, exist_ok=True)
        g = self.graph
        doc = {
            "meta": self.meta,
            "inputs": g.inputs,
            "outputs": g.outputs,
            "tensors": {n: {"shape": list(t.shape)} for n, t in g.tensors.items()},
            "ops": [{"kind": op.kind, "name": op.name, "inputs": op.inputs,
                     "outputs": op.outputs, "attrs": op.attrs} for op in g.ops],
            "tq": {n: {"scale": float(q.scale), "zp": int(q.zp)} for n, q in self.tq.items()},
            "convs": {n: {"zp_out": int(c.zp_out), "res": c.res} for n, c in self.convs.items()},
        }
        with open(os.path.join(out_dir, "qgraph.json"), "w") as fh:
            json.dump(doc, fh, indent=1)
        arrays = {}
        for n, c in self.convs.items():
            arrays[f"{n}/w_q"] = c.w_q
            arrays[f"{n}/bias_q"] = c.bias_q
            arrays[f"{n}/mult"] = c.mult
            arrays[f"{n}/shift"] = c.shift
            if c.lut is not None:
                arrays[f"{n}/lut"] = c.lut
        for n, lut in self.luts.items():
            arrays[f"silu/{n}"] = lut
        np.savez_compressed(os.path.join(out_dir, "qgraph.npz"), **arrays)

    @classmethod
    def load(cls, out_dir: str) -> "QGraph":
        with open(os.path.join(out_dir, "qgraph.json")) as fh:
            doc = json.load(fh)
        arrays = np.load(os.path.join(out_dir, "qgraph.npz"))
        g = NpuGraph()
        g.inputs = doc["inputs"]
        g.outputs = doc["outputs"]
        for n, t in doc["tensors"].items():
            g.add_tensor(TensorInfo(n, tuple(t["shape"])))
        for o in doc["ops"]:
            g.ops.append(Op(o["kind"], o["name"], o["inputs"], o["outputs"], o["attrs"]))
        qg = cls(g, meta=doc.get("meta", {}))
        qg.tq = {n: QuantParams(v["scale"], v["zp"]) for n, v in doc["tq"].items()}
        for n, c in doc["convs"].items():
            qg.convs[n] = QConv(
                arrays[f"{n}/w_q"], arrays[f"{n}/bias_q"], arrays[f"{n}/mult"], arrays[f"{n}/shift"],
                c["zp_out"], arrays[f"{n}/lut"] if f"{n}/lut" in arrays else None, c["res"])
        for key in arrays.files:
            if key.startswith("silu/"):
                qg.luts[key[5:]] = arrays[key]
        return qg
