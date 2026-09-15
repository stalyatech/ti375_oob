---
title: "Önyükleme Akışı"
type: concept
created: 2026-07-03
updated: 2026-07-03
source_count: 1
tags: [boot, flash, nuttx, concept]
---

# Önyükleme Akışı

## Tanım
Yazılım SoC'un ([[efx-sapphire-fcu]]) güç açılışından uçuş uygulamasının ([[nuttx]])
çalışmasına kadar geçen önyükleme zinciri.

## Detaylı Açıklama
**Önyükleyici** çip-içi SRAM'de çalışır (`bootloader.ld`, `ORIGIN=0xF900_0000, LENGTH=16K`);
SPI flash'ı başlatır ve uygulamayı DDR'e kopyalar. **Uygulama** DDR penceresinden çalışır
(`default.ld`/`freertos.ld`, `ORIGIN=0x0000_1000, LENGTH=1020K`). FMU dönüşümüyle `LDSize`
124K'dan 1020K'ya büyütülmüştür ([[oob-to-fmu-transformation]]). Birleşik flash imajı
([[nuttx]]): FPGA bit-akışı `0x0`, `nuttx.bin` `0x800000` adresinde. FCU'ya özel `tool/binGen.py`
çip-içi RAM init `.bin` dosyasını üretir; varsayılan imaj yalnızca SPI-flash önyükleyicisini
içerir, farklı bir uygulamayı güç açılışında başlatmak için yeniden üretilir.

## Örnekler
- `Bitstream/NuttX/x3/X3_FPGA_Nuttx_Combined.hex`: bit-akışı + NuttX uygulaması birleşik flash imajı.

## İlişkili Kavramlar
- [[nuttx]]: başlatılan RTOS
- [[oob-to-fmu-transformation]]: `LDSize`/`HexFile_Path` değişikliklerinin bağlamı
- [[flight-management-unit]]: uçuş yazılımının çalışmaya başladığı nokta

## Kaynaklar
- [[software-architecture]]
