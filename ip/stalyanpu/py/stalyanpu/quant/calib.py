"""Activation statistics from the FP32 ONNX model.

Every tensor the quantizer needs (graph inputs, op outputs, pre-activation
and pre-add tensors) is exposed as an extra ONNX output and one onnxruntime
session collects, per image, the min, max and the low and high percentiles.
Percentiles are averaged over the calibration images, which is the usual
"averaged percentile" calibration and needs a single pass.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import onnx

from ..frontend.graph import NpuGraph


SAMPLES_PER_IMAGE = 2048


@dataclass
class TensorStats:
    n: int = 0
    lo: float = float("inf")
    hi: float = float("-inf")
    p_lo_sum: float = 0.0
    p_hi_sum: float = 0.0
    chunks: list = field(default_factory=list)

    def update(self, t: np.ndarray, p: float, rng=None) -> None:
        flat = t.reshape(-1)
        self.n += 1
        self.lo = min(self.lo, float(flat.min()))
        self.hi = max(self.hi, float(flat.max()))
        q = np.percentile(flat, [100.0 - p, p])
        self.p_lo_sum += float(q[0])
        self.p_hi_sum += float(q[1])
        # A random subsample of values feeds the MSE range search.
        if rng is not None:
            k = min(SAMPLES_PER_IMAGE, flat.size)
            self.chunks.append(flat[rng.choice(flat.size, k, replace=False)].astype(np.float32))

    @property
    def samples(self) -> np.ndarray:
        if not self.chunks:
            return np.zeros(0, dtype=np.float32)
        return np.concatenate(self.chunks)

    @property
    def p_lo(self) -> float:
        return self.p_lo_sum / max(self.n, 1)

    @property
    def p_hi(self) -> float:
        return self.p_hi_sum / max(self.n, 1)

    def as_dict(self) -> dict:
        return {"n": self.n, "min": self.lo, "max": self.hi, "p_lo": self.p_lo, "p_hi": self.p_hi}


def calibration_tensors(g: NpuGraph) -> list:
    names = list(g.inputs)
    for op in g.ops:
        for o in op.outputs:
            names.append(o)
        if op.kind == "CONV":
            if op.attrs.get("preact"):
                names.append(op.attrs["preact"])
            if op.attrs.get("preadd"):
                names.append(op.attrs["preadd"])
    return list(dict.fromkeys(names))


def make_probe_model(model: onnx.ModelProto, tensors: list) -> onnx.ModelProto:
    m = onnx.ModelProto()
    m.CopyFrom(model)
    existing = {o.name for o in m.graph.output}
    inputs = {i.name for i in m.graph.input}
    for t in tensors:
        if t in existing or t in inputs:
            continue
        m.graph.output.append(onnx.helper.make_tensor_value_info(t, onnx.TensorProto.FLOAT, None))
    return m


def collect_stats(model: onnx.ModelProto, g: NpuGraph, images, percentile: float = 99.99,
                  input_name: str | None = None, progress=None) -> dict:
    """images yields NCHW float32 arrays. Returns {tensor: TensorStats}."""
    import onnxruntime as ort

    tensors = calibration_tensors(g)
    probe = make_probe_model(model, tensors)
    sess = ort.InferenceSession(probe.SerializeToString(), providers=["CPUExecutionProvider"])
    in_name = input_name or sess.get_inputs()[0].name
    out_names = [t for t in tensors if t != in_name]
    stats = {t: TensorStats() for t in tensors}
    rng = np.random.default_rng(0)
    for i, img in enumerate(images):
        stats[in_name].update(img, percentile, rng)
        outs = sess.run(out_names, {in_name: img})
        for name, val in zip(out_names, outs):
            stats[name].update(val, percentile, rng)
        if progress:
            progress(i + 1)
    return stats
