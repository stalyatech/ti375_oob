"""NC32HW tensor layout in DDR.

A CHW int8 tensor is stored as ceil(C / 32) planes, each plane holding
H * W * 32 bytes in row major order with the 32 channels of a pixel
contiguous. Padded channels of the last plane carry ``pad_value``.
"""

from __future__ import annotations

import numpy as np

CH_GROUP = 32


def n_planes(c: int) -> int:
    return (c + CH_GROUP - 1) // CH_GROUP


def plane_bytes(h: int, w: int) -> int:
    return h * w * CH_GROUP


def tensor_bytes(c: int, h: int, w: int) -> int:
    return n_planes(c) * plane_bytes(h, w)


def pack(t: np.ndarray, pad_value: int = 0) -> bytes:
    """CHW int8 -> NC32HW bytes."""
    c, h, w = t.shape
    cp = n_planes(c) * CH_GROUP
    full = np.full((cp, h, w), pad_value, dtype=np.int8)
    full[:c] = t
    # [cg][h][w][32]
    arr = full.reshape(n_planes(c), CH_GROUP, h, w).transpose(0, 2, 3, 1)
    return np.ascontiguousarray(arr).tobytes()


def unpack(buf, c: int, h: int, w: int) -> np.ndarray:
    """NC32HW bytes -> CHW int8 with the first c channels."""
    np_ = n_planes(c)
    arr = np.frombuffer(bytes(buf[:np_ * plane_bytes(h, w)]), dtype=np.int8)
    arr = arr.reshape(np_, h, w, CH_GROUP).transpose(0, 3, 1, 2).reshape(np_ * CH_GROUP, h, w)
    return np.ascontiguousarray(arr[:c])


def read_planes(mem, base: int, plane_stride: int, row_stride: int, planes: int, h: int, w: int) -> np.ndarray:
    """Gather ``planes`` channel groups from memory into CHW int8 [planes*32, h, w]."""
    out = np.empty((planes * CH_GROUP, h, w), dtype=np.int8)
    for p in range(planes):
        for y in range(h):
            off = base + p * plane_stride + y * row_stride
            row = np.frombuffer(bytes(mem[off:off + w * CH_GROUP]), dtype=np.int8).reshape(w, CH_GROUP)
            out[p * CH_GROUP:(p + 1) * CH_GROUP, y, :] = row.T
    return out


def write_planes(mem, base: int, plane_stride: int, row_stride: int, t: np.ndarray) -> None:
    """Scatter CHW int8 [planes*32, h, w] into memory."""
    cp, h, w = t.shape
    assert cp % CH_GROUP == 0
    for p in range(cp // CH_GROUP):
        for y in range(h):
            off = base + p * plane_stride + y * row_stride
            row = np.ascontiguousarray(t[p * CH_GROUP:(p + 1) * CH_GROUP, y, :].T)
            mem[off:off + w * CH_GROUP] = row.tobytes()
