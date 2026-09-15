---
title: "RTL8211F Ethernet PHY"
type: entity
category: product
created: 2026-07-03
updated: 2026-07-03
source_count: 2
tags: [ethernet, phy, rgmii, networking]
---

# RTL8211F Ethernet PHY

## Tanım
Realtek **RTL8211F** Gigabit Ethernet fiziksel katman (PHY) tümdevresi. MAC ile fiziksel ağ
arasındaki harici PHY'dir.

## Temel Bilgiler
[[gtse-mac]] ile RGMII üzerinden (DDIO çıkışları `io_tseClk`/`io_tseClk_90` ile) ve MDIO
yönetim arayüzü (`io_tseClk`) üzerinden konuşur. `ONCHIP_PHY=0` ayarı harici PHY kullanımını
belirtir. Yazılım sürücüsü `rtl8211fd.h`'dir ve `tsemac/lwipIperfServer` uygulamasında
kullanılır. PHY reset'i `phy_sw_rst` CSR'i (streamControl `0x081`) üzerinden yönetilir.

## Kaynaklarda Geçişi
- [[hardware-architecture]]: Ethernet fiziksel katman notları
- [[software-architecture]]: `rtl8211fd` sürücüsü

## İlişkiler
- [[gtse-mac]]: bağlı olduğu MAC
- [[ethernet-datapath]]: fiziksel uç noktası olduğu akış
