"""Bit exact fixed point arithmetic of the StalyaNPU epilogue.

Requantization of a 32-bit accumulator to int8 uses a 16-bit multiplier and
an arithmetic right shift with round half up:

    q = sat8( ((acc + bias) * m + 2^(sh-1)) >> sh ) + zp_out )

with m in [2^15, 2^16) and sh in [0, 47]. The hardware computes the 48-bit
product in two DSP48 blocks and shifts it; this module is the reference the
RTL is checked against, so the arithmetic here is written with plain Python
integers first (``requant_scalar``) and vectorised second (``requant``).

The activation function after requantization is a 256 entry int8 to int8
table produced by ``silu_lut``.
"""

from __future__ import annotations

import math

import numpy as np

MULT_BITS = 16
MULT_MIN = 1 << (MULT_BITS - 1)
MULT_MAX = (1 << MULT_BITS) - 1
SHIFT_MAX = 47
INT8_MIN = -128
INT8_MAX = 127


def saturate_int8(x):
    return np.clip(x, INT8_MIN, INT8_MAX)


def quantize_multiplier(real_scale: float) -> tuple[int, int]:
    """Split a positive real scale into (m, sh) with real_scale ~= m * 2^-sh.

    m is normalised to [2^15, 2^16) so the relative error is below 2^-15.
    Scales that would need a shift outside [0, 47] raise ValueError; such
    values do not occur with int8 tensors of sane ranges.
    """
    if real_scale <= 0.0:
        raise ValueError("scale must be positive")
    mant, exp = math.frexp(real_scale)          # real = mant * 2^exp, mant in [0.5, 1)
    m = int(round(mant * (1 << MULT_BITS)))     # in [2^15, 2^16]
    sh = MULT_BITS - exp
    if m == (1 << MULT_BITS):
        m >>= 1
        sh -= 1
    if not (0 <= sh <= SHIFT_MAX):
        raise ValueError(f"shift {sh} out of range for scale {real_scale}")
    assert MULT_MIN <= m <= MULT_MAX
    return m, sh


def requant_scalar(acc: int, bias: int, m: int, sh: int, zp_out: int) -> int:
    """Reference requantization on Python integers (arbitrary precision)."""
    if not (MULT_MIN <= m <= MULT_MAX):
        raise ValueError("multiplier out of range")
    if not (0 <= sh <= SHIFT_MAX):
        raise ValueError("shift out of range")
    s = acc + bias
    if not (-(1 << 31) <= s < (1 << 31)):
        raise OverflowError("acc + bias does not fit in int32")
    prod = s * m
    if sh == 0:
        r = prod
    else:
        r = (prod + (1 << (sh - 1))) >> sh
    r += zp_out
    return max(INT8_MIN, min(INT8_MAX, r))


def requant(acc, bias, m, sh, zp_out):
    """Vectorised requantization. Arrays broadcast; m and sh may be per channel."""
    acc = np.asarray(acc, dtype=np.int64)
    bias = np.asarray(bias, dtype=np.int64)
    m = np.asarray(m, dtype=np.int64)
    sh = np.asarray(sh, dtype=np.int64)
    s = acc + bias
    if np.any(s < -(1 << 31)) or np.any(s >= (1 << 31)):
        raise OverflowError("acc + bias does not fit in int32")
    prod = s * m                                   # fits in int64: 32 + 16 bits
    rnd = np.where(sh > 0, np.left_shift(np.int64(1), np.maximum(sh - 1, 0)), 0)
    r = np.right_shift(prod + rnd, sh)             # arithmetic shift on int64
    r = r + np.int64(zp_out)
    return saturate_int8(r).astype(np.int8)


def silu_lut(s_in: float, zp_in: int, s_out: float, zp_out: int) -> np.ndarray:
    """256 entry table mapping int8 pre-activation codes to int8 SiLU codes.

    Entry index i corresponds to the int8 value (i - 128) so the table can be
    indexed with ``q + 128``; ``silu_lut(...)[np.int16(q) + 128]``.
    """
    q = np.arange(-128, 128, dtype=np.float64)
    x = s_in * np.subtract(q, zp_in)
    y = x / (1.0 + np.exp(-x))
    code = np.round(y / s_out) + zp_out
    return saturate_int8(code).astype(np.int8)
