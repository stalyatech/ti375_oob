---
title: "gDMA_dnn — DNN Stream DMA"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [dma, ip, dnn, openeye, axi, axis, historical]
---

# gDMA_dnn — DNN Stream DMA

## Tanım
[[openeye]]'ın 64-bit `dma_i`/`dma_o` AXI-Stream uçlarını DDR ile taşımak için üretilmiş ikinci
**efx_dma** (sürüm 6.4.2) örneği. Mevcut [[gdma]] ile aynı IP'dir; stream genişliği ve kanal
yönleri DNN için ayarlanmıştır. OpenEye ile birlikte tasarımdan çıkarılmıştır.

## Temel Bilgiler
[[efinity-toolchain]] GUI IP Manager'da `bridges_and_adaptors` kütüphanesinden, `ip/gDMA`
referans alınarak üretilmiştir ([[dnn-integration-gui-ip-steps]]). Ayarlar: `MemExtWidth=128`
(128-bit DDR AXI master, `gAXIM_5to1_switch` ile uyumlu), scatter-gather mod,
`CTRL_ASYNC_MODE=1` (APB kontrol saati DDR saatinden farklı), kanal AsyncMode=1.

Kanallar:
- **CH1 MEM→STREAM** (`dat1_o`, Width=64, SG, BurstSize ~1024): ağırlık ve aktivasyonu OpenEye
  `dma_i`'ye besler.
- **CH0 STREAM→MEM** (`dat0_i`, Width=64, SG): OpenEye `dma_o` sonucunu DDR'a yazar.

Her iki stream ucu `io_dnnClk` (100 MHz), veri tarafı `io_ddrMasters_0_clk`, kontrol tarafı
`io_peripheralClk` domainindedir; CDC IP'nin async kanallarında çözülür. DDR erişimi
`gAXIM_5to1_switch` `MDNN=3` yuvasından [[lpddr4x-controller]]'a gider
([[shared-dram-arbitration]], [[axi-interconnect-topology]]).

Kontrol yolu Hard SoC APB3 peripheral 0 penceresinin alt yarısıdır (`PADDR[14]=0`,
0x0000..0x3FFF, APB native); üst yarı OpenEye `cfg_reg`'e gider
([[accelerator-control-plane-apb]]). `ctrl_interrupts` bağlanmamıştır; tamamlanma takibi
descriptor polling ile veya OpenEye done kesmesi ([[hard-soc-fabric-interrupt-path]]) ile yapılır.

Simülasyonda kapsam dışıdır (vendor RTL); AXIS kontratı [[file-driven-directed-testbench]]
içindeki BFM ile temsil edilir.

### Durum
Git geçmişine göre (`f119069`, "drop the openeye and dnn dma files from the project source
list") [[stalyanpu]] `MDNN` yuvasını aldığında gDMA_dnn OpenEye ile birlikte `ti375_oob.xml` ve
`ti375_oob_top.v`'den çıkarılmıştır. StalyaNPU M8'e kadar kendi `snpu_rd_dma` ile doğrudan anahtara
bağlandı; M9'dan itibaren dedicated `axi_target0` portunu kullanır ve `MDNN` yuvası boştur.
`ip/gDMA_dnn/` dizini diskte durur.

## Kaynaklarda Geçişi
- [[dnn-integration-readme]]: veri düzlemi, saat alanları, APB alt penceresi ve IRQ durumu
- [[dnn-integration-gui-ip-steps]]: IP üretim parametreleri

## İlişkiler
- [[gdma]]: aynı efx_dma IP'sinin Ethernet için ayarlanmış kardeş örneği
- [[openeye]]: beslediği hızlandırıcı
- [[stalyanpu]]: yuvasını devralan blok
- [[lpddr4x-controller]]: `MDNN` yuvası üzerinden eriştiği DRAM
- [[efx-sapphire-hpsoc-slb]]: APB3 kontrol master'ının bulunduğu Hard SoC tarafı
