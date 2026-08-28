"""Tile selection shared by the emitter and the performance model.

Tiles are whole output rows. The row count is the largest that keeps the
tile inside one accumulator bank (p_max pixels) and its input footprint,
halo included, inside half of the input buffer so the other half can
prefetch the next tile.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..hwcfg import HwConfig


@dataclass
class Tiling:
    tile_rows: int
    tile_px: int
    n_tiles: int
    ring_rows: int


def choose_rows(out_h: int, out_w: int, in_w: int, k: int, s: int, ic_bytes: int, hw: HwConfig) -> int:
    """ic_bytes is the byte count of one input pixel (padded channels)."""
    rows = max(1, hw.p_max // out_w)
    rows = min(rows, out_h)
    budget = hw.ibuf_bytes // 2
    while rows > 1:
        rows_in = rows * s + k - 1
        if rows_in * in_w * ic_bytes <= budget:
            break
        rows -= 1
    return rows


def tile_conv(out_h: int, out_w: int, in_w: int, k: int, s: int, ic_bytes: int, hw: HwConfig) -> Tiling:
    rows = choose_rows(out_h, out_w, in_w, k, s, ic_bytes, hw)
    n_tiles = (out_h + rows - 1) // rows
    return Tiling(rows, rows * out_w, n_tiles, rows * s + k - 1)
