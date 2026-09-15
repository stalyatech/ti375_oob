---
title: "Kaynak: Sistem Genel Bakışı"
type: source
source_file: "docs/help/System Overview.md"
author: "Proje mimari dokümantasyonu"
date: 2026-07-03
created: 2026-07-03
updated: 2026-07-03
tags: [overview, soc, clocks, fmu]
---

# Kaynak: Sistem Genel Bakışı

## Özet
Tasarımın hedef cihazını, toolchain'ini ve iki-alanlı hesaplama konseptini tanımlar. Tek bir
Efinix Titanium [[ti375c529]] FPGA üzerinde iki RISC-V Sapphire SoC bulunur: uçuş uygulama
işlemcisi [[efx-sapphire-fcu]] ve ev-işleri/konfigürasyon bloğu [[efx-sapphire-hpsoc-slb]].
Her ikisi tek bir [[lpddr4x-controller]] belleği paylaşır. Üç PLL (200 MHz çevresel, sistem/DDR
ve 125 MHz Gigabit Ethernet) saat alanlarını besler.

## Temel Çıkarımlar
- Cihaz **Ti375C529**, Efinity **2025.2.288**, üst modül `ti375_oob_top`.
- Çift-SoC ayrımı: yazılım SoC uçuş uygulamasını, donanım blok ev-işlerini üstlenir ([[dual-soc-architecture]]).
- Kontrol düzlemi `gAXIS_1to2_switch`, veri düzlemi `gAXIM_3to1_switch` ([[axi-interconnect-topology]]).
- Paylaşımlı DRAM bir 3-e-1 arbiter üzerinden gerçekleşir ([[shared-dram-arbitration]]).

## Detaylı Notlar
Yazılım SoC ([[efx-sapphire-fcu]]) 200 MHz'de 4 çekirdekli, çift-hassasiyetli FPU'lu, MMU'lu ve
Linux/[[nuttx]] yeteneklidir; tüm kart çevre birimlerini (UART/SPI/I2C/GPIO) sürer. Donanım blok
([[efx-sapphire-hpsoc-slb]]) sertleştirilmiş DDR denetleyicisinin AXI portuna sahiptir ve
yazılım SoC'a JTAG hata-ayıklama köprüsü ile reset sağlar. Saatlemede
`` `define ETH_1000MBPS `` Gigabit RX saatini seçer; `tse_pll_ok` iki PLL kilidinin AND'idir.
Reset zinciri: donanım blok `io_asyncReset` üretir (FCU'yu resetler), FCU watchdog'u ise hard
panic'te kendini resetler.

## Bağlantılar
- İlgili varlıklar: [[ti375c529]], [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[lpddr4x-controller]], [[efinity-toolchain]]
- İlgili kavramlar: [[dual-soc-architecture]], [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[flight-management-unit]]
- İlgili kaynaklar: [[hardware-architecture]], [[software-architecture]]
