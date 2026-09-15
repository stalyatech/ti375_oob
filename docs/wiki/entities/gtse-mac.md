---
title: "gTSE — Üç Hızlı Ethernet MAC"
type: entity
category: product
created: 2026-07-03
updated: 2026-07-03
source_count: 3
tags: [ethernet, mac, ip, rgmii, networking]
---

# gTSE — Üç Hızlı Ethernet MAC

## Tanım
Efinix **Triple-Speed Ethernet MAC** IP çekirdeği (`efx_tsemac`, sürüm 7.0). 10/100/1000 Mbps
Ethernet ortam erişim denetleyicisi. `rtl/tseCore.v` içinde sarılır.

## Temel Bilgiler
RGMII HI/LO DDR arayüzü, MDIO yönetimi, `eth_speed[2:0]` ve TX/RX MAC AXI-Stream sağlar; CSR'ler
AXI-Lite üzerindendir. `tseCore` içinde `gTSE_1to2_switch` (CSR'yi MAC/CMN olarak böler),
`gTSE` (MAC) ve `gTSE_streamControl` (TX FIFO + reset CSR'leri `0x080..0x083`) birlikte çalışır.
Harici PHY [[rtl8211f-phy]]'dir. Sürüm 7.0 ile yeni parametreler geldi: `INTER_PACKET_GAP=12`,
`MTU_FRAME_LENGTH=1518`, `MAC_SOURCE_ADDRESS` (placeholder), `ENABLE_BROADCAST_FILTERING`,
`LOOPBACK_EN`, `ONCHIP_PHY=0`. Çerçeveler [[gdma]] üzerinden DDR'e taşınır ([[ethernet-datapath]]).

## Kaynaklarda Geçişi
- [[hardware-architecture]]: Ethernet alt sistemi bölümü
- [[software-architecture]]: `efx_tse_mac` sürücüsü ve iperf uygulaması
- [[change-analysis]]: 6.4 → 7.0 parametre değişiklikleri

## İlişkiler
- [[rtl8211f-phy]]: bağlı fiziksel katman
- [[gdma]]: çerçeveleri DDR'e taşıyan DMA motoru
- [[efx-sapphire-fcu]]: CSR master'ı ve sürücü sahibi
- [[ethernet-datapath]]: TX/RX veri akışı kavramı
