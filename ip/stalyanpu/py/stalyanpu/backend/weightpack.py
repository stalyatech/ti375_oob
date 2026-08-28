"""Weight, parameter and table packing for the array.

Weights are stored in the order the weight FIFO consumes them:

    [oct][icg][tap][chain][dsp][2 bytes]

with oct the 64 channel output tile, icg the 32 channel input group, tap
the (ky, kx) position row major, chain c covering output channels 2c and
2c+1, dsp i covering input channel icg*32+i. The two bytes are the low lane
weight (even output channel) followed by the high lane weight (odd output
channel). Padded channels hold zero.

Per output channel parameters are 8 bytes: int32 bias, uint16 multiplier,
uint8 shift, int8 zero point. The activation table is 256 bytes indexed by
the int8 code plus 128.
"""

from __future__ import annotations

import struct

import numpy as np

from ..hwcfg import HwConfig

PARAM_BYTES = 8
LUT_BYTES = 256


def _ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


def pack_weights(w_q: np.ndarray, hw: HwConfig) -> tuple:
    """Returns (bytes, bytes_per_oct)."""
    oc, ic, k, _ = w_q.shape
    n_oct = _ceil_div(oc, hw.n_oc)
    n_icg = _ceil_div(ic, hw.n_ic)
    oc_pad = n_oct * hw.n_oc
    ic_pad = n_icg * hw.n_ic
    full = np.zeros((oc_pad, ic_pad, k, k), dtype=np.int8)
    full[:oc, :ic] = w_q
    # [oct][icg][ky][kx][chain][dsp][lane]
    arr = full.reshape(n_oct, hw.n_chain, 2, n_icg, hw.n_ic, k, k)
    arr = arr.transpose(0, 3, 5, 6, 1, 4, 2)
    data = np.ascontiguousarray(arr).tobytes()
    per_oct = n_icg * k * k * hw.n_chain * hw.n_ic * 2
    assert len(data) == n_oct * per_oct
    return data, per_oct


def unpack_weights(data, oc: int, ic: int, k: int, hw: HwConfig) -> np.ndarray:
    n_oct = _ceil_div(oc, hw.n_oc)
    n_icg = _ceil_div(ic, hw.n_ic)
    arr = np.frombuffer(bytes(data), dtype=np.int8).reshape(n_oct, n_icg, k, k, hw.n_chain, hw.n_ic, 2)
    full = arr.transpose(0, 4, 6, 1, 5, 2, 3).reshape(n_oct * hw.n_oc, n_icg * hw.n_ic, k, k)
    return np.ascontiguousarray(full[:oc, :ic])


def pack_params(bias_q, mult, shift, zp: int, oc_pad: int) -> bytes:
    out = bytearray()
    n = len(bias_q)
    for c in range(oc_pad):
        if c < n:
            out += struct.pack("<iHBb", int(bias_q[c]), int(mult[c]), int(shift[c]), int(zp))
        else:
            out += struct.pack("<iHBb", 0, 1 << 15, 15, int(zp))
    return bytes(out)


def unpack_params(data, oc: int) -> tuple:
    bias = np.zeros(oc, dtype=np.int64)
    mult = np.zeros(oc, dtype=np.int64)
    shift = np.zeros(oc, dtype=np.int64)
    zp = 0
    for c in range(oc):
        b, m, s, z = struct.unpack_from("<iHBb", bytes(data), c * PARAM_BYTES)
        bias[c], mult[c], shift[c], zp = b, m, s, z
    return bias, mult, shift, zp


def pack_lut(lut: np.ndarray) -> bytes:
    assert lut.shape == (LUT_BYTES,)
    return lut.astype(np.int8).tobytes()
