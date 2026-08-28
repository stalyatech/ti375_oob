"""Execute a quantized graph with the bit exact integer operators."""

from __future__ import annotations

import numpy as np

from ..quant.qgraph import QGraph
from . import intops


class QRunner:
    def __init__(self, qg: QGraph):
        self.qg = qg
        self.g = qg.graph

    def quantize_input(self, name: str, x: np.ndarray) -> np.ndarray:
        """x is CHW float32 in the units the FP32 model expects."""
        return self.qg.tq[name].quantize(x)

    def dequantize(self, name: str, q: np.ndarray) -> np.ndarray:
        return self.qg.tq[name].dequantize(q)

    def run(self, inputs: dict, keep_all: bool = False) -> dict:
        """inputs: {name: CHW int8}. Returns {name: CHW int8} of the outputs
        (all tensors when keep_all)."""
        t = dict(inputs)
        tq = self.qg.tq
        for op in self.g.ops:
            if op.kind == "CONV":
                qc = self.qg.convs[op.name]
                x = t[op.inputs[0]]
                acc = intops.conv2d_int(x, qc.w_q, op.attrs["s"], op.attrs["pad"], tq[op.inputs[0]].zp)
                q = intops.requant_channels(acc, qc.bias_q, qc.mult, qc.shift, qc.zp_out)
                if qc.lut is not None:
                    q = intops.apply_lut(q, qc.lut)
                if qc.res is not None:
                    r = t[op.attrs["residual"]]
                    q = intops.residual_add(q, r, qc.res["mult_a"], qc.res["shift_a"],
                                            qc.res["mult_b"], qc.res["shift_b"],
                                            qc.res["zp_y"], qc.res["zp_r"], qc.res["zp_out"])
                t[op.outputs[0]] = q
            elif op.kind == "SILU":
                t[op.outputs[0]] = intops.apply_lut(t[op.inputs[0]], self.qg.luts[op.name])
            elif op.kind == "ADD":
                t[op.outputs[0]] = intops.add_same_scale(t[op.inputs[0]], t[op.inputs[1]], tq[op.outputs[0]].zp)
            elif op.kind == "MAXPOOL5":
                t[op.outputs[0]] = intops.maxpool5(t[op.inputs[0]])
            elif op.kind == "UPSAMPLE2":
                t[op.outputs[0]] = intops.upsample2(t[op.inputs[0]])
            elif op.kind == "CONCAT":
                t[op.outputs[0]] = intops.concat_channels([t[i] for i in op.inputs])
            elif op.kind == "SPLIT":
                parts = intops.split_channels(t[op.inputs[0]], op.attrs["sizes"])
                for name, part in zip(op.outputs, parts):
                    t[name] = part
            else:
                raise NotImplementedError(op.kind)
        if keep_all:
            return t
        return {o: t[o] for o in self.g.outputs}
