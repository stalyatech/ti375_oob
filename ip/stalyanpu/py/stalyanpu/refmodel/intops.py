"""Bit exact integer operators of the accelerator.

Tensors are CHW int8 arrays (batch 1). Convolution accumulates int8 products
exactly: the im2col matrix product runs in float64, where every partial sum
stays below 2^53 (at most 4608 products of magnitude 2^14 per output), so
the result equals the integer sum the hardware forms.
"""

from __future__ import annotations

import numpy as np

from .fixedpoint import INT8_MAX, INT8_MIN, requant

MAX_K = (1 << 53) // (1 << 14)   # products per output that stay exact in float64


def pad_chw(x: np.ndarray, pad: int, value: int) -> np.ndarray:
    if pad == 0:
        return x
    c, h, w = x.shape
    out = np.full((c, h + 2 * pad, w + 2 * pad), value, dtype=x.dtype)
    out[:, pad:pad + h, pad:pad + w] = x
    return out


def im2col(x: np.ndarray, k: int, stride: int) -> tuple:
    """x is already padded CHW. Returns (cols [OH*OW, C*k*k], OH, OW)."""
    c, h, w = x.shape
    oh = (h-k) // stride + 1
    ow = (w-k) // stride + 1
    cols = np.empty((oh * ow, c * k * k), dtype=np.float64)
    idx = 0
    for ci in range(c):
        for ky in range(k):
            for kx in range(k):
                patch = x[ci, ky:ky + stride * oh:stride, kx:kx + stride * ow:stride]
                cols[:, idx] = patch.reshape(-1)
                idx += 1
    return cols, oh, ow


def conv2d_int(x: np.ndarray, w: np.ndarray, stride: int, pad: int, pad_value: int) -> np.ndarray:
    """int8 conv, returns int64 accumulators [OC, OH, OW]."""
    oc, ic, k, _ = w.shape
    assert x.shape[0] == ic, (x.shape, w.shape)
    assert ic * k * k <= MAX_K
    xp = pad_chw(x, pad, pad_value)
    cols, oh, ow = im2col(xp, k, stride)
    wm = w.reshape(oc, ic * k * k).astype(np.float64)
    acc = cols @ wm.T                        # exact in float64
    return np.rint(acc).astype(np.int64).T.reshape(oc, oh, ow)


def requant_channels(acc: np.ndarray, bias, mult, shift, zp_out: int) -> np.ndarray:
    """Per output channel requantization of [OC, H, W] accumulators."""
    oc = acc.shape[0]
    b = np.asarray(bias, dtype=np.int64).reshape(oc, 1, 1)
    m = np.asarray(mult, dtype=np.int64).reshape(oc, 1, 1)
    s = np.asarray(shift, dtype=np.int64).reshape(oc, 1, 1)
    return requant(acc, b, m, s, zp_out)


def apply_lut(q: np.ndarray, lut: np.ndarray) -> np.ndarray:
    return lut[q.astype(np.int16) + 128]


def rescale_int8(v: np.ndarray, zp_in: int, mult: int, shift: int) -> np.ndarray:
    """((v-zp_in) * mult + 2^(shift-1)) >> shift as int64, no saturation."""
    d = v.astype(np.int64) - np.int64(zp_in)
    prod = d * np.int64(mult)
    rnd = (1 << (shift - 1)) if shift > 0 else 0
    return np.right_shift(prod + rnd, shift)


def residual_add(y, r, mult_a, shift_a, mult_b, shift_b, zp_y, zp_r, zp_out) -> np.ndarray:
    """Residual add of the epilogue with two rescale paths."""
    s = rescale_int8(y, zp_y, mult_a, shift_a) + rescale_int8(r, zp_r, mult_b, shift_b) + np.int64(zp_out)
    return np.clip(s, INT8_MIN, INT8_MAX).astype(np.int8)


def add_same_scale(a: np.ndarray, b: np.ndarray, zp: int) -> np.ndarray:
    s = a.astype(np.int64) + b.astype(np.int64) - np.int64(zp)
    return np.clip(s, INT8_MIN, INT8_MAX).astype(np.int8)


def maxpool5(x: np.ndarray, pad_value: int = INT8_MIN) -> np.ndarray:
    """5x5 stride 1 pad 2 max pool. Padding uses the minimum int8 so it never wins."""
    xp = pad_chw(x, 2, pad_value)
    c, h, w = x.shape
    out = np.full((c, h, w), INT8_MIN, dtype=np.int8)
    for ky in range(5):
        for kx in range(5):
            np.maximum(out, xp[:, ky:ky + h, kx:kx + w], out=out)
    return out


def upsample2(x: np.ndarray) -> np.ndarray:
    return np.repeat(np.repeat(x, 2, axis=1), 2, axis=2)


def concat_channels(parts: list) -> np.ndarray:
    return np.concatenate(parts, axis=0)


def split_channels(x: np.ndarray, sizes: list) -> list:
    out = []
    start = 0
    for s in sizes:
        out.append(x[start:start + s])
        start += s
    assert start == x.shape[0]
    return out
