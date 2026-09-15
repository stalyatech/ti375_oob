---
title: "NuttX RTOS"
type: entity
category: product
created: 2026-07-03
updated: 2026-07-03
source_count: 2
tags: [rtos, nuttx, px4, flight-software]
---

# NuttX RTOS

## Tanım
POSIX uyumlu, küçük ayak izli gerçek zamanlı işletim sistemi. PX4 otopilot yığınının kullandığı
RTOS ailesidir; bu nedenle uçuş uygulama katmanını yerleşik uçuş-denetleyici yazılımıyla
uyumlu hale getirir.

## Temel Bilgiler
[[efx-sapphire-fcu]] üzerinde uçuş uygulaması olarak çalışır ve SPI flash'tan başlatılır.
Birleşik flash imajı ([[boot-flow]]) `X3_FPGA_Nuttx_Combined.hex` şeklindedir: FPGA bit-akışı
`0x0` adresinde, `nuttx.bin` (~401 KB) `0x800000` adresinde. `Bitstream/NuttX/` altında `hp`,
`x2`, `x3` varyantları bulunur; her varyant `boot/boot.hex`, `app/nuttx.bin`, `app/soc.h` ve
`fpga/ti375_oob.{bit,hex}` içerir. FCU IP `HexFile_Path` `.../x3/boot/boot.hex`'i işaret eder.

## Kaynaklarda Geçişi
- [[software-architecture]]: NuttX imaj düzeni
- [[change-analysis]]: `HexFile_Path` ve `Linux=true` değişikliği

## İlişkiler
- [[efx-sapphire-fcu]]: üzerinde koştuğu SoC
- [[vexriscv]]: hedef çekirdek mimarisi
- [[boot-flow]]: önyükleme/imaj akışı
- [[flight-management-unit]]: hizmet ettiği uygulama alanı
