"""Vectors for the conv unit testbench (tb_conv_unit).

One convolution layer with the input already resident in the ibuf, weights
in consumption order, per channel parameters, activation table, residual
words and the expected output words in emission order:

    for tile: for oct: for pixel: for plane of the oct (valid planes only)

Files (all $readmemh): cfg.hex (32-bit words, see CFG), ibuf.hex (256-bit
words), w.hex (256-bit), prm.hex (64-bit), lut.hex (8-bit), res.hex
(256-bit), golden.hex (256-bit).
"""

from __future__ import annotations

import os
import struct

import numpy as np

from ..backend import layout, weightpack
from ..backend.tiler import tile_conv
from ..hwcfg import HwConfig
from ..refmodel import intops
from ..refmodel.fixedpoint import quantize_multiplier, silu_lut

CFG = ["in_h", "in_w", "out_h", "out_w", "ic", "oc", "k", "stride", "pad", "zp_in", "n_icg", "n_oct",
       "n_planes", "silu", "residual", "zp_out", "zp_res", "zp_out2", "res_mult_a", "res_shift_a",
       "res_mult_b", "res_shift_b", "tile_rows", "n_tiles", "n_ibuf_words", "n_w_words", "n_out_words",
       "n_res_words", "plane_words", "n_prm"]


def _ceil_div(a, b):
    return (a + b - 1) // b


def _hex_words(path, data: bytes, width_bytes: int):
    with open(path, "w", newline="\n") as fh:
        for i in range(0, len(data), width_bytes):
            fh.write(data[i:i + width_bytes][::-1].hex() + "\n")


def conv_unit_vectors(out_dir: str, hw: HwConfig, x: np.ndarray, w_q: np.ndarray, bias_q, mult, shift,
                      zp_in: int, zp_pre: int, stride: int, lut=None, zp_out: int = 0,
                      residual=None, zp_res: int = 0, zp_out2: int = 0,
                      res=(1 << 15, 15, 1 << 15, 15), tile_rows: int | None = None) -> dict:
    """x: CHW int8, w_q: [OC, IC, k, k] int8, residual: CHW int8 of the output shape or None."""
    ic, in_h, in_w = x.shape
    oc, _, k, _ = w_q.shape
    pad = k // 2
    out_h = (in_h + 2 * pad-k) // stride + 1
    out_w = (in_w + 2 * pad-k) // stride + 1
    n_icg = _ceil_div(ic, hw.n_ic)
    n_oct = _ceil_div(oc, hw.n_oc)
    n_planes = _ceil_div(oc, 32)
    ic_planes = _ceil_div(ic, 32)
    # The ibuf holds one 32 byte word per (pixel, plane); a reduced array
    # with n_ic < 32 reads 32 / n_ic input groups out of each word.

    # Expected output.
    acc = intops.conv2d_int(x, w_q, stride, pad, zp_in)
    q = intops.requant_channels(acc, bias_q, mult, shift, zp_pre)
    if lut is not None:
        q = intops.apply_lut(q, lut)
    zp_fill = zp_out
    if residual is not None:
        q = intops.residual_add(q, residual, res[0], res[1], res[2], res[3], zp_out, zp_res, zp_out2)
        zp_fill = zp_out2
    full = np.full((n_planes * 32, out_h, out_w), zp_fill, dtype=np.int8)
    full[:oc] = q

    if tile_rows is None:
        t = tile_conv(out_h, out_w, in_w, k, stride, ic_planes * 32, hw)
        tile_rows = t.tile_rows
    n_tiles = _ceil_div(out_h, tile_rows)

    # ibuf image: one 32 channel plane after another (the DDR layout), rows,
    # columns; padded channels carry zp_in.
    words = bytearray(layout.pack(x, zp_in))
    plane_words = in_h * in_w

    # The weight stream is consumed once per spatial tile (the DMA replays
    # it), so the vector holds n_tiles copies.
    wbytes_once, per_oct = weightpack.pack_weights(w_q, hw)
    wbytes_all = wbytes_once * n_tiles
    prm = weightpack.pack_params(bias_q, mult, shift, zp_pre, n_oct * hw.n_oc)

    # Output and residual words in emission order: per tile and output
    # channel tile, plane major (every pixel of a plane, then the next plane).
    out_words = bytearray()
    res_words = bytearray()
    if residual is not None:
        rfull = np.full((n_planes * 32, out_h, out_w), zp_res, dtype=np.int8)
        rfull[:oc] = residual
    row = 0
    for t in range(n_tiles):
        rows = min(tile_rows, out_h-row)
        for o in range(n_oct):
            for win in range(hw.n_oc // 32):
                plane = o * (hw.n_oc // 32) + win
                if plane >= n_planes:
                    continue
                for r in range(rows):
                    for c in range(out_w):
                        out_words += full[plane * 32:(plane + 1) * 32, row + r, c].tobytes()
                        if residual is not None:
                            res_words += rfull[plane * 32:(plane + 1) * 32, row + r, c].tobytes()
        row += rows

    os.makedirs(out_dir, exist_ok=True)
    cfg = {
        "in_h": in_h, "in_w": in_w, "out_h": out_h, "out_w": out_w, "ic": ic, "oc": oc, "k": k,
        "stride": stride, "pad": pad, "zp_in": zp_in & 0xFF, "n_icg": n_icg, "n_oct": n_oct,
        "n_planes": n_planes, "silu": int(lut is not None), "residual": int(residual is not None),
        "zp_out": zp_out & 0xFF, "zp_res": zp_res & 0xFF, "zp_out2": zp_out2 & 0xFF,
        "res_mult_a": res[0], "res_shift_a": res[1], "res_mult_b": res[2], "res_shift_b": res[3],
        "tile_rows": tile_rows, "n_tiles": n_tiles, "n_ibuf_words": len(words) // 32,
        "n_w_words": len(wbytes_all) // 32, "n_out_words": len(out_words) // 32,
        "n_res_words": len(res_words) // 32, "plane_words": plane_words, "n_prm": n_oct * hw.n_oc,
    }
    with open(os.path.join(out_dir, "cfg.hex"), "w", newline="\n") as fh:
        for name in CFG:
            fh.write(f"{cfg[name] & 0xFFFFFFFF:08x}\n")
    _hex_words(os.path.join(out_dir, "ibuf.hex"), bytes(words), 32)
    _hex_words(os.path.join(out_dir, "w.hex"), wbytes_all, 32)
    _hex_words(os.path.join(out_dir, "prm.hex"), prm, 8)
    _hex_words(os.path.join(out_dir, "lut.hex"), (lut if lut is not None else np.zeros(256, np.int8)).astype(np.int8).tobytes(), 1)
    _hex_words(os.path.join(out_dir, "res.hex"), bytes(res_words) if res_words else b"\0" * 32, 32)
    _hex_words(os.path.join(out_dir, "golden.hex"), bytes(out_words), 32)
    return cfg


def random_case(out_dir: str, hw: HwConfig, ic: int, oc: int, k: int, stride: int, in_h: int, in_w: int,
                silu: bool, residual: bool, seed: int = 1, tile_rows: int | None = None) -> dict:
    """Random layer with realistic parameter ranges."""
    rng = np.random.default_rng(seed)
    x = rng.integers(-128, 128, (ic, in_h, in_w), dtype=np.int8)
    w_q = rng.integers(-127, 128, (oc, ic, k, k), dtype=np.int8)
    zp_in = int(rng.integers(-128, 128))
    # Scale the accumulator into a plausible int8 range.
    s_acc = 1.0 / (127.0 * np.sqrt(ic * k * k) * 4.0)
    bias_q = rng.integers(-20000, 20000, oc).astype(np.int64)
    mult = np.zeros(oc, dtype=np.int64)
    shift = np.zeros(oc, dtype=np.int64)
    for c in range(oc):
        m, s = quantize_multiplier(s_acc * float(rng.uniform(0.5, 2.0)))
        mult[c], shift[c] = m, s
    zp_pre = int(rng.integers(-128, 128))
    lut = silu_lut(0.05, zp_pre, 0.03, -120) if silu else None
    zp_out = -120 if silu else zp_pre
    r = rng.integers(-128, 128, (oc, (in_h + 2 * (k // 2)-k) // stride + 1, (in_w + 2 * (k // 2)-k) // stride + 1),
                     dtype=np.int8) if residual else None
    return conv_unit_vectors(out_dir, hw, x, w_q, bias_q, mult, shift, zp_in, zp_pre, stride, lut, zp_out,
                             r, zp_res=zp_out, zp_out2=zp_out, tile_rows=tile_rows)


CASES = {
    # name: (hwcfg, ic, oc, k, stride, in_h, in_w, silu, residual, tile_rows)
    "conv1x1":      ("small512", 32, 32, 1, 1, 8, 12, False, False, None),
    "conv3x3":      ("small512", 32, 64, 3, 1, 9, 11, True, False, None),
    "conv3x3s2":    ("small512", 64, 32, 3, 2, 10, 13, True, False, None),
    "conv_res":     ("small512", 32, 32, 3, 1, 8, 10, True, True, None),
    "conv_pad80":   ("small512", 48, 80, 1, 1, 6, 9, False, False, None),
    "conv_tiles":   ("small512", 32, 32, 3, 1, 12, 8, True, False, 2),
    "conv_full":    ("full2048", 40, 96, 3, 1, 6, 10, True, False, None),
}


def write_case(name: str, out_dir: str) -> dict:
    from ..hwcfg import load

    hwname, ic, oc, k, s, h, w, silu, res, tr = CASES[name]
    return random_case(out_dir, load(hwname), ic, oc, k, s, h, w, silu, res, tile_rows=tr)


if __name__ == "__main__":
    import sys

    print(write_case(sys.argv[1], sys.argv[2]))
