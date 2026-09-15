---
title: "Uçuş Yönetim Birimi (FMU)"
type: concept
created: 2026-07-03
updated: 2026-07-03
source_count: 3
tags: [fmu, concept, avionics]
---

# Uçuş Yönetim Birimi (FMU)

## Tanım
Bir hava aracının uçuş hesaplama görevlerini yürüten gömülü elektronik birim. Bu projede FMU,
tek bir [[ti375c529]] FPGA üzerinde uçuş uygulaması ile platform ev-işlerini ayıran çift-SoC bir
sistem olarak gerçeklenir.

## Detaylı Açıklama
FMU rolü, uçuş-kritik yazılımın ([[nuttx]] üzerinde) yoğunlaştığı yazılım işlemcisi
[[efx-sapphire-fcu]] ile ev-işleri/konfigürasyon cephesi [[efx-sapphire-hpsoc-slb]] arasındaki
[[dual-soc-architecture]] ile şekillenir. Ağ (telemetri) için Gigabit Ethernet
([[gtse-mac]] + [[rtl8211f-phy]]), veri hareketi için [[gdma]], kayıt/depolama için [[gsdhc]]
ve paylaşımlı [[lpddr4x-controller]] belleği kullanılır.

## Örnekler
- Telemetri: lwIP tabanlı ağ yığını (`tsemac/lwipIperfServer` referans uygulaması).
- Kayıt: FatFs/FreeRTOS+FAT ile SD karta yazma.
- Zaman/termal izleme: PCF8523 RTC ve EMC1413 sıcaklık sensörü sürücüleri.

## İlişkili Kavramlar
- [[dual-soc-architecture]]: FMU'nun donanım organizasyonu
- [[oob-to-fmu-transformation]]: OOB demosundan bu role geçiş
- [[boot-flow]]: uçuş yazılımının başlatılması

## Kaynaklar
- [[system-overview]], [[software-architecture]], [[fmu-notes]]
