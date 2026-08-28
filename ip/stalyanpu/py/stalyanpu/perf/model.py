"""Analytic cycle model of the StalyaNPU array.

Per conv layer:

    n_pass   = ceil(IC / n_ic) * k * k
    n_oct    = ceil(OC / n_oc)
    cyc_mac  = sum over tiles of n_oct * n_pass * (P_t + t_pass)
    cyc_tile = n_tiles * t_tile + exposed input fill of the first tile
    cyc_ddr  = bytes moved / bytes per cycle
    cycles   = max(cyc_mac + cyc_tile, cyc_ddr) + t_op

Tiles are whole output rows. The row count per tile is the largest that
keeps P_t <= p_max and the input footprint (with halo) inside half of the
input buffer, so the other half can prefetch the next tile.

The model is deliberately simple; it is calibrated against simulation cycle
counts (M6) and hardware counters (M8).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from ..hwcfg import HwConfig
from .layers import Layer


def _ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


def _pad_to(a: int, b: int) -> int:
    return _ceil_div(a, b) * b


@dataclass
class LayerEstimate:
    layer: Layer
    n_tiles: int
    rows_per_tile: int
    n_pass: int
    n_oct: int
    cyc_mac: int
    cyc_tile: int
    cyc_ddr: int
    cycles: int
    bytes_rd: int
    bytes_wr: int
    bound: str
    util: float

    @property
    def macs(self) -> int:
        return self.layer.macs


def choose_rows(layer: Layer, hw: HwConfig, ic_pad: int) -> int:
    """Largest whole row count per tile that fits the accumulator and ibuf."""
    rows = max(1, hw.p_max // layer.out_w)
    rows = min(rows, layer.out_h)
    budget = hw.ibuf_bytes // 2
    while rows > 1:
        rows_in = rows * layer.s + layer.k - 1
        if rows_in * layer.in_w * ic_pad <= budget:
            break
        rows -= 1
    return rows


def layer_cycles(layer: Layer, hw: HwConfig) -> LayerEstimate:
    bpc = hw.bytes_per_cycle
    if layer.kind == "maxpool5":
        c_pad = _pad_to(layer.ic, hw.ch_group)
        words = layer.out_h * layer.out_w * (c_pad // hw.ch_group)
        bytes_rd = layer.in_h * layer.in_w * c_pad
        bytes_wr = layer.out_h * layer.out_w * c_pad
        cyc_ddr = int(math.ceil((bytes_rd + bytes_wr) / bpc))
        cycles = max(words, cyc_ddr) + hw.t_op
        return LayerEstimate(layer, 1, layer.out_h, 0, 0, words, 0, cyc_ddr, cycles,
                             bytes_rd, bytes_wr, "ddr" if cyc_ddr > words else "mac", 0.0)

    ic_eff = hw.stem_ic_pad if layer.stem else layer.ic
    ic_pad = _pad_to(ic_eff, hw.n_ic)
    ic_layout = _pad_to(ic_eff, hw.ch_group) if not layer.stem else hw.stem_ic_pad
    oc_pad = _pad_to(layer.oc, hw.n_oc)
    oc_layout = _pad_to(layer.oc, hw.ch_group)
    n_pass = (ic_pad // hw.n_ic) * layer.k * layer.k
    n_oct = oc_pad // hw.n_oc

    rows = choose_rows(layer, hw, ic_layout)
    n_tiles = _ceil_div(layer.out_h, rows)

    cyc_mac = 0
    bytes_in = 0
    first_fill = 0
    remaining = layer.out_h
    for t in range(n_tiles):
        r = min(rows, remaining)
        remaining -= r
        p = r * layer.out_w
        cyc_mac += n_oct * n_pass * (p + hw.t_pass)
        rows_in = min(r * layer.s + layer.k - 1, layer.in_h)
        tile_in = rows_in * layer.in_w * ic_layout
        bytes_in += tile_in
        if t == 0:
            first_fill = int(math.ceil(tile_in / bpc))

    weight_bytes = layer.k * layer.k * ic_pad * oc_pad
    bytes_w = weight_bytes * n_tiles
    bytes_out = layer.out_h * layer.out_w * oc_layout
    bytes_res = bytes_out if layer.residual else 0
    bytes_rd = bytes_in + bytes_w + bytes_res
    bytes_wr = bytes_out

    cyc_tile = n_tiles * hw.t_tile + first_fill
    cyc_ddr = int(math.ceil((bytes_rd + bytes_wr) / bpc))
    compute = cyc_mac + cyc_tile
    cycles = max(compute, cyc_ddr) + hw.t_op
    util = layer.macs / (cycles * hw.macs_per_cycle) if cycles else 0.0
    bound = "ddr" if cyc_ddr > compute else "mac"
    return LayerEstimate(layer, n_tiles, rows, n_pass, n_oct, cyc_mac, cyc_tile, cyc_ddr,
                         cycles, bytes_rd, bytes_wr, bound, util)


@dataclass
class NetEstimate:
    hw: HwConfig
    layers: list
    cpu_ms: float

    @property
    def cycles(self) -> int:
        return sum(e.cycles for e in self.layers)

    @property
    def macs(self) -> int:
        return sum(e.macs for e in self.layers)

    @property
    def npu_ms(self) -> float:
        return self.cycles / (self.hw.clk_mhz * 1e3)

    @property
    def frame_ms(self) -> float:
        # The CPU tail of frame N overlaps the NPU work of frame N+1 once
        # two descriptor lists are in flight, so the frame time is the
        # larger of the two.
        return max(self.npu_ms, self.cpu_ms)

    @property
    def fps(self) -> float:
        return 1000.0 / self.frame_ms

    @property
    def util(self) -> float:
        return self.macs / (self.cycles * self.hw.macs_per_cycle)

    @property
    def bytes_total(self) -> int:
        return sum(e.bytes_rd + e.bytes_wr for e in self.layers)


def estimate(layers: list[Layer], hw: HwConfig, cpu_ms: float = 4.0) -> NetEstimate:
    return NetEstimate(hw, [layer_cycles(l, hw) for l in layers], cpu_ms)
