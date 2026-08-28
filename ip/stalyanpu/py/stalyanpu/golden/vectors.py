"""Golden vectors for the RTL testbenches.

A vector set is a directory with:
    mem.hex       memory image before the run (blob, input, parameters)
    golden.hex    expected memory contents of the output regions
    golden.json   regions {name, base, bytes, shape, crc32}, descriptor
                  range to execute, CSR values to program

``write_net_vectors`` covers the whole descriptor list; ``write_layer_vectors``
runs the interpreter up to the selected descriptor so its inputs are in
memory, then emits a one descriptor list for it.
"""

from __future__ import annotations

import json
import os

import numpy as np

from ..backend import isa, layout
from ..backend.emit import Program
from ..backend.interp import Memory, run_blob, run_descriptor
from ..hwcfg import HwConfig
from . import hexfmt


def _region(name, base, data, shape):
    return {"name": name, "base": base, "bytes": len(data), "shape": list(shape), "crc32": hexfmt.crc32(data)}


def _write_set(out_dir, mem_before: Memory, regions: list, meta: dict) -> None:
    os.makedirs(out_dir, exist_ok=True)
    hexfmt.write_hex(os.path.join(out_dir, "mem.hex"), mem_before.ranges())
    hexfmt.write_hex(os.path.join(out_dir, "golden.hex"), [(r["base"], r["data"]) for r in regions])
    doc = dict(meta)
    doc["regions"] = [{k: v for k, v in r.items() if k != "data"} for r in regions]
    with open(os.path.join(out_dir, "golden.json"), "w") as fh:
        json.dump(doc, fh, indent=1)


def write_net_vectors(prog: Program, hw: HwConfig, mem: Memory, out_dir: str, dump_all: bool = False) -> dict:
    """mem holds the blob and the input. Runs the full list."""
    before = Memory()
    before.pages = {k: bytearray(v) for k, v in mem.pages.items()}
    regions = []

    def on_desc(i, d):
        if dump_all:
            oc, h, w = d.get("oc"), d.get("out_h"), d.get("out_w")
            planes = layout.n_planes(oc)
            size = planes * d.get("out_plane_stride")
            base = d.get("out_base")
            regions.append(dict(_region(f"desc{i}", base, mem.read(base, size), (planes * 32, h, w)), data=mem.read(base, size)))

    run_blob(mem, prog.base, hw, on_descriptor=on_desc)
    for o in prog.outputs:
        base = prog.scratch + o.offset
        size = layout.tensor_bytes(o.c, o.h, o.w)
        data = mem.read(base, size)
        regions.append(dict(_region(o.name, base, data, (layout.n_planes(o.c) * 32, o.h, o.w)), data=data))
    meta = {"kind": "net", "base": prog.base, "scratch": prog.scratch, "desc_base": prog.base + prog.desc_off,
            "desc_count": len(prog.descriptors), "hwcfg": hw.name}
    _write_set(out_dir, before, regions, meta)
    return meta


def write_layer_vectors(prog: Program, hw: HwConfig, mem: Memory, index: int, out_dir: str) -> dict:
    """Runs descriptors 0..index-1 to fill memory, then writes a set that
    executes only descriptor ``index`` (as a one entry list at a scratch
    address so the LAST and IRQ flags are set)."""
    descs = prog.descriptors
    for d in descs[:index]:
        run_descriptor(mem, d, hw)
    d = descs[index]
    single = type(d)()
    single.w = list(d.w)
    single.set("flags", single.get("flags") | (1 << isa.FLAGS["LAST"]) | (1 << isa.FLAGS["IRQ"]))
    single.set("flags", single.get("flags") & ~(1 << isa.FLAGS["WAIT_PREV"]))
    single.finalize()
    list_base = prog.base + prog.size          # right after the blob, 4 KB aligned
    mem.write(list_base, single.to_bytes())
    before = Memory()
    before.pages = {k: bytearray(v) for k, v in mem.pages.items()}
    run_descriptor(mem, single, hw)
    oc, h, w = d.get("oc"), d.get("out_h"), d.get("out_w")
    planes = layout.n_planes(oc)
    base = d.get("out_base")
    size = planes * d.get("out_plane_stride")
    data = mem.read(base, size)
    regions = [dict(_region(prog.desc_names[index], base, data, (planes * 32, h, w)), data=data)]
    meta = {"kind": "layer", "index": index, "op": prog.desc_names[index], "base": prog.base,
            "scratch": prog.scratch, "desc_base": list_base, "desc_count": 1, "hwcfg": hw.name}
    _write_set(out_dir, before, regions, meta)
    return meta
