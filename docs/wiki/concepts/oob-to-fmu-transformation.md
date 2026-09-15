---
title: "OOB → FMU Dönüşümü"
type: concept
created: 2026-07-03
updated: 2026-07-03
source_count: 2
tags: [change-log, fmu, transformation, concept]
---

# OOB → FMU Dönüşümü

## Tanım
Stok Efinix "kutudan çıktığı gibi" (out-of-box, OOB) demosunun kademeli olarak bir
[[flight-management-unit]] platformuna dönüştürülme süreci.

## Detaylı Açıklama
Dönüşüm dört ana harekette özetlenir:
1. **Hesaplamayı ayır** — uçuş işlemcisi [[efx-sapphire-fcu]] (artık Linux/[[nuttx]] sınıfı,
   `LDSize` 1020K, 128-bit DDR master, hızlandırıcı kaldırılmış) ve ev-işleri denetleyicisi
   [[efx-sapphire-hpsoc-slb]] ([[dual-soc-architecture]]).
2. **Veri düzlemini uçuş işlemcisine taşı** — Gigabit Ethernet ([[gtse-mac]] 7.0),
   dağınık-toplama [[gdma]], SD depolama ([[gsdhc]]) — hepsi paylaşımlı DRAM'e
   ([[shared-dram-arbitration]]) erişir.
3. **Güncel toolchain'e geç** — [[efinity-toolchain]] 2025.2, Sapphire 3.3.0.
4. **Sonraki adım tutkalını hazırla** — `gAXIS_1to3_switch`, APB/AXI-Lite köprüsü, TX
   denetleyicisi ve LED (henüz bağlanmamış).

Git geçmişi bu adımları üç commit'te kaydeder: ilk OOB → çift-SoC + paylaşımlı DRAM → veri
düzleminin taşınması + DMA. Açık kalemler [[fmu-notes]] sayfasındadır.

## Örnekler
- `608bd67` commit'i: donanım SoC'tan TSEMAC/SDHC/SLB switch kaldırma, yazılım SoC'a ekleme ve DMA getirme.
- Custom-instruction/CFU hızlandırıcısının ve pinlerinin kaldırılması.

## İlişkili Kavramlar
- [[dual-soc-architecture]], [[shared-dram-arbitration]], [[ethernet-datapath]]
- [[flight-management-unit]]: dönüşümün hedefi

## Kaynaklar
- [[change-analysis]], [[fmu-notes]]
