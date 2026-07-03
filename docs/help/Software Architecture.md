---
title: "Software Architecture"
type: note
tags: [software, bsp, memory-map, nuttx, boot, drivers]
up: "[[Home]]"
created: 2026-07-03
updated: 2026-07-03
---

# Software Architecture

> [!info] Related
> Parent: [[Home]] · See also: [[Hardware Architecture]], [[Change Analysis]]

The firmware lives under `embedded_sw/` (git-ignored, present) as **two Sapphire-SoC BSP trees**:

| Tree | Target | Role |
|------|--------|------|
| `embedded_sw/EfxSapphireFCU` | Soft application SoC | Flight application processor (NuttX/Linux-capable, 4-core) |
| `embedded_sw/efx_hard_soc` | Hard processor block | Housekeeping / platform controller |

## 1. Processor / ISA

From `Bitstream/NuttX/x3/app/soc.h`: **RV32IMAFDC** (M, A, C, F, D + Zicsr/Zifencei),
**4 cores** (FCU `cpu0..3.yaml`), each with **FPU + MMU + Supervisor**, 8 KB 2-way I/D caches,
CLINT **200 MHz**, on-chip RAM_A 16 KB.

## 2. Memory maps

### 2a. `EfxSapphireFCU` — peripheral block at `0xF80x_xxxx`

| Region | Base | Size |
|--------|------|------|
| DDR (main memory) | `0x0000_1000` | `0xE000_0000` |
| AXI_A slave window | `0xE100_0000` | `0x1000_0000` |
| On-chip RAM_A | `0xF900_0000` | `0x4000` |
| Peripheral block | `0xF800_0000` | `0x0100_0000` |
| PLIC / CLINT | `0xF8C0_0000` / `0xF8B0_0000` | `0x40_0000` / `0x1_0000` |
| UART0/1/2 | `0xF801_0000` / `0xF801_B000` / `0xF801_C000` | `0x40` |
| SPI0/1/2 | `0xF801_4000` / `5000` / `6000` | `0x1000` |
| I2C0/1/2 | `0xF801_8000` / `9000` / `A000` | `0x100` |
| GPIO0 | `0xF801_7000` | `0x100` |
| Timer0/1/2 | `0xF801_D000` / `E000` / `F000` | `0x1000` |
| Watchdog | `0xF802_0000` | `0x100` |
| APB slave 0 | `0xF810_0000` | `0x1_0000` |

### 2b. `efx_hard_soc` — peripherals under `0xE80x_xxxx`

DDR `0x0000_1000` (size `0xE7FF_F000`), AXI_A `0xE800_0000`; UART0/1/2 `0xE801_0/1/2000`,
I2C0/1/2 `0xE802_0/1/2000`, SPI0/1/2 `0xE803_0/1/2000`, GPIO0 `0xE804_0000`;
PLIC/CLINT/RAM_A same as FCU.

## 3. PLIC interrupts (FCU)

UART0/1/2 = 1/2/3 · SPI0/1/2 = 4/5/6 · I2C0/1/2 = 8/9/10 · GPIO0 = 12/13 · Timer0/1/2 = 24/25/26
· Watchdog = 28 · User A = 16 · **User F(SD)=21, G(DMA0)=22, H(DMA1)=23** (see [[Hardware Architecture#5. DMA subsystem — `gDMA`]]).

## 4. Boot flow & NuttX image

- **Bootloader** runs from on-chip SRAM (`bootloader.ld`, `ORIGIN=0xF900_0000, LENGTH=16K`);
  inits SPI flash, copies app into DDR.
- **Application** runs from DDR (`default.ld`/`freertos.ld`, `ORIGIN=0x0000_1000, LENGTH=1020K`).
- **NuttX combined flash image** (`X3_FPGA_Nuttx_Combined.rpt`):

  | Flash addr | Length | Image |
  |------------|--------|-------|
  | `0x0000_0000` | `0x0042_701C` | `fpga/ti375_oob.hex` (bitstream) |
  | `0x0080_0000` | `0x0006_1F28` | `app/nuttx.bin` (NuttX) |

  Variants `Bitstream/NuttX/{hp,x2,x3}`; FCU IP `HexFile_Path` → `.../x3/boot/boot.hex`.

> [!tip] Why NuttX matters
> NuttX is the POSIX RTOS used by the **PX4** autopilot stack, aligning the flight application
> layer with established flight-controller software.

## 5. BSP contents (`bsp/efinix/EfxSapphireSoc/`)

- `include/` — `soc.h`, `bsp.h`, `soc.mk`, `print.h`, `semihosting.h`, `freertosHalConfig.h`.
- `linker/` — `bootloader.ld`, `default.ld`, `default_i.ld`, `freertos.ld`, `freertos_i.ld`.
- `app/` — middleware **`fatfs/`** (ChaN FatFs) + **`lwip/`** (lwIP stack).
- `openocd/` — debug/flash configs, GDB register XMLs (`efx_hard_soc` adds `lauterbach_trace32/`).

## 6. Driver library (`software/standalone/driver/`)

Core: `uart/spi/spiFlash/i2c/gpio/clint/plic/timer/watchdog/prescaler/riscv/vexriscv/io.h`.
Data plane: `dmasg.h` (SG DMA), `mmc.h`+`efx_mmc_driver.h` (SD/eMMC),
`efx_tse_mac.h`+`efx_tse_phy.h`+`rtl8211fd.h` (Ethernet MAC + PHY).
Fabric/bring-up: `apb3_cl.h`, `DDRCali_i2c.h`. Devices: `emc1413.h` (temp), `pcf8523.h` (RTC).

## 7. Application inventory

### 7a. `EfxSapphireFCU` — `software/standalone`

Benchmarks/bring-up: `coremark`, `dhrystone`, `memTest`, `bootloader`,
`customInstructionDemo` (TEA), `fpuDemo`, `smpDemo`/`smpIntrDemo`, cache-flush & semihosting.
Peripherals: `apb3Demo`, `axi4Demo`, `gpioDemo`, `i2c*` (MCP4725 DAC, AT24C01 EEPROM, master/slave),
`sdhc/{sdhcDemo,fatFSDemo}`, `spiDemo`, `timer/*`, `uart/*`.

> [!important] Key networking app
> `tsemac/lwipIperfServer` — a **Gigabit Ethernet iperf TCP server** (lwIP raw mode) using
> `efx_tse_mac`, the `rtl8211fd` PHY, and `dmasg` DMA. Reference for the Ethernet hardware in
> [[Hardware Architecture#4. Ethernet subsystem — `rtl/tseCore.v`]].

`software/freeRTOS`: `freertosDemo` only.

### 7b. `efx_hard_soc` — richer housekeeping set

Standalone adds `application/oob` (SMP LED + spinning ASCII **donut** over UART),
`i2c/rtcDemo` (PCF8523), `i2c/temperatureSensorDemo` (EMC1413).
FreeRTOS suite: `freertosDemo`, `freertosEchoServerDemo`, `freertosFatDemo`,
`freertosIperfDemo`, `freertosMqttPlainTextDemo` (all FreeRTOS+TCP / +FAT).

## 8. Build & flash tooling

- **Build:** per-app `makefile` + `src/`; include `common/{bsp.mk,riscv64-unknown-elf.mk,standalone.mk}`;
  pick `default.ld`/`freertos.ld`; `-DSMP` common; outputs under `build/`.
- **Flash (FCU only):** `tool/binGen.py` generates on-chip-RAM init `.bin`
  (`python3 binGen.py -b <app.bin> -f <fpu> -s <ram bytes>`); `tool/bootloader/bootloader_124K.bin`.

## 9. Flight vs housekeeping

| Layer | Runs on | Software |
|-------|---------|----------|
| Flight application | `EfxSapphireFCU` (soft, 4-core, DDR, FPU-D) | **NuttX**; lwIP Gigabit networking |
| Housekeeping | `efx_hard_soc` (hard block) | Bare-metal + FreeRTOS(+TCP/+FAT); RTC/temp; OOB demo |

Config changes (Linux enabled, `LDSize` grown, custom-instruction removed) → [[Change Analysis]].
Open items → [[FMU Notes]].
