---
title: "LPDDR4x DRAM Denetleyicisi"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-15
source_count: 5
tags: [dram, lpddr4x, memory, axi, axi-target0]
---

# LPDDR4x DRAM Denetleyicisi

## Tanım
[[ti375c529]] içindeki sertleştirilmiş **LPDDR4x** bellek denetleyicisi (`soc_ddr_inst1`):
32-bit veri yolu, 8 Gb yoğunluk, 1 fiziksel rank. Platformun tek fiziksel ana belleğidir.

## Temel Bilgiler
Denetleyici, sertleştirilmiş RISC-V alt sistemi `qcrv32_inst1`'e aittir ve AXI portu üst
seviyede `io_ddrMasters_0_*` (128-bit veri, 32-bit adres, 4-bit id) ile yüzeye çıkar; ayrıca
`io_ddrMasters_memCheck_pass` sinyali vardır. Bu tek slave, `gAXIM_3to1_switch` veri düzlemi
arbiter'ının hedefidir; [[efx-sapphire-fcu]] (`MFCU`), [[gdma]] (`MTSE`) ve [[gsdhc]] (`MSDHC`)
bu tek belleği paylaşır ([[shared-dram-arbitration]]). FCU bellek haritasında DDR penceresi
`0x0000_1000` tabanında, `0xE000_0000` boyutundadır.

### NPU veri yolu (2026-09, M8)
- LPDDR4x x32 @1600 MT/s = 6,4 GB/s pinlerde; fabric'e tek 128-bit @250 MHz port (4,0 GB/s, 5 master paylaşır). `axi_target0/1` portları (`ti375_oob.peri.xml`) M8'de kapalıydı; [[stalyanpu]] için dedicated port M9 adayı olarak planlandı.
- Board davranışı: bekleyen okuma yanıtı tüketilmeden yazma kabul edilmez (rd_dma `rready` kilidi); `awcache/arcache` 0 ile device modunda tek işlem kabul eder. Paylaşımlı porttan NPU için ölçülen etkin bant genişliği 2,5 GB/s (sayaç tabanlı); A2 örtüşmesi sayaçları hiç değiştirmeyince kare süresinden türetilen değer ~1,8 GB/s (63,8 MB/kare ÷ 35,6 ms) çıktı. Yani sert SoC üzerinden geçen `io_ddrMasters_0` köprü yolu, denetleyicinin kendisinden önce sınır oluyordu.

### Dedicated `axi_target0` portu (2026-09-15, M9)
- Arayüz tasarımcısı x32 LPDDR4x'te 256-bit AXI'yi reddeder ("AXI Data Width 256 is not supported"); port **512-bit** açıldı (`is_axi_enable="true"`, `is_axi_width_256="false"`), pin adları `npu_ddr_*`, `ACLK_0` doğrudan `io_ddrMasters_0_clk` saat ağı. `efx_run -f interface` şablonu ARADDR 33 bit, ID 6 bit, RDATA/WDATA 512 bit, WSTRB 64 bit üretir.
- NPU 256-bit kaldı; arada [[snpu-axi-up512]] genişleticisi var. Yan bant: `ARAPCMD`/`AWAPCMD` 0, `AWALLSTRB` 0 (aksi hâlde yazma 16 beat sınırı), `AWCOBUF` 0 + `AWCACHE` 1111, ID'ler 0, `ARSTN = ~npu_rst`. Belge: Titanium DDR DRAM Block User Guide v2.8 (ASIZE 6 için ALEN ≤ 63, 4 KB sınırı, adres DRAM bayt adresi).
- Port pinlerinin `set_input_delay`/`set_output_delay` kısıtları `outflow/ti375_oob.pt.sdc`'den `constraints.sdc`'ye elle taşınmalıdır; taşınmayınca build'ler yerleşime bağlı asılı kaldı ([[ddr-port-pin-constraints]]).
- Sonuç: 5,69 M çevrim/kare, 43,9 fps, MAC %85; giriş dolumu 3,6 M'den 0,30 M çevrime indi. Dedicated portta etkin bant genişliği 4 GB/s'nin üzerindedir.

## Kaynaklarda Geçişi
- [[hardware-architecture]]: paylaşımlı DRAM mekanizması
- [[system-overview]]: cihaz tablosu
- [[stalyanpu-decision-record]]: port ve bant genişliği bütçesi
- [[stalyanpu-bringup-guide]]: board'da görülen DDR davranışları, `axi_target0` açılışı, yan bant, pin kısıtları
- [[stalyanpu-perf-plan]]: paylaşımlı yolun ~1,8 GB/s sınırı ve dedicated port sonucu

## İlişkiler
- [[efx-sapphire-fcu]], [[gdma]], [[gsdhc]]: paylaşımlı portu kullanan master'lar
- [[efx-sapphire-hpsoc-slb]]: paylaşımlı AXI portuna sahip olan alt sistem
- [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[dual-soc-architecture]]: erişim kavramları ve iki SoC'un paylaşımı
- [[stalyanpu]]: en büyük bant genişliği tüketicisi, M9'dan itibaren dedicated `axi_target0` portunda
- [[snpu-axi-up512]]: NPU'yu 512-bit porta bağlayan genişletici
- [[ddr-port-pin-constraints]]: port pinlerinin zamanlama kısıtları
- [[efinity-toolchain]]: portu açan arayüz tasarımcısı
- [[board-bringup-flow]]: DDR yolu düzeltmeleri ve ölçümler
- [[ti375-devkit]]: ölçümlerin alındığı kart
- [[analytic-performance-model]]: DDR bant genişliği varsayımı ve dedicated port sonrası düzeltmesi
- [[dnn-accelerator-options]]: veri yolu karşılaştırması
- [[gdma-dnn]]: eskiden `MDNN` yuvasından erişen DMA
