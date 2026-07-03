---
title: "FMU Platform — Help Vault"
type: moc
tags: [moc, fmu, ti375, overview]
created: 2026-07-03
updated: 2026-07-03
---

# 🛩️ FMU Platform — Help Vault

Obsidian-formatted architecture help for the `ti375_oob` design as it is re-purposed from
Efinix's Titanium **Ti375C529 out-of-box (OOB)** demo into a **Flight Management Unit (FMU)**.

> [!info] One-paragraph summary
> A single **Ti375C529** FPGA hosts **two RISC-V Sapphire SoCs** sharing one hardened
> **LPDDR4x** DRAM. The soft SoC ([[System Overview#Dual-SoC split|EfxSapphireFCU]]) is a
> quad-core, FPU-D, NuttX-capable **application/flight processor** driving all board I/O and
> the Ethernet/DMA/SD data plane. The hard block (`EfxSapphireHpSoc_slb`) is the
> **housekeeping / config / JTAG-debug** front-end that owns the DDR controller. Flight
> software boots **NuttX** from SPI flash.

## Map of content

- [[System Overview]] — device, toolchain, dual-SoC concept, block diagram, clocks/PLLs
- [[Hardware Architecture]] — RTL integration, AXI interconnect, shared-DRAM, TSE/DMA/SD, glue RTL
- [[Software Architecture]] — Sapphire BSPs, memory maps, interrupts, boot flow, NuttX, apps
- [[Change Analysis]] — the OOB → FMU transformation (commits + working-tree changes)
- [[FMU Notes]] — current-state observations, gaps, and flagged issues

## Reading order

1. Start with [[System Overview]] for the big picture.
2. Drill into [[Hardware Architecture]] and [[Software Architecture]].
3. Read [[Change Analysis]] to understand *what changed and why*.
4. Check [[FMU Notes]] for open items before relying on the current bitstream.

## Tags

`#hardware` `#software` `#ip` `#ethernet` `#dma` `#soc` `#nuttx` `#change-log` `#fmu`

> [!note] Scope
> This vault mirrors the plain-Markdown docs in `docs/` in Obsidian form (frontmatter +
> `[[wiki-links]]`). It is descriptive of the **current state**; open items are flagged in
> [[FMU Notes]], not solved. `embedded_sw/` and `Bitstream/` are git-ignored but part of the
> platform and are documented here.
