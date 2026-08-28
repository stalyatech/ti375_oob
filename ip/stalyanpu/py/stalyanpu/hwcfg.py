"""Hardware configuration of the StalyaNPU array.

The same object feeds the performance model, the tiler and the golden vector
generators, so every tool sees one geometry. Values mirror the RTL parameters
in ip/stalyanpu/rtl/snpu_pkg.vh.
"""

from __future__ import annotations

import dataclasses
import json
from dataclasses import dataclass


@dataclass
class HwConfig:
    name: str = "full2048"
    # Array geometry. A chain is chain_len cascaded DSP48 blocks in DUAL
    # mode and covers chain_len input channels for two output channels.
    n_chain: int = 32
    chain_len: int = 32
    # Pixels per accumulator bank (output stationary tile size).
    p_max: int = 1024
    # On chip buffers in bytes.
    ibuf_bytes: int = 512 * 1024
    wfifo_bytes: int = 32 * 1024
    # Clock and memory interface.
    clk_mhz: float = 250.0
    axi_dw: int = 128
    # Effective DDR bandwidth available to the accelerator, bytes per
    # second. 2.4 GB/s is the planning value for the shared 128-bit port
    # and is replaced by the measured figure after bring-up.
    ddr_bw_gbps: float = 2.4
    # Fixed overheads in cycles.
    t_pass: int = 40      # weight switch and pipeline skew per pass
    t_tile: int = 150     # tile setup
    t_op: int = 500       # descriptor fetch, parameters, activation table
    # Epilogue throughput in output channels per cycle.
    epilogue_oc_per_cycle: int = 32
    # Channel granularity of the tensor layout (NC32HW).
    ch_group: int = 32
    # Padded input channel count of the stem layer in baseline mode.
    stem_ic_pad: int = 8

    @property
    def n_oc(self) -> int:
        return 2 * self.n_chain

    @property
    def n_ic(self) -> int:
        return self.chain_len

    @property
    def macs_per_cycle(self) -> int:
        return self.n_oc * self.n_ic

    @property
    def dsp_count(self) -> int:
        return self.n_chain * self.chain_len

    @property
    def bytes_per_cycle(self) -> float:
        return self.ddr_bw_gbps * 1e9 / (self.clk_mhz * 1e6)

    @property
    def peak_gmacs(self) -> float:
        return self.macs_per_cycle * self.clk_mhz / 1e3

    def to_json(self, path: str) -> None:
        with open(path, "w") as fh:
            json.dump(dataclasses.asdict(self), fh, indent=2)

    @classmethod
    def from_json(cls, path: str) -> "HwConfig":
        with open(path) as fh:
            return cls(**json.load(fh))


PRESETS = {
    "full2048": HwConfig(),
    "small256": HwConfig(
        name="small256",
        n_chain=8,
        chain_len=16,
        p_max=256,
        ibuf_bytes=64 * 1024,
        wfifo_bytes=8 * 1024,
    ),
}


def load(name_or_path: str) -> HwConfig:
    """Return a preset by name or a configuration loaded from a JSON file."""
    if name_or_path in PRESETS:
        return PRESETS[name_or_path]
    return HwConfig.from_json(name_or_path)
