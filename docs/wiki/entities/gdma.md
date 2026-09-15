---
title: "gDMA — Dağınık-Toplama DMA"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-15
source_count: 5
tags: [dma, ip, ethernet, nic, axi]
---

# gDMA — Dağınık-Toplama DMA

## Tanım
Efinix **efx_dma** IP çekirdeği (sürüm 6.4.2). Ethernet AXI-Stream ile DDR arasında çerçeve
taşıyan dağınık-toplama (scatter-gather) DMA motoru — pratikte bir **NIC halka arabelleği
motoru**.

## Temel Bilgiler
Kontrol yolu [[efx-sapphire-fcu]]'dan gelen APB3 (`ctrl_*`, `PADDR[13:0]`); veri yolu 128-bit
AXI `read_*`/`write_*` master'ı (veri düzleminde `MTSE` portu → DDR). Akış tarafında iki kanal:
TX (`dat1_o` → `s_eth_tx_*`, `io_tseClk`) ve RX (`dat0_i` ← `m_eth_rx_*`, `rgmii_rxc`). Descriptor
güncellemeleri `io_1/0_descriptorUpdate`, kesmeler `dma_interrupts[1:0]` → FCU'da
`userInterruptG/H`. `608bd67` commit'iyle yazılım SoC'a eklenmiştir ([[oob-to-fmu-transformation]]).

### DNN tarafı (2026-08/09)
- Aynı efx_dma 6.4.2 IP'sinin DNN için 64-bit stream kanallı ikinci örneği [[gdma-dnn]] olarak üretildi ve [[openeye]] ile birlikte `ti375_oob_top.v`'den söküldü; `MDNN=3` yuvasına [[stalyanpu]] `snpu_top` geçti (M9'dan itibaren NPU dedicated `axi_target0` portunda, yuva boş).
- APB slave 0 penceresi `PADDR[14]` ile bölünür: alt yarı gDMA, üst yarı ayrılmış (eski NPU CSR yeri). `userInterruptG/H` yolu [[hard-soc-fabric-interrupt-path]]'in bir örneğidir.

## Kaynaklarda Geçişi
- [[hardware-architecture]]: DMA alt sistemi bölümü
- [[software-architecture]]: `dmasg` sürücüsü
- [[change-analysis]]: DMA'nın eklenmesi

- [[stalyanpu-synthesis-guide]]: M7 entegrasyonunda APB pencere paylaşımı
- [[dnn-integration-readme]]: gDMA_dnn örneğinin türetildiği desen

## İlişkiler
- [[gtse-mac]]: çerçeveleri sağladığı/aldığı MAC
- [[lpddr4x-controller]]: `MTSE` portu üzerinden yazdığı DRAM ([[shared-dram-arbitration]])
- [[efx-sapphire-fcu]]: APB3 kontrol master'ı
- [[ethernet-datapath]]: içinde yer aldığı veri akışı
- [[gdma-dnn]]: DNN akışları için türetilmiş ikinci örnek
- [[stalyanpu]]: MDNN yuvasını devralan hızlandırıcı
