---
title: "Change Analysis — OOB → FMU"
type: note
tags: [change-log, fmu, ip, soc, ethernet]
up: "[[Home]]"
created: 2026-07-03
updated: 2026-07-03
---

# Change Analysis — OOB → FMU

> [!info] Related
> Parent: [[Home]] · See also: [[Hardware Architecture]], [[Software Architecture]], [[FMU Notes]]

How the stock Efinix Ti375 out-of-box demo is transformed into the FMU platform — committed
history and the uncommitted working-tree delta.

## 1. Commit history

| Commit | Message | Meaning |
|--------|---------|---------|
| `224ef85` | Initial commit | Stock Efinix `ti375_oob` OOB demo |
| `9938416` | *Sapphire HardSoC and SoftSoC ... shared DRAM* | Introduces the **dual-SoC** architecture sharing one DRAM |
| `608bd67` | *HP TSEMAC/SDHC/SLB switch removed; SP TSEMAC/SDHC added; DMA added to SP* | **Moves the data plane** from the hard SoC (HP) to the soft SoC (SP), adds **DMA** |

HP = Hard Processor (`EfxSapphireHpSoc_slb`); SP = Soft Processor (`EfxSapphireFCU`).

## 2. Working-tree delta

`git diff --stat`: **58 files, ~21.8k+ / ~19.4k−**. Bulk = regenerated IP netlists
(`EfxSapphireSoc.v` ×6 `source_*`, `gTSE.sv`) from an Efinity bump; meaningful changes are in
SoC configs, IP versions, and the top level. Untracked: `ip/gAXIS_1to3_switch/`,
`rtl/{apb3_2_axi4_lite,apb3_slave,axi_stream_ctrl,led_ctl}.v`, nine `*_wrapper_bak*.v`.

## 3. Toolchain / version bumps

| Item | Before | After |
|------|--------|-------|
| Efinity | 2025.1.110.5.9 | **2025.2.288** |
| `efx_soc` | 3.2.3 | **3.3.0** |
| `efx_tsemac` | 6.4 (VERSION 16) | **7.0 (VERSION 66)** |
| `efx_dma` | 6.4.1 | **6.4.2** |
| Base path | `D:\...` | `E:\...` |
| Last run flow | `bitstream` | `place` |

## 4. `EfxSapphireFCU` (soft SoC) — flight-processor changes

| Parameter | Before | After | Why |
|-----------|--------|-------|-----|
| `Linux` | — | **`true`** | MMU/Supervisor Linux-class config |
| `LDSize` | 124K | **1020K** | Larger app image (NuttX/Linux) |
| `AXIMasterWidth` | 32 | **128** | Wider CPU→DDR master |
| Custom instr / CFU | enabled | **removed** | TEA-style accelerator dropped; `IO_CFUCLK/RESET` unbound |
| `CO_DEBUG`, `WRITEBUFFER_...` | — | added | New knobs |
| `HexFile_Path` | — | `Bitstream/NuttX/x3/boot/boot.hex` | Boots **NuttX** |

Reflected across `soc_config`, `settings.json`, `ti375_oob.isf`, `ti375_oob.peri.xml`.

## 5. `efx_tsemac` 6.4 → 7.0

New MAC params (`ip/gTSE/settings.json`): `INTER_PACKET_GAP=6'd12`, `MTU_FRAME_LENGTH=16'd1518`,
`MAC_SOURCE_ADDRESS=48'd0` (placeholder), `ENABLE_BROADCAST_FILTERING=1`, `LOOPBACK_EN=1`,
`APBIF=0`, `ONCHIP_PHY=0` (external RTL8211F).

## 6. `EfxSapphireHpSoc_slb` (hard SoC)

`EfxSapphireHpSoc_slb.v`, `_wrapper.v`, `source/Axi4PeripheralTop.v`, `hard_ip_args.ini`,
`source/peri_config` all changed — consistent with *"HP TSEMAC/SDHC/SLB switch removed"*: the
hard domain's data-plane peripherals and SLB switch were stripped, leaving housekeeping,
config, and the DDR port. `peri_config` keeps 3× UART/SPI/I2C, GPIO, watchdog, 200 MHz.

## 7. Interconnect & top-level

`ti375_oob_top.v` (~972 lines changed): dual-SoC wiring + two AXI switches + TSE/DMA/SD hookups.
`gAXIS_1to2_switch` in use; new untracked `gAXIS_1to3_switch` staged. `gDMA.v` (~137 lines) gains
Ethernet stream + DDR master hookups. `rtl/tseCore.v` change is cosmetic (whitespace).

## 8. Staged-but-unwired additions

| Item | Status |
|------|--------|
| `ip/gAXIS_1to3_switch/` | Present, not referenced |
| `rtl/{apb3_slave,apb3_2_axi4_lite,axi_stream_ctrl,led_ctl}.v` | Present, not instantiated |
| `*_wrapper_bak5..13.v` | Untracked backup clutter |

## 9. Summary — what the change set *is*

1. **Split compute** into a flight processor (soft FCU, now Linux/NuttX, wide DDR, no accelerator)
   and a housekeeping controller (hard HpSoc).
2. **Consolidate the data plane on the flight processor** — Gigabit Ethernet (TSE 7.0),
   scatter-gather DMA, SD storage — reaching **shared DRAM** via AXI switches.
3. **Move onto the current toolchain** (Efinity 2025.2, Sapphire 3.3.0).
4. **Stage next-step glue** (`gAXIS_1to3_switch`, APB/AXI-Lite bridge, TX controller, LED).

Current-state caveats collected in [[FMU Notes]].
