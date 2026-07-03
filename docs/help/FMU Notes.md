---
title: "FMU Current-State Notes"
type: note
tags: [fmu, issues, notes, safety]
up: "[[Home]]"
created: 2026-07-03
updated: 2026-07-03
---

# FMU Current-State Notes

> [!info] Related
> Parent: [[Home]] · See also: [[Hardware Architecture]], [[Change Analysis]]

Descriptive observations about the platform *as it stands today*. **Not** design proposals —
gaps and issues are simply flagged, with source pointers.

## 1. Compute domain responsibilities

| Domain | Hardware | Responsibility today |
|--------|----------|----------------------|
| Flight application | [[System Overview#Dual-SoC split|EfxSapphireFCU]] (soft, 4-core, FPU-D, DDR) | Runs **NuttX**; owns all board I/O and Ethernet/DMA/SD data plane |
| Housekeeping | `efx_hard_soc` / `EfxSapphireHpSoc_slb` (hard block) | Config, JTAG bridge, reset, owns DDR-controller AXI |

Flight-critical software concentrates on the soft SoC; the hard block is a housekeeping/bring-up
front-end (its peripheral fabric and `axiA` are open — [[Hardware Architecture#3. SoC instances]]).

## 2. Reset / watchdog behavior

- FCU watchdog (`0xF802_0000`) drives `system_watchdog_hardPanic → sp_watchdogReset`, OR'd into
  the FCU async reset — a **self-recovery** path on hard panic.
- The hard block generates `io_asyncReset`, which also resets the FCU (housekeeping can reset
  flight). No reciprocal path (the FCU cannot reset the hard block) — note for safety analysis.

## 3. Flagged issues (verify before relying on the current bitstream)

### 3a. `MHSDC` index typo — *correctness*
`ti375_oob_top.v:666`: `.m_axi_arready( m_axis_arready[MHSDC*1 +: 1] )`. `MHSDC` is undeclared
(localparams are `MTSE`/`MSDHC`/`MFCU`, `:250-252`). If resolved to `0` (`MTSE`) it cross-wires
SDHC's `arready` to the **DMA** master port, breaking SD reads and/or DMA. **Confirm against the
elaboration log; treat SD-read behavior as suspect until verified.**

### 3b. Staged glue RTL not wired in — *incomplete integration*
`rtl/apb3_slave.v`, `rtl/apb3_2_axi4_lite.v`, `rtl/axi_stream_ctrl.v`, `rtl/led_ctl.v` and
`ip/gAXIS_1to3_switch/` are present but **not instantiated**; their functions are today inside
`gTSE_streamControl`. Nothing depends on them yet — see [[Hardware Architecture#7. Staged glue RTL (present, NOT wired into top)]].

### 3c. Backup-file clutter — *housekeeping*
Nine untracked `ip/EfxSapphireHpSoc_slb/EfxSapphireHpSoc_wrapper_bak5..13.v`. Not referenced by
the build. Consolidate/remove once the wrapper is stable — **confirm the live wrapper first**.

## 4. Provisioning still open

- **MAC address:** `MAC_SOURCE_ADDRESS = 48'd0` (placeholder) — must be provisioned.
- **IP address:** lwIP reference server uses static `configIP_ADDR*` — static-IP by default.
- **Boot variant:** FCU boots `.../x3/boot/boot.hex`; `hp`/`x2` variants also exist — pin the
  canonical FMU variant.

## 5. Middleware already available

lwIP (FCU) + FreeRTOS+TCP (hard SoC) networking; FatFs + FreeRTOS+FAT for SD logging; PCF8523
**RTC** and EMC1413 **temperature** I2C drivers; `dmasg` **DMA** driver. These map onto FMU needs
(telemetry, logging, timekeeping, thermal) and are demonstrated by existing apps
([[Software Architecture#7. Application inventory]]).

## 6. Traceability

Sourced from `ti375_oob_top.v`, `ip/EfxSapphireFCU/source/{soc_config,settings.json}`,
`ip/gTSE/settings.json`, `Bitstream/NuttX/x3/app/soc.h`,
`Bitstream/NuttX/x3/X3_FPGA_Nuttx_Combined.rpt`, `rtl/*.v`, and the working-tree `git diff`.
