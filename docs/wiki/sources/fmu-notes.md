---
title: "Kaynak: FMU Mevcut Durum Notları"
type: source
source_file: "docs/help/FMU Notes.md"
author: "Proje mimari dokümantasyonu"
date: 2026-07-03
created: 2026-07-03
updated: 2026-07-03
tags: [fmu, issues, notes, safety]
---

# Kaynak: FMU Mevcut Durum Notları

## Özet
Platformun bugünkü haline dair betimleyici gözlemler: hesaplama alanı sorumlulukları, reset/
watchdog davranışı, işaretlenen hatalar ve henüz sağlanmamış konfigürasyon kalemleri. Tasarım
önerisi değil, açık kalemlerin kaydıdır.

## Temel Çıkarımlar
- Uçuş-kritik yazılım [[efx-sapphire-fcu]] üzerinde; [[efx-sapphire-hpsoc-slb]] ev-işleri cephesidir.
- Watchdog hard panic'te FCU'yu kendiliğinden resetler; donanım blok da FCU'yu resetleyebilir (tersi yok).
- `MHSDC` index yazım hatası doğrulanmalıdır ([[gsdhc]]).
- MAC adresi ve statik IP henüz sağlanmamıştır.

## Detaylı Notlar
İşaretlenen üç konu: (3a) `ti375_oob_top.v:666`'daki `MHSDC` yazım hatası — çözülürse SD okuma
handshake'i [[gdma]] portuna çapraz bağlanır; (3b) `rtl/` tutkal RTL ve `gAXIS_1to3_switch` henüz
üst modüle bağlanmamıştır; (3c) dokuz adet `*_wrapper_bak*.v` yedek dosyası birikmiştir.

Hazır ara katmanlar FMU ihtiyaçlarıyla örtüşür: lwIP/FreeRTOS+TCP (telemetri), FatFs/FreeRTOS+FAT
(kayıt), PCF8523 RTC (zaman), EMC1413 (termal), `dmasg` DMA. Güvenlik analizi için reset
topolojisi (tek yönlü) not edilmelidir.

> ❓ **Belirsiz:** FMU için kanonik NuttX boot varyantı (`hp` / `x2` / `x3`) henüz sabitlenmemiştir.

## Bağlantılar
- İlgili varlıklar: [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[gsdhc]], [[gdma]], [[gtse-mac]], [[nuttx]]
- İlgili kavramlar: [[flight-management-unit]], [[dual-soc-architecture]], [[oob-to-fmu-transformation]]
- İlgili kaynaklar: [[hardware-architecture]], [[change-analysis]]
