---
title: "gSDHC — SD-Host Denetleyicisi"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-24
source_count: 2
tags: [sd, storage, ip, axi]
---

# gSDHC — SD-Host Denetleyicisi

## Tanım
Efinix SD-host denetleyici IP çekirdeği; SD kart erişimi (depolama/kayıt) sağlar. Üst modülde
`u_gSDHC` olarak örneklenir.

## Temel Bilgiler
CSR'leri kontrol düzlemi anahtarı üzerinden (`SDHC` portu, index 1) AXI-Lite ile; veri yolu
`m_axi_*` master'ı veri düzlemi anahtarı üzerinden (`MSDHC` portu, index 1) DDR'e erişir.
Kesme `sd_int → userInterruptF`. SD pinleri `sd_clk/cmd/dat`, `sd_base_clk` saatiyle sürülür.
Yazılım tarafında `efx_mmc_driver` ve FatFs/FreeRTOS+FAT ile kullanılır.

> ⚠️ **Hata:** `ti375_oob_top.v:666` içinde bu çekirdeğin okuma kanalı handshake'i tanımsız
> `MHSDC` index'ine bağlıdır (`.m_axi_arready(m_axis_arready[MHSDC*1 +: 1])`). `MHSDC` çözülüp
> `0` (`MTSE` = [[gdma]]) olursa SDHC'nin `arready`'si DMA portuna çapraz bağlanır. Elaboration
> log ile doğrulanmalıdır — bkz. [[fmu-notes]].

## Kaynaklarda Geçişi
- [[hardware-architecture]]: SD-host alt sistemi
- [[fmu-notes]]: `MHSDC` yazım hatası

## İlişkiler
- [[gdma]]: yazım hatasının çapraz bağladığı port
- [[lpddr4x-controller]]: `MSDHC` üzerinden yazdığı DRAM
- [[efx-sapphire-fcu]]: CSR master'ı ve sürücü sahibi
- [[stalyavpu]]: eMMC örneğinin kullandığı `MEMMC` (yuva 4) codec için ayrılmıştı; codec 6:1 switch'in yuva 5'ine gider
