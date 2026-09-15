---
title: "Kaynak: Yazılım Mimarisi"
type: source
source_file: "docs/help/Software Architecture.md"
author: "Proje mimari dokümantasyonu"
date: 2026-07-03
created: 2026-07-03
updated: 2026-07-03
tags: [software, bsp, memory-map, nuttx, boot, drivers]
---

# Kaynak: Yazılım Mimarisi

## Özet
`embedded_sw/` altındaki iki Sapphire-SoC BSP ağacını ([[efx-sapphire-fcu]] ve
`efx_hard_soc`) belgeler: [[vexriscv]] ISA'sı, iki SoC için bellek haritaları, PLIC kesme
haritası, önyükleme akışı ([[boot-flow]]), [[nuttx]] imaj düzeni ve uygulama/sürücü envanteri.

## Temel Çıkarımlar
- ISA **RV32IMAFDC**, 4 çekirdek, FPU+MMU+Supervisor, 200 MHz, 8 KB I/D önbellek.
- FCU çevre birimleri `0xF80x`, hard-soc çevre birimleri `0xE80x` adres bloğunda.
- Önyükleyici çip-içi SRAM'de (`0xF900_0000`), uygulama DDR'de (`0x0000_1000`, 1020K) çalışır.
- Anahtar ağ uygulaması: `tsemac/lwipIperfServer` (Gigabit lwIP iperf sunucusu).

## Detaylı Notlar
[[efx-sapphire-fcu]] ağacı 4 çekirdekli uygulama-işlemci ağacıdır; `standalone` ve `freeRTOS`
uygulamaları, gömülü **lwIP** ve **FatFs** ara katmanları içerir. Sürücü kitaplığı UART/SPI/I2C/
GPIO/timer/watchdog yanında `dmasg` (DMA — [[gdma]]), `efx_mmc_driver` (SD — [[gsdhc]]),
`efx_tse_mac`+`rtl8211fd` (Ethernet — [[gtse-mac]], [[rtl8211f-phy]]) barındırır. `efx_hard_soc`
ağacı daha zengin bir uygulama kümesine sahiptir: SMP "donut" OOB demosu, PCF8523 RTC, EMC1413
sıcaklık sensörü ve tam bir FreeRTOS+TCP suite (echo/iperf/MQTT) + FreeRTOS+FAT.

[[nuttx]] birleşik flash imajı: FPGA bit-akışı `0x0` adresinde, `nuttx.bin` `0x800000`
adresinde. FCU IP `HexFile_Path` `Bitstream/NuttX/x3/boot/boot.hex`'i gösterir. FCU'ya özel
`tool/binGen.py` çip-içi RAM init `.bin` üretir.

## Bağlantılar
- İlgili varlıklar: [[efx-sapphire-fcu]], [[vexriscv]], [[nuttx]], [[gtse-mac]], [[gdma]], [[gsdhc]], [[rtl8211f-phy]]
- İlgili kavramlar: [[boot-flow]], [[dual-soc-architecture]], [[flight-management-unit]]
- İlgili kaynaklar: [[system-overview]], [[hardware-architecture]], [[change-analysis]]
