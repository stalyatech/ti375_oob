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
    # Split window images with word addresses relative to the window bases,
    # so the bench can use $readmemh instead of parsing lines itself.
    win0, win1 = [], []
    for addr, data in mem_before.ranges():
        (win1 if addr >= meta["scratch"] else win0).append((addr, data))
    hexfmt.write_win_hex(os.path.join(out_dir, "mem0.hex"), win0, meta["base"])
    hexfmt.write_win_hex(os.path.join(out_dir, "mem1.hex"), win1, meta["scratch"])
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


def _crop_descriptor(d, max_tiles: int) -> None:
    """Limits the descriptor to the first ``max_tiles`` output tiles so the
    simulation stays short. The input height shrinks to the rows those output
    rows need; rows past it count as bottom padding for the interpreter and
    the hardware alike. The output planes pack with the cropped height."""
    op = d.get("opcode")
    tile_rows = d.get("tile_rows")
    out_h = d.get("out_h")
    rows = min(out_h, max_tiles * tile_rows)
    if rows < out_h and rows % 2:
        rows += 1
    if rows >= out_h:
        return
    d.set("out_h", rows)
    if op == isa.OPCODES["CONV"]:
        in_rows = rows if d.get("stride") == 1 else 2 * rows - 1
        d.set("in_h", min(d.get("in_h"), in_rows))
    else:
        d.set("in_h", rows)
    d.set("n_tiles", (rows + tile_rows - 1) // tile_rows)
    d.set("out_plane_stride", rows * d.get("out_row_stride"))
    d.finalize()


def write_layer_vectors(prog: Program, hw: HwConfig, mem: Memory, index: int, out_dir: str,
                        max_tiles: int | None = None) -> dict:
    """Runs descriptors 0..index-1 to fill memory, then writes a set that
    executes only descriptor ``index`` (as a one entry list at a scratch
    address so the LAST and IRQ flags are set). With ``max_tiles`` the
    descriptor is cropped to that many output tiles and the memory image
    keeps only the pages the run reads."""
    descs = prog.descriptors
    for d in descs[:index]:
        run_descriptor(mem, d, hw)
    d = descs[index]
    single = type(d)()
    single.w = list(d.w)
    single.set("flags", single.get("flags") | (1 << isa.FLAGS["LAST"]) | (1 << isa.FLAGS["IRQ"]))
    single.set("flags", single.get("flags") & ~(1 << isa.FLAGS["WAIT_PREV"]))
    single.finalize()
    if max_tiles is not None:
        _crop_descriptor(single, max_tiles)
    list_base = prog.base + prog.size          # right after the blob, 4 KB aligned
    mem.write(list_base, single.to_bytes())
    snapshot = {k: bytearray(v) for k, v in mem.pages.items()}
    mem.track = True
    mem.reads = set()
    run_descriptor(mem, single, hw)
    mem.track = False
    before = Memory()
    if max_tiles is not None:
        keep = set()
        for pg in mem.reads:
            keep.update((pg - 1, pg, pg + 1))
        for a in (list_base, list_base + isa.DESC_BYTES - 1):
            keep.add(a // Memory.PAGE)
        before.pages = {k: v for k, v in snapshot.items() if k in keep}
    else:
        before.pages = snapshot
    oc, h, w = single.get("oc"), single.get("out_h"), single.get("out_w")
    planes = layout.n_planes(oc)
    base = single.get("out_base")
    size = planes * single.get("out_plane_stride")
    data = mem.read(base, size)
    regions = [dict(_region(prog.desc_names[index], base, data, (planes * 32, h, w)), data=data)]
    meta = {"kind": "layer", "index": index, "op": prog.desc_names[index], "base": prog.base,
            "scratch": prog.scratch, "desc_base": list_base, "desc_count": 1, "hwcfg": hw.name,
            "run_dims": {"in_h": single.get("in_h"), "in_w": single.get("in_w"),
                         "out_h": single.get("out_h"), "out_w": single.get("out_w"),
                         "ic": single.get("ic"), "oc": single.get("oc"),
                         "k": single.get("k"), "stride": single.get("stride"),
                         "opcode": single.get("opcode")}}
    _write_set(out_dir, before, regions, meta)
    return meta
