---
title: "Kaynak: Değişiklik Analizi (OOB → FMU)"
type: source
source_file: "docs/help/Change Analysis.md"
author: "Proje mimari dokümantasyonu"
date: 2026-07-03
created: 2026-07-03
updated: 2026-07-03
tags: [change-log, fmu, ip, soc, ethernet]
---

# Kaynak: Değişiklik Analizi (OOB → FMU)

## Özet
Stok Efinix Ti375 OOB demosunun FMU platformuna nasıl dönüştürüldüğünü hem commit geçmişi hem
de commit'lenmemiş çalışma-ağacı farkı üzerinden açıklar. Ana dönüşüm
[[oob-to-fmu-transformation]] kavram sayfasında sentezlenir.

## Temel Çıkarımlar
- 3 commit: ilk OOB → çift-SoC + paylaşımlı DRAM → veri düzleminin donanım SoC'tan yazılım SoC'a taşınması + DMA eklenmesi.
- Toolchain yükseltmeleri: Efinity 2025.1→2025.2, `efx_soc` 3.2.3→3.3.0, `efx_tsemac` 6.4→7.0, `efx_dma` 6.4.1→6.4.2.
- [[efx-sapphire-fcu]] artık `Linux=true`, `LDSize` 124→1020K, `AXIMasterWidth` 32→128; custom-instruction kaldırıldı.
- [[gtse-mac]] 7.0 yeni parametreler getirdi (MTU, IPG, broadcast filtreleme, loopback).

## Detaylı Notlar
Çalışma-ağacı farkı 58 dosya, ~21.8k ekleme/~19.4k silme; büyük kısmı Efinity sürüm
yükseltmesinden yeniden üretilen IP netlist'leri. Anlamlı değişiklikler SoC konfigürasyonları,
IP sürümleri ve üst modüldedir. `608bd67` commit'i donanım SoC'tan ([[efx-sapphire-hpsoc-slb]])
TSEMAC/SDHC/SLB switch'i kaldırıp yazılım SoC'a ([[efx-sapphire-fcu]]) TSEMAC/SDHC ekler ve
[[gdma]]'yı getirir. Custom-instruction/CFU hızlandırıcısı ve ilgili pinler kaldırılmıştır.

Bekleyen ama bağlanmamış eklemeler: `ip/gAXIS_1to3_switch/`, `rtl/` tutkal dosyaları ve dokuz
adet `*_wrapper_bak*.v` yedek dosyası. Bunlar [[fmu-notes]] sayfasında not edilir.

## Bağlantılar
- İlgili varlıklar: [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[gtse-mac]], [[gdma]], [[efinity-toolchain]], [[nuttx]]
- İlgili kavramlar: [[oob-to-fmu-transformation]], [[dual-soc-architecture]], [[flight-management-unit]]
- İlgili kaynaklar: [[hardware-architecture]], [[software-architecture]], [[fmu-notes]]
