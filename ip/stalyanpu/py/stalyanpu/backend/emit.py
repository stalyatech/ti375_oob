"""Descriptor and blob emitter.

The blob is loaded at ``base`` and holds a 4 KB header, the descriptor
table and the parameter region (weights, per channel parameters, activation
tables). Activations live in a separate scratch region at ``scratch``. All
addresses inside descriptors are absolute.
"""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass, field

from ..hwcfg import HwConfig
from ..quant.qgraph import QGraph
from . import isa, layout, weightpack
from .alloc import Allocation, allocate
from .tiler import tile_conv

HEADER_BYTES = 4096
SECTION_ALIGN = 4096
PARAM_ALIGN = 64


def _align(x: int, a: int) -> int:
    return (x + a - 1) // a * a


def _ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


class Descriptor:
    def __init__(self):
        self.w = [0] * isa.DESC_WORDS
        self.set("version", isa.ISA_VERSION)

    def set(self, name: str, value: int) -> None:
        f = isa.field(name)
        v = int(value) & f.mask
        if value < 0:
            assert -(1 << (f.width - 1)) <= value, (name, value)
        else:
            assert value <= f.mask, (name, value)
        self.w[f.word] = (self.w[f.word] & ~(f.mask << f.lsb)) | (v << f.lsb)

    def get(self, name: str, signed: bool = False) -> int:
        f = isa.field(name)
        v = (self.w[f.word] >> f.lsb) & f.mask
        if signed and v >= 1 << (f.width - 1):
            v -= 1 << f.width
        return v

    def flag(self, name: str) -> None:
        self.set("flags", self.get("flags") | (1 << isa.FLAGS[name]))

    def has_flag(self, name: str) -> bool:
        return bool(self.get("flags") & (1 << isa.FLAGS[name]))

    def finalize(self) -> None:
        body = struct.pack("<31I", *self.w[:31])
        self.w[31] = zlib.crc32(body) & 0xFFFFFFFF

    def to_bytes(self) -> bytes:
        return struct.pack("<32I", *self.w)

    @classmethod
    def from_bytes(cls, data) -> "Descriptor":
        d = cls()
        d.w = list(struct.unpack("<32I", bytes(data[:isa.DESC_BYTES])))
        return d

    def crc_ok(self) -> bool:
        return zlib.crc32(struct.pack("<31I", *self.w[:31])) & 0xFFFFFFFF == self.w[31]


@dataclass
class OutputInfo:
    name: str
    offset: int
    c: int
    h: int
    w: int
    scale: float
    zp: int


@dataclass
class Program:
    base: int
    scratch: int
    descriptors: list
    params: bytes
    alloc: Allocation
    outputs: list
    input_name: str
    input_offset: int
    input_bytes: int
    input_shape: tuple
    desc_names: list = field(default_factory=list)

    @property
    def desc_off(self) -> int:
        return HEADER_BYTES

    @property
    def param_off(self) -> int:
        return _align(HEADER_BYTES + len(self.descriptors) * isa.DESC_BYTES, SECTION_ALIGN)

    @property
    def size(self) -> int:
        return _align(self.param_off + len(self.params), SECTION_ALIGN)

    def to_bytes(self) -> bytes:
        blob = bytearray(self.size)
        for i, d in enumerate(self.descriptors):
            blob[self.desc_off + i * isa.DESC_BYTES:self.desc_off + (i + 1) * isa.DESC_BYTES] = d.to_bytes()
        blob[self.param_off:self.param_off + len(self.params)] = self.params
        # Output table and names inside the header, after the fixed words.
        n_hdr = len(isa.BLOB_HEADER)
        outputs_off = n_hdr * 4
        names_off = outputs_off + len(self.outputs) * len(isa.OUTPUT_ENTRY) * 4
        names = bytearray()
        entries = bytearray()
        for o in self.outputs:
            entries += struct.pack("<8I", o.offset, o.h, o.w, o.c, int(round(o.scale * 65536.0)),
                                   o.zp & 0xFFFFFFFF, names_off + len(names), 0)
            names += o.name.encode() + b"\0"
        assert names_off + len(names) <= HEADER_BYTES, "header overflow"
        blob[outputs_off:outputs_off + len(entries)] = entries
        blob[names_off:names_off + len(names)] = names
        hdr = [isa.BLOB_MAGIC, isa.ISA_VERSION, self.base, self.size, self.desc_off, len(self.descriptors),
               self.param_off, len(self.params), self.scratch, self.alloc.scratch_size,
               self.input_offset, self.input_bytes, len(self.outputs), outputs_off, 0]
        assert len(hdr) == n_hdr
        blob[0:n_hdr * 4] = struct.pack(f"<{n_hdr}I", *hdr)
        crc = zlib.crc32(bytes(blob[0:(n_hdr - 1) * 4]) + bytes(blob[n_hdr * 4:])) & 0xFFFFFFFF
        blob[(n_hdr - 1) * 4:n_hdr * 4] = struct.pack("<I", crc)
        return bytes(blob)


def emit(qg: QGraph, hw: HwConfig, base: int = 0x20000000, scratch: int = 0x28000000,
         wait_prev_all: bool = True) -> Program:
    g = qg.graph
    alloc = allocate(g)
    params = bytearray()

    def add_param(data: bytes) -> int:
        off = _align(len(params), PARAM_ALIGN)
        params.extend(b"\0" * (off-len(params)))
        params.extend(data)
        return off

    # Parameter region layout is only known after the descriptor count, so
    # offsets are relative here and rebased below.
    descs = []
    names = []
    rel = []   # (descriptor, list of (field, param offset)) to rebase

    def src_fields(d: Descriptor, sources: list, h: int, w: int):
        assert 1 <= len(sources) <= 2, f"{len(sources)} sources need COPY ops"
        s0 = sources[0]
        d.set("src0_base", scratch + s0.placement.base_offset)
        d.set("src0_plane_stride", s0.placement.buffer.plane_stride)
        d.set("src0_row_stride", s0.placement.buffer.row_stride)
        d.set("src0_planes", s0.placement.planes)
        if s0.upsample:
            d.flag("UPS0")
        if len(sources) == 2:
            s1 = sources[1]
            d.flag("TWO_SRC")
            d.set("src1_base", scratch + s1.placement.base_offset)
            d.set("src1_plane_stride", s1.placement.buffer.plane_stride)
            d.set("src1_row_stride", s1.placement.buffer.row_stride)
            d.set("src1_planes", s1.placement.planes)
            if s1.upsample:
                d.flag("UPS1")

    for op in g.ops:
        if op.kind in ("CONCAT", "SPLIT", "UPSAMPLE2"):
            continue
        d = Descriptor()
        out = op.outputs[0]
        to = g.tensors[out]
        ti = g.tensors[op.inputs[0]]
        d.set("in_h", ti.h)
        d.set("in_w", ti.w)
        d.set("out_h", to.h)
        d.set("out_w", to.w)
        d.set("ic", ti.c)
        d.set("oc", to.c)
        src_fields(d, alloc.sources(op.inputs[0]), ti.h, ti.w)
        po = alloc.place[out]
        d.set("out_base", scratch + po.base_offset)
        d.set("out_plane_stride", po.buffer.plane_stride)
        d.set("out_row_stride", po.buffer.row_stride)
        d.set("zp_in", qg.tq[op.inputs[0]].zp)
        d.set("zp_out", qg.tq[out].zp)
        if op.kind == "CONV":
            qc = qg.convs[op.name]
            k, s = op.attrs["k"], op.attrs["s"]
            d.set("opcode", isa.OPCODES["CONV"])
            d.set("k", k)
            d.set("stride", s)
            for p in ("pad_t", "pad_l", "pad_b", "pad_r"):
                d.set(p, op.attrs["pad"])
            wbytes, per_oct = weightpack.pack_weights(qc.w_q, hw)
            oc_pad = _ceil_div(to.c, hw.n_oc) * hw.n_oc
            pbytes = weightpack.pack_params(qc.bias_q, qc.mult, qc.shift, qc.zp_out, oc_pad)
            fields = [("w_base", add_param(wbytes)), ("param_base", add_param(pbytes))]
            d.set("w_bytes_per_oct", per_oct)
            # The per channel parameter block carries the requantization zero
            # point; zp_out of the descriptor is the zero point after the
            # activation, which the residual add and the channel padding use.
            if qc.res is not None:
                d.set("zp_out", qc.res["zp_y"])
            if qc.lut is not None:
                d.flag("SILU")
                fields.append(("lut_base", add_param(weightpack.pack_lut(qc.lut))))
            if qc.res is not None:
                d.flag("RESIDUAL")
                pr = alloc.sources(op.attrs["residual"])
                assert len(pr) == 1 and not pr[0].upsample
                d.set("res_base", scratch + pr[0].placement.base_offset)
                d.set("res_plane_stride", pr[0].placement.buffer.plane_stride)
                d.set("res_row_stride", pr[0].placement.buffer.row_stride)
                d.set("zp_res", qc.res["zp_r"])
                d.set("zp_out2", qc.res["zp_out"])
                d.set("res_mult_a", qc.res["mult_a"])
                d.set("res_shift_a", qc.res["shift_a"])
                d.set("res_mult_b", qc.res["mult_b"])
                d.set("res_shift_b", qc.res["shift_b"])
            ic_bytes = _ceil_div(ti.c, layout.CH_GROUP) * layout.CH_GROUP
            t = tile_conv(to.h, to.w, ti.w, k, s, ic_bytes, hw)
            d.set("tile_rows", t.tile_rows)
            d.set("tile_px", t.tile_px)
            d.set("n_tiles", t.n_tiles)
            d.set("ring_rows", t.ring_rows)
            rel.append((d, fields))
        elif op.kind == "MAXPOOL5":
            d.set("opcode", isa.OPCODES["MAXPOOL5"])
            d.set("k", 5)
            d.set("stride", 1)
            for p in ("pad_t", "pad_l", "pad_b", "pad_r"):
                d.set(p, 2)
            d.set("tile_rows", to.h)
            d.set("tile_px", to.h * to.w)
            d.set("n_tiles", 1)
            d.set("ring_rows", to.h)
        else:
            raise NotImplementedError(op.kind)
        if wait_prev_all and descs:
            d.flag("WAIT_PREV")
        d.set("tag", len(descs))
        descs.append(d)
        names.append(op.name)

    descs[-1].flag("LAST")
    descs[-1].flag("IRQ")

    prog = Program(base, scratch, descs, bytes(params), alloc, [], g.inputs[0], 0, 0, ())
    for d, fields in rel:
        for name, off in fields:
            d.set(name, base + prog.param_off + off)
    for d in descs:
        d.finalize()
    prog.desc_names = names
    pin = alloc.place[g.inputs[0]]
    prog.input_offset = pin.base_offset
    prog.input_bytes = pin.buffer.size
    prog.input_shape = (g.tensors[g.inputs[0]].c, pin.buffer.h, pin.buffer.w)
    for o in g.outputs:
        p = alloc.place[o]
        t = g.tensors[o]
        prog.outputs.append(OutputInfo(o, p.base_offset, t.c, t.h, t.w, qg.tq[o].scale, qg.tq[o].zp))
    return prog
