---
title: "Ethernet Veri Yolu"
type: concept
created: 2026-07-03
updated: 2026-07-03
source_count: 2
tags: [ethernet, dma, axi-stream, concept]
---

# Ethernet Veri Yolu

## Tanım
Ethernet çerçevelerinin, MAC AXI-Stream arayüzü ile paylaşımlı DRAM arasında [[gdma]] üzerinden
taşındığı TX/RX akışı.

## Detaylı Açıklama
**TX:** [[gdma]] `dat1_o` → `s_eth_tx_*` → `gTSE_streamControl` FIFO → `m_eth_tx_*` →
[[gtse-mac]] → RGMII → [[rtl8211f-phy]]. **RX:** [[rtl8211f-phy]] → RGMII → [[gtse-mac]]
`rx_axis_mac_*` → `s_eth_rx_*` → `m_eth_rx_*` → [[gdma]] `dat0_i`. `gTSE_streamControl`, iki
asenkron FIFO (`gTSE_core_fifo_data` ve `gTSE_core_fifo_ctrl`) ve doğru `tlast` üreten 3-durumlu
bir okuma FSM'i içerir. DMA, çerçeveleri [[shared-dram-arbitration]] üzerinden DDR'e yazar ve
FCU'ya `userInterruptG/H` kesmelerini üretir. Yazılım tarafında lwIP (`tsemac/lwipIperfServer`)
bu yolu bir NIC olarak kullanır.

## Örnekler
- Gigabit iperf TCP sunucusu: lwIP raw modda, `dmasg` DMA sürücüsü ve `rtl8211fd` PHY sürücüsü ile.

## İlişkili Kavramlar
- [[shared-dram-arbitration]]: DMA'nın DDR'e eriştiği mekanizma
- [[axi-interconnect-topology]]: CSR erişimi için kontrol düzlemi
- [[flight-management-unit]]: telemetri için bu yolun kullanımı

## Kaynaklar
- [[hardware-architecture]], [[software-architecture]]
