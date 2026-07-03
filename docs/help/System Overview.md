---
title: "System Overview"
type: note
tags: [hardware, soc, clocks, fmu, overview]
up: "[[Home]]"
created: 2026-07-03
updated: 2026-07-03
---

# System Overview

> [!info] Related
> Parent: [[Home]] · Next: [[Hardware Architecture]], [[Software Architecture]]

## Target device & toolchain

| Item | Value | Source |
|------|-------|--------|
| FPGA family | Efinix **Titanium** | `ti375_oob.xml` |
| Device | **Ti375C529** (529-ball FBGA) | `ti375_oob.xml`, `ti375_oob.isf` |
| Timing model | C4 | `ti375_oob.isf` |
| Efinity version | **2025.2.288** (from 2025.1) | `ti375_oob.xml` |
| Top module | `ti375_oob_top` | `ti375_oob_top.v` |
| External DRAM | Hard **LPDDR4x** (`soc_ddr_inst1`): 32-bit, 8 Gb, 1 rank | `ti375_oob.peri.xml` |

## The FMU concept

Two independent RISC-V compute domains on one FPGA separate **flight application software**
from **platform housekeeping** while sharing one DRAM:

- **Application / Flight domain** → the *soft* Sapphire SoC **`EfxSapphireFCU`** (Flight
  Control Unit). Quad-core, double-precision FPU, MMU, Linux/NuttX-capable. Owns all board I/O
  and the Ethernet/SD/DMA data plane.
- **Housekeeping / Platform domain** → the *hard* processor block **`EfxSapphireHpSoc_slb`**:
  configuration control, the JTAG debug bridge into the soft SoC, reset generation, and the
  hardened DDR controller AXI port.

## Dual-SoC split

| Aspect | `EfxSapphireFCU` (soft) | `EfxSapphireHpSoc_slb` (hard) |
|--------|-------------------------|-------------------------------|
| Role | Flight application processor | Housekeeping / config / debug bridge |
| Cores | 4× VexRiscv RV32IMAFDC, 200 MHz | Hardened RISC-V (`qcrv32_inst1`) |
| FPU / MMU | Double-precision FPU + MMU + Supervisor | RV32IMAFDC |
| DRAM access | Master `MFCU` (`io_ddrA`, 128-bit) via 3-to-1 switch | Owns DDR controller AXI (`io_ddrMasters_0`) |
| Board peripherals | Drives 3× UART/SPI/I2C, GPIO | Peripheral fabric unused here |
| Debug | `io_jtag_*` ← `sys_jtag_io_*` | Drives fabric tap `jtagCtrl_*` / `ut_jtagCtrl_*` |
| OS/runtime | **NuttX** (Linux-capable) | Bare-metal housekeeping |

Details in [[Hardware Architecture]] and [[Software Architecture]].

## Top-level block diagram

```
                          Ti375C529  (ti375_oob_top.v)
   ┌───────────────────────────────────────────────────────────────────────────┐
   │   ┌────────────────────┐            ┌──────────────────────────────┐      │
   │   │ EfxSapphireHpSoc   │  config /  │  EfxSapphireFCU  (soft SoC)   │      │
   │   │ _slb  (hard block) │  jtag /    │  4x RV32IMAFDC @200MHz, FPU-D │      │
   │   │  housekeeping      │  reset     │  NuttX / Linux-capable        │      │
   │   │  owns DDR ctrl AXI │◄──────────►│  axiA(32b)  io_ddrA(128b)     │      │
   │   └─────────┬──────────┘            │  apbSlave_0 → gDMA control    │      │
   │             │ io_ddrMasters_0       └──┬──────────┬─────────┬───────┘      │
   │             │ (to LPDDR4x)             │axiA      │io_ddrA  │apb           │
   │             │                    ┌─────▼─────┐    │     ┌───▼────┐         │
   │             │                    │ gAXIS_    │    │     │ gDMA   │         │
   │             │                    │ 1to2_sw   │    │     │ (SG)   │         │
   │             │                    └──┬─────┬──┘    │     └─┬───▲──┘         │
   │             │              TSE=0 CSR│     │SDHC=1 │ 128b  │   │ stream     │
   │             │                  ┌────▼──┐ ┌▼─────┐ │       │   │            │
   │             │                  │tseCore│ │gSDHC │ │       │   │            │
   │             │                  └──┬────┘ └──┬───┘ │       │   │            │
   │             │           RGMII+MDIO│  SD pins │     │       │   │            │
   │             │                     ▼          ▼     │       │   │            │
   │             │              RTL8211F PHY    SD card │       │   │            │
   │             │        ┌────────────────────────────▼───────▼───▼──┐         │
   │             └───────►│        gAXIM_3to1_switch  (data plane)     │         │
   │                      │  MTSE=0(DMA)·MSDHC=1(SD)·MFCU=2(CPU)       │         │
   │                      └──────────────────────┬─────────────────────┘         │
   │                                             ▼  Hard LPDDR4x controller       │
   └───────────────────────────────────────────────────────────────────────────┘
```

- **Control plane** — `gAXIS_1to2_switch`: FCU `axiA` (32-bit) → {TSE CSR, SDHC CSR}.
- **Data plane** — `gAXIM_3to1_switch`: {gDMA, gSDHC, FCU} (128-bit) → single LPDDR4x slave.
  This arbiter is the **shared-DRAM** mechanism ([[Hardware Architecture#2. The two AXI interconnect layers]]).

## Clocks, resets, PLLs

| PLL | Ref | Purpose | Output(s) | Lock |
|-----|-----|---------|-----------|------|
| `soc_pll_peri_clk` (`PLL_TR0`) | 25 MHz | Peripheral/system | `io_ddrMasters_0_clk`; `io_peripheralClk` = **200 MHz** | `pll_peripheral_locked` |
| `soc_pll_sys_clk` (`PLL_BL0`) | 100 MHz | System / DDR | `ddrClk` | `pll_system_locked` |
| `tse_pll_clk` (`PLL_BL2`) | 125 MHz (`rgmii_rxc_phy`) | Gigabit Ethernet | `io_tseClk` (+90°) | `pll_tse_locked` |

- `` `define ETH_1000MBPS 1 `` selects the Gigabit RX clock; `tse_pll_ok = pll_tse_locked & pll_peripheral_locked`.
- The hard block generates `io_asyncReset` (resets the FCU); the FCU watchdog
  `system_watchdog_hardPanic → sp_watchdogReset` self-recovers the flight domain — see [[FMU Notes#2. Reset / watchdog behavior]].
