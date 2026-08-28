"""Integer parameters of every conv from float weights and tensor scales."""

from __future__ import annotations

import numpy as np

from ..frontend.graph import NpuGraph
from ..frontend.onnx_import import OnnxModel
from ..refmodel.fixedpoint import quantize_multiplier, silu_lut
from .qgraph import QConv, QGraph, QuantParams

UNIT_MULT = 1 << 15
UNIT_SHIFT = 15


def quantize_weights(w: np.ndarray) -> tuple:
    """Per output channel symmetric int8. Returns (w_q, scales[OC])."""
    oc = w.shape[0]
    absmax = np.abs(w.reshape(oc, -1)).max(axis=1)
    scales = np.where(absmax > 0, absmax / 127.0, 1.0 / 127.0)
    w_q = np.clip(np.rint(w / scales.reshape(oc, 1, 1, 1)), -127, 127).astype(np.int8)
    return w_q, scales


def quantize_conv(op, w: np.ndarray, b: np.ndarray | None, q_in: QuantParams,
                  q_pre: QuantParams, q_out: QuantParams, q_res: QuantParams | None) -> QConv:
    """q_pre is the scale the accumulator is requantized to (the
    pre-activation tensor for SiLU convs, the output otherwise). q_out is the
    tensor after activation (and after the residual add when present)."""
    oc = w.shape[0]
    w_q, s_w = quantize_weights(w)
    if b is None:
        b = np.zeros(oc, dtype=np.float64)
    s_acc = q_in.scale * s_w
    bias_q = np.rint(b / s_acc).astype(np.int64)
    bias_q -= np.int64(q_in.zp) * w_q.astype(np.int64).reshape(oc, -1).sum(axis=1)
    if np.any(np.abs(bias_q) >= (1 << 31)):
        raise OverflowError(f"bias of {op.name} does not fit int32")
    mult = np.zeros(oc, dtype=np.uint16)
    shift = np.zeros(oc, dtype=np.uint8)
    for c in range(oc):
        m, s = quantize_multiplier(s_acc[c] / q_pre.scale)
        mult[c], shift[c] = m, s
    lut = None
    if op.attrs.get("silu"):
        act_q = q_res if q_res is not None else q_out
        lut = silu_lut(q_pre.scale, q_pre.zp, act_q.scale, act_q.zp)
    res = None
    if q_res is not None:
        # The residual, the activation output and the sum share one scale
        # (unification), so both rescale paths are the identity.
        res = {"mult_a": UNIT_MULT, "shift_a": UNIT_SHIFT, "mult_b": UNIT_MULT, "shift_b": UNIT_SHIFT,
               "zp_y": q_out.zp, "zp_r": q_res.zp, "zp_out": q_out.zp}
    return QConv(w_q, bias_q.astype(np.int32), mult, shift, q_pre.zp, lut, res)


def build_qgraph(g: NpuGraph, model: OnnxModel, tq: dict, meta: dict | None = None) -> QGraph:
    qg = QGraph(g, tq=dict(tq), meta=meta or {})
    for op in g.ops:
        if op.kind == "CONV":
            w = model.const(op.attrs["weight"]).astype(np.float64)
            b = model.const(op.attrs["bias"]) if op.attrs.get("bias") else None
            b = None if b is None else b.astype(np.float64)
            out = op.outputs[0]
            q_in = tq[op.inputs[0]]
            q_out = tq[out]
            residual = op.attrs.get("residual")
            q_res = tq[residual] if residual else None
            if op.attrs.get("silu"):
                q_pre = tq[op.attrs["preact"]]
            elif residual:
                q_pre = tq[op.attrs["preadd"]]
            else:
                q_pre = q_out
            qg.convs[op.name] = quantize_conv(op, w, b, q_in, q_pre, q_out, q_res)
        elif op.kind == "SILU":
            q_in = tq[op.inputs[0]]
            q_out = tq[op.outputs[0]]
            qg.luts[op.name] = silu_lut(q_in.scale, q_in.zp, q_out.scale, q_out.zp)
    return qg
