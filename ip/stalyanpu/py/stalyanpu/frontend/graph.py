"""Intermediate representation of the accelerator graph.

Ops:
    CONV       k, s, pad, ic, oc, silu, residual (tensor name or None),
               weight, bias (initializer names)
    MAXPOOL5   5x5 stride 1 pad 2 max pool
    CONCAT     channel concatenation, resolved to write offsets by the emitter
    SPLIT      channel split, resolved to read offsets by the emitter
    UPSAMPLE2  nearest 2x upsample, resolved to a reader address mode

Tensors are NCHW with batch 1. Channel groups of 32 are the unit of the
DDR layout, which is why CONCAT and SPLIT only accept 32 aligned offsets.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TensorInfo:
    name: str
    shape: tuple
    dtype: str = "float32"
    is_const: bool = False

    @property
    def c(self) -> int:
        return self.shape[1] if len(self.shape) >= 2 else 1

    @property
    def h(self) -> int:
        return self.shape[2] if len(self.shape) >= 3 else 1

    @property
    def w(self) -> int:
        return self.shape[3] if len(self.shape) >= 4 else 1


@dataclass
class Op:
    kind: str
    name: str
    inputs: list
    outputs: list
    attrs: dict = field(default_factory=dict)

    def text(self) -> str:
        a = ", ".join(f"{k}={v}" for k, v in self.attrs.items() if k not in ("weight", "bias"))
        return f"{self.kind:10s} {self.name}: {self.inputs} -> {self.outputs} [{a}]"


class NpuGraph:
    def __init__(self):
        self.tensors: dict[str, TensorInfo] = {}
        self.ops: list[Op] = []
        self.inputs: list[str] = []
        self.outputs: list[str] = []

    def add_tensor(self, t: TensorInfo) -> None:
        self.tensors[t.name] = t

    def producer(self, name: str):
        for op in self.ops:
            if name in op.outputs:
                return op
        return None

    def consumers(self, name: str) -> list:
        return [op for op in self.ops if name in op.inputs]

    def op_counts(self) -> dict:
        counts: dict[str, int] = {}
        for op in self.ops:
            counts[op.kind] = counts.get(op.kind, 0) + 1
        return counts

    def macs(self) -> int:
        total = 0
        for op in self.ops:
            if op.kind == "CONV":
                t = self.tensors[op.outputs[0]]
                total += t.h * t.w * op.attrs["oc"] * op.attrs["ic"] * op.attrs["k"] ** 2
        return total

    def text(self) -> str:
        lines = [f"inputs : {self.inputs}", f"outputs: {self.outputs}"]
        for op in self.ops:
            lines.append(op.text())
        return "\n".join(lines)
