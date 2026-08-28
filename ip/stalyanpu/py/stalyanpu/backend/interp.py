"""Descriptor interpreter.

Executes a blob against a byte addressable memory using only the fields of
the descriptors, the packed parameters and the integer operators of the
reference model. Its outputs must match ``QRunner`` bit for bit; that check
validates the layout, the packing, the allocation and the emitter before
any RTL exists, and the same code produces the golden vectors.
"""

from __future__ import annotations

import struct

import numpy as np

from ..hwcfg import HwConfig
from ..refmodel import intops
from . import isa, layout, weightpack
from .emit import HEADER_BYTES, Descriptor


class Memory:
    """Sparse byte memory made of 1 MB pages."""

    PAGE = 1 << 20

    def __init__(self):
        self.pages = {}

    def _page(self, addr: int, create: bool) -> bytearray | None:
        p = addr // self.PAGE
        if p not in self.pages:
            if not create:
                return None
            self.pages[p] = bytearray(self.PAGE)
        return self.pages[p]

    def write(self, addr: int, data) -> None:
        data = bytes(data)
        while data:
            page = self._page(addr, True)
            off = addr % self.PAGE
            n = min(len(data), self.PAGE - off)
            page[off:off + n] = data[:n]
            data = data[n:]
            addr += n

    def read(self, addr: int, n: int) -> bytes:
        out = bytearray()
        while n > 0:
            page = self._page(addr, False)
            off = addr % self.PAGE
            m = min(n, self.PAGE - off)
            out += page[off:off + m] if page is not None else bytes(m)
            n -= m
            addr += m
        return bytes(out)

    def __getitem__(self, sl):
        return self.read(sl.start, sl.stop-sl.start)

    def __setitem__(self, sl, data):
        self.write(sl.start, data)

    def ranges(self) -> list:
        """(addr, bytes) of every written page, merged when contiguous."""
        out = []
        for p in sorted(self.pages):
            addr = p * self.PAGE
            if out and out[-1][0] + len(out[-1][1]) == addr:
                out[-1] = (out[-1][0], out[-1][1] + bytes(self.pages[p]))
            else:
                out.append((addr, bytes(self.pages[p])))
        return out


def read_header(mem, base: int) -> dict:
    n = len(isa.BLOB_HEADER)
    words = struct.unpack(f"<{n}I", mem.read(base, n * 4))
    hdr = {name: v for (name, _), v in zip(isa.BLOB_HEADER, words)}
    assert hdr["magic"] == isa.BLOB_MAGIC, "bad blob magic"
    assert hdr["version"] == isa.ISA_VERSION
    outs = []
    for i in range(hdr["n_outputs"]):
        e = struct.unpack("<8I", mem.read(base + hdr["outputs_off"] + i * 32, 32))
        name = mem.read(base + e[6], 256).split(b"\0")[0].decode()
        zp = e[5] - (1 << 32) if e[5] >= (1 << 31) else e[5]
        outs.append({"name": name, "offset": e[0], "h": e[1], "w": e[2], "c": e[3],
                     "scale": e[4] / 65536.0, "zp": zp})
    hdr["outputs"] = outs
    return hdr


def read_descriptors(mem, base: int, hdr: dict) -> list:
    descs = []
    for i in range(hdr["desc_count"]):
        d = Descriptor.from_bytes(mem.read(base + hdr["desc_off"] + i * isa.DESC_BYTES, isa.DESC_BYTES))
        if not d.crc_ok():
            raise ValueError(f"descriptor {i}: bad CRC")
        descs.append(d)
    return descs


def _read_source(mem, base, plane_stride, row_stride, planes, h, w, ups):
    if ups:
        src = layout.read_planes(mem, base, plane_stride, row_stride, planes, h // 2, w // 2)
        return intops.upsample2(src)
    return layout.read_planes(mem, base, plane_stride, row_stride, planes, h, w)


def run_descriptor(mem, d: Descriptor, hw: HwConfig) -> None:
    op = d.get("opcode")
    if op in (isa.OPCODES["NOP"], isa.OPCODES["END"], isa.OPCODES["BARRIER"]):
        return
    in_h, in_w = d.get("in_h"), d.get("in_w")
    out_h, out_w = d.get("out_h"), d.get("out_w")
    ic, oc = d.get("ic"), d.get("oc")
    x = _read_source(mem, d.get("src0_base"), d.get("src0_plane_stride"), d.get("src0_row_stride"),
                     d.get("src0_planes"), in_h, in_w, d.has_flag("UPS0"))
    if d.has_flag("TWO_SRC"):
        x1 = _read_source(mem, d.get("src1_base"), d.get("src1_plane_stride"), d.get("src1_row_stride"),
                          d.get("src1_planes"), in_h, in_w, d.has_flag("UPS1"))
        x = np.concatenate([x, x1], axis=0)
    zp_in = d.get("zp_in", signed=True)
    x = x[:ic]
    if op == isa.OPCODES["CONV"]:
        k, s = d.get("k"), d.get("stride")
        pads = [d.get(p) for p in ("pad_t", "pad_l", "pad_b", "pad_r")]
        assert pads == [k // 2] * 4, pads
        n_oct = (oc + hw.n_oc - 1) // hw.n_oc
        wq = weightpack.unpack_weights(mem.read(d.get("w_base"), n_oct * d.get("w_bytes_per_oct")), oc, ic, k, hw)
        bias, mult, shift, zp_pre = weightpack.unpack_params(mem.read(d.get("param_base"), oc * weightpack.PARAM_BYTES), oc)
        acc = intops.conv2d_int(x, wq, s, k // 2, zp_in)
        q = intops.requant_channels(acc, bias, mult, shift, zp_pre)
        if d.has_flag("SILU"):
            lut = np.frombuffer(mem.read(d.get("lut_base"), 256), dtype=np.int8)
            q = intops.apply_lut(q, lut)
        if d.has_flag("RESIDUAL"):
            planes = (oc + layout.CH_GROUP - 1) // layout.CH_GROUP
            r = layout.read_planes(mem, d.get("res_base"), d.get("res_plane_stride"), d.get("res_row_stride"),
                                   planes, out_h, out_w)[:oc]
            q = intops.residual_add(q, r, d.get("res_mult_a"), d.get("res_shift_a"), d.get("res_mult_b"),
                                    d.get("res_shift_b"), d.get("zp_out", signed=True),
                                    d.get("zp_res", signed=True), d.get("zp_out2", signed=True))
        # Tiling consistency: the hardware iterates tiles, the result is the same.
        assert d.get("n_tiles") == (out_h + d.get("tile_rows") - 1) // d.get("tile_rows")
        assert d.get("tile_px") == d.get("tile_rows") * out_w
    elif op == isa.OPCODES["MAXPOOL5"]:
        q = intops.maxpool5(x)
    else:
        raise NotImplementedError(f"opcode {op}")
    oc_pad = (oc + layout.CH_GROUP - 1) // layout.CH_GROUP * layout.CH_GROUP
    fill = d.get("zp_out2", signed=True) if d.has_flag("RESIDUAL") else d.get("zp_out", signed=True)
    full = np.full((oc_pad, out_h, out_w), fill, dtype=np.int8)
    full[:oc] = q
    layout.write_planes(mem, d.get("out_base"), d.get("out_plane_stride"), d.get("out_row_stride"), full)


def run_blob(mem, base: int, hw: HwConfig, on_descriptor=None) -> dict:
    """Execute the descriptor list of the blob at ``base``. Returns the
    output tensors as CHW int8 arrays keyed by name."""
    hdr = read_header(mem, base)
    descs = read_descriptors(mem, base, hdr)
    for i, d in enumerate(descs):
        run_descriptor(mem, d, hw)
        if on_descriptor:
            on_descriptor(i, d)
        if d.has_flag("LAST"):
            break
    outs = {}
    for o in hdr["outputs"]:
        planes = layout.n_planes(o["c"])
        t = layout.read_planes(mem, hdr["scratch_base"] + o["offset"], layout.plane_bytes(o["h"], o["w"]),
                               o["w"] * layout.CH_GROUP, planes, o["h"], o["w"])
        outs[o["name"]] = t[:o["c"]]
    return outs
