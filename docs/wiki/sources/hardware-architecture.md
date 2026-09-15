---
title: "Kaynak: Donanım Mimarisi"
type: source
source_file: "docs/help/Hardware Architecture.md"
author: "Proje mimari dokümantasyonu"
date: 2026-07-03
created: 2026-07-03
updated: 2026-07-03
tags: [hardware, rtl, ip, ethernet, dma, axi]
---

# Kaynak: Donanım Mimarisi

## Özet
`ti375_oob_top.v` üst modülünün RTL entegrasyonunu ayrıntılandırır: iki SoC, iki AXI anahtar
katmanı, Ethernet ([[gtse-mac]]), DMA ([[gdma]]) ve SD-host ([[gsdhc]]) alt sistemleri,
paylaşımlı DRAM arbitrasyonu ve henüz bağlanmamış tutkal RTL dosyaları. `MHSDC` index yazım
hatası açıkça işaretlenir.

## Temel Çıkarımlar
- Kontrol düzlemi port index'leri `TSE=0, SDHC=1`; veri düzlemi `MTSE=0, MSDHC=1, MFCU=2`.
- [[gdma]] Ethernet çerçevelerini MAC AXI-Stream ile DDR arasında taşıyan NIC halka motorudur.
- [[gtse-mac]], `tseCore.v` içinde `gTSE_1to2_switch` + `gTSE` + `gTSE_streamControl` ile sarılır.
- Tutkal RTL (`apb3_slave`, `apb3_2_axi4_lite`, `axi_stream_ctrl`, `led_ctl`) mevcut ama bağlı değil.

## Detaylı Notlar
**Kontrol düzlemi** (`gAXIS_1to2_switch`, `io_peripheralClk`): [[efx-sapphire-fcu]]'nun 32-bit
`axiA` master'ı, [[gtse-mac]] ve [[gsdhc]] CSR uzaylarına erişir. **Veri düzlemi**
(`gAXIM_3to1_switch`, `io_ddrMasters_0_clk`): üç 128-bit master ([[gdma]], [[gsdhc]], FCU
`io_ddrA`) tek [[lpddr4x-controller]] slave'i için yarışır — [[shared-dram-arbitration]]
mekanizması budur.

Ethernet veri akışı ([[ethernet-datapath]]): TX'te gDMA → streamControl FIFO → MAC → RGMII;
RX'te RGMII → MAC → gDMA. PHY harici [[rtl8211f-phy]]'dir. `gTSE_streamControl` CSR'leri
`0x080..0x083` mac/phy/dma reset kontrollerini içerir.

> ⚠️ **Çelişki değil, hata:** `ti375_oob_top.v:666` içinde `.m_axi_arready(m_axis_arready[MHSDC*1 +: 1])`
> tanımsız `MHSDC` kullanır (`MSDHC` olmalı). Ayrıntı [[gsdhc]] ve [[fmu-notes]] sayfalarında.

## Bağlantılar
- İlgili varlıklar: [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[gtse-mac]], [[gdma]], [[gsdhc]], [[rtl8211f-phy]], [[lpddr4x-controller]]
- İlgili kavramlar: [[axi-interconnect-topology]], [[shared-dram-arbitration]], [[ethernet-datapath]], [[dual-soc-architecture]]
- İlgili kaynaklar: [[system-overview]], [[change-analysis]], [[fmu-notes]]
