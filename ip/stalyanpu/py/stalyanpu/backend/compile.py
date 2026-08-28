"""Compile a quantized graph into a blob and check it with the interpreter."""

from __future__ import annotations

import json
import os

import numpy as np

from ..hwcfg import HwConfig
from ..quant.qgraph import QGraph
from ..refmodel.runner import QRunner
from . import layout
from .emit import Program, emit
from .interp import Memory, run_blob


def load_program(qg: QGraph, hw: HwConfig, base: int = 0x20000000, scratch: int = 0x28000000) -> Program:
    return emit(qg, hw, base, scratch)


def write_build(prog: Program, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "frame.bin"), "wb") as fh:
        fh.write(prog.to_bytes())
    doc = {
        "base": prog.base, "scratch": prog.scratch, "size": prog.size,
        "scratch_size": prog.alloc.scratch_size,
        "descriptors": [{"index": i, "op": n, "words": d.w} for i, (n, d) in enumerate(zip(prog.desc_names, prog.descriptors))],
        "buffers": [{"name": b.name, "offset": b.offset, "size": b.size, "planes": b.planes, "h": b.h, "w": b.w,
                     "first_use": b.first_use, "last_use": b.last_use, "pinned": b.pinned} for b in prog.alloc.buffers],
        "input": {"name": prog.input_name, "offset": prog.input_offset, "bytes": prog.input_bytes, "shape": list(prog.input_shape)},
        "outputs": [o.__dict__ for o in prog.outputs],
    }
    with open(os.path.join(out_dir, "alloc.json"), "w") as fh:
        json.dump(doc, fh, indent=1)


def make_memory(prog: Program, x_int8: np.ndarray, zp_in: int) -> Memory:
    mem = Memory()
    mem.write(prog.base, prog.to_bytes())
    mem.write(prog.scratch + prog.input_offset, layout.pack(x_int8, zp_in))
    return mem


def check(qg: QGraph, hw: HwConfig, prog: Program, x_int8: np.ndarray) -> tuple:
    """Run the interpreter on the blob and the reference runner on the graph.
    Returns (ok, {name: mismatching bytes})."""
    zp_in = qg.tq[prog.input_name].zp
    mem = make_memory(prog, x_int8, zp_in)
    got = run_blob(mem, prog.base, hw)
    ref = QRunner(qg).run({prog.input_name: x_int8})
    diff = {}
    for name, r in ref.items():
        g = got[name]
        diff[name] = int((g != r).sum()) if g.shape == r.shape else -1
    return all(v == 0 for v in diff.values()), diff
