---
title: "Hardware Architecture"
type: note
tags: [hardware, rtl, ip, ethernet, dma, axi]
up: "[[Home]]"
created: 2026-07-03
updated: 2026-07-03
---

# Hardware Architecture

> [!info] Related
> Parent: [[Home]] · See also: [[System Overview]], [[Change Analysis]], [[FMU Notes]]

## 1. Instantiated modules (`ti375_oob_top.v`)

| Instance | Module | Role |
|----------|--------|------|
| `u_EfxSapphireFCU` | `EfxSapphireFCU` | Soft RISC-V application SoC (Linux/NuttX-capable) |
| `u_top_peripherals` | `EfxSapphireHpSoc_slb` | Hard processor-block wrapper (housekeeping/config/debug) |
| `u_AXIS_1to2_switch` | `gAXIS_1to2_switch` | Control-plane: FCU `axiA` → {TSE, SDHC} |
| `u_AXIM_3to1_switch` | `gAXIM_3to1_switch` | Data-plane: {DMA, SDHC, FCU} → LPDDR4x |
| `u_tseCore` | `tseCore` | Triple-Speed Ethernet subsystem (wraps `gTSE`) |
| `u_gDMA` | `gDMA` | Scatter-gather DMA (Ethernet stream ↔ DDR) |
| `u_gSDHC` | `gSDHC` | SD-host controller (CSR + AXI master to DDR) |

## 2. The two AXI interconnect layers

Fixed by localparams in `ti375_oob_top.v`:

```
localparam TSE = 0;  SDHC = 1;  AXIS_DEV = 2;     // control-plane ports (:246-248)
localparam MTSE = 0; MSDHC = 1; MFCU = 2; AXIM_DEV = 3; // data-plane ports (:250-253)
```

**Layer A — control plane (`gAXIS_1to2_switch`, `io_peripheralClk`):** FCU 32-bit `axiA`
master (`sp_m_axis_*`, addr windowed to `{7'b0, awaddr[24:0]}`) → port `TSE`(0)=`tseCore` CSR,
port `SDHC`(1)=`gSDHC` CSR. The FCU is the register master for both.

**Layer B — data plane (`gAXIM_3to1_switch`, `io_ddrMasters_0_clk`):** three 128-bit masters
`MTSE`(0)=gDMA, `MSDHC`(1)=gSDHC, `MFCU`(2)=FCU `io_ddrA` → single slave `io_ddrMasters_0_*`
(the LPDDR4x controller).

### Shared-DRAM mechanism

One physical LPDDR4x DRAM. The hardened subsystem `qcrv32_inst1` (bound in `ti375_oob.isf`)
owns the controller and exposes AXI as `io_ddrMasters_0_*` (128-bit data / 32-bit addr /
4-bit id) + `io_ddrMasters_memCheck_pass`. The FCU reaches DRAM as master `MFCU`, while gDMA
(`MTSE`) and gSDHC (`MSDHC`) contend through the same 3-to-1 arbiter. This is how both SoCs +
DMA + SD share one DRAM.

## 3. SoC instances

### `u_EfxSapphireFCU` (soft application SoC)

| Interface | Wiring |
|-----------|--------|
| Clocks | `io_systemClk = io_peripheralClk`; `io_memoryClk = io_ddrMasters_0_clk` |
| Reset | `io_asyncReset = sp_watchdogReset \| io_asyncReset(HpSoc)`; `system_watchdog_hardPanic → sp_watchdogReset` |
| Memory master | `io_ddrA_*` (128-bit) → `MFCU` → DDR |
| Peripheral master | `axiA_*` (32-bit) → `sp_m_axis_*` → 1-to-2 switch |
| DMA control | `io_apbSlave_0_*` (APB3) → `gDMA.ctrl_*` (14-bit addr) |
| Debug | `io_jtag_*` ← `sys_jtag_io_*` |
| Board IO | `system_spi/uart/i2c 0..2`, `system_gpio_0` → top pins |
| Interrupts | `userInterruptF = sd_int`; `userInterruptG/H = dma_interrupts[0/1]` |

### `u_top_peripherals = EfxSapphireHpSoc_slb` (hard processor block)

- Its `system_*`, `axiA_*`, `userInterrupt*` ports are left **open**.
- Drives: fabric JTAG tap `jtagCtrl_*` / `ut_jtagCtrl_*` (debug bridge into the FCU), config
  controller `cfg_done/start/sel/reset`, `io_asyncReset` (resets FCU), `io_gpio_sw_n`; consumes
  `pll_peripheral_locked` / `pll_system_locked`. Its DDR/`axiA` surface at top as
  `io_ddrMasters_0`/`axiA` (owned by `qcrv32_inst1`).

## 4. Ethernet subsystem — `rtl/tseCore.v`

`tseCore` (`ADDR_WIDTH=10`) instantiates:
- **`gTSE_1to2_switch`** — splits CSR AXI (`addr[15:0]`) into `MAC`(0) / `CMN`(1).
- **`gTSE`** — Efinix **Triple-Speed Ethernet MAC** v7.0: RGMII HI/LO DDR, MDIO, `eth_speed[2:0]`,
  TX/RX MAC AXI-Stream, AXI-Lite CSR at `MAC`.
- **`gTSE_streamControl`** — TX FIFO buffering + CSRs at `CMN`. Async FIFOs `gTSE_core_fifo_data`
  (`{tkeep,tdest,tdata}`) and `gTSE_core_fifo_ctrl` (word count); 3-state read FSM replays frames
  with correct `tlast`. CSRs (default read `0xEEEE_1111`):

  | Offset | Register | Offset | Register |
  |--------|----------|--------|----------|
  | `0x080` | `mac_sw_rst` | `0x082` | `dma_rx_rst` |
  | `0x081` | `phy_sw_rst` | `0x083` | `dma_tx_rst` |

- Reset helpers `reset`/`reset_ctrl`: `mac_ext_rst = ~pll_locked` → `proto_reset`/`mac_ext_srst`.

**Dataflow:** TX = gDMA `dat1_o` → `s_eth_tx_*` → streamControl FIFO → `m_eth_tx_*` → `gTSE` →
RGMII TX. RX = RGMII RX → `gTSE` → `s_eth_rx_*` → `m_eth_rx_*` → gDMA `dat0_i`. `phy_rst = phy_sw_rst`.
PHY = external **RTL8211F** (RGMII DDIO on `io_tseClk`/`io_tseClk_90`; MDIO on `io_tseClk`).

## 5. DMA subsystem — `gDMA`

| Interface | Wiring |
|-----------|--------|
| Control | APB3 `ctrl_*` from FCU (`sp_apbSlave_0_PADDR[13:0]`) on `io_peripheralClk` |
| Data | AXI `read_*`/`write_*` (128-bit) on `io_ddrMasters_0_clk` → `MTSE` → DDR |
| Stream TX | `dat1_o_*` (on `io_tseClk`) → `s_eth_tx_*` |
| Stream RX | `dat0_i_*` (on `rgmii_rxc`) ← `m_eth_rx_*` |
| SG / IRQ | `io_1/0_descriptorUpdate`; `dma_interrupts[1:0]` → `userInterruptG/H` |

gDMA is the **NIC ring-buffer engine** — moves Ethernet frames between the MAC AXI-Stream and DDR.

## 6. SD-host subsystem — `gSDHC`

CSR via control-plane switch (`SDHC` port 1); data `m_axi_*` via data-plane (`MSDHC` port 1);
`sd_int → userInterruptF`; SD pins `sd_clk/cmd/dat` on `sd_base_clk`.

> [!warning] Flagged issue — `MHSDC` typo
> `ti375_oob_top.v:666`: `.m_axi_arready( m_axis_arready[MHSDC*1 +: 1] )` uses undeclared
> `MHSDC` (should be `MSDHC`). If it elaborates, `MHSDC`→0 (`MTSE`) cross-wires SDHC's `arready`
> to the DMA master port. Verify against the synthesis log. See [[FMU Notes#3a. `MHSDC` index typo]].

## 7. Staged glue RTL (present, NOT wired into top)

These `rtl/` files are referenced nowhere in the top or project list — a refactor/bring-up
variant of functions already inside `gTSE_streamControl`, staged for later:

| File | Module | Function |
|------|--------|----------|
| `rtl/apb3_slave.v` | `apb3_slave` | APB3 reg-file: `clkmux_sel`, `tx_packet_count`, `mac_sw_rst`, `phy_sw_rst` |
| `rtl/apb3_2_axi4_lite.v` | `apb3_2_axi4_lite` | APB3→AXI4-Lite bridge, 5-state FSM, 8-bit timeout→`pslverror` |
| `rtl/axi_stream_ctrl.v` | `axi_stream_ctrl` | AXI-Stream TX; `tlast` when `r_packet_cnt == tx_packet_count` |
| `rtl/led_ctl.v` | `led_ctl` | Heartbeat: counter to `125e6-1` toggles `led_o` (~1 Hz @125 MHz) |

The untracked `ip/gAXIS_1to3_switch/` IP is likewise staged but unwired.

## 8. Configuration files

| File | Contents |
|------|----------|
| `ti375_oob.xml` | Project/top/IP list + flow; device `Ti375C529`, timing `C4` |
| `ti375_oob.peri.xml` | 3 PLLs, LPDDR4x `soc_ddr_inst1`, RGMII DDIO, MDIO, SD pins, config controller, clkmux |
| `ti375_oob.isf` | Pin/bank/voltage; CLKMUX; `qcrv32_inst1` "SOC" map binding `axiA_*`/`io_ddrMasters_0_*` |
| `constraints.sdc` | Timing constraints |

## 9. Flagged hardware issues

1. `MHSDC` typo on `gSDHC.m_axi_arready` (`ti375_oob_top.v:666`) — §6.
2. Nine untracked `EfxSapphireHpSoc_wrapper_bak5..13.v` backups in `ip/EfxSapphireHpSoc_slb/`.

See [[FMU Notes]] and [[Change Analysis]].
