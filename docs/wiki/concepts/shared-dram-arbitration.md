---
title: "Paylaşımlı DRAM Arbitrasyonu"
type: concept
created: 2026-07-03
updated: 2026-09-24
source_count: 6
tags: [dram, axi, arbitration, concept, m9]
---

# Paylaşımlı DRAM Arbitrasyonu

## Tanım
Birden fazla AXI master'ının tek bir fiziksel [[lpddr4x-controller]] belleğine, bir 3-e-1 AXI
anahtarı (`gAXIM_3to1_switch`) üzerinden yarışarak erişmesi.

## Detaylı Açıklama
Veri düzlemi anahtarının üç master'ı vardır (hepsi 128-bit): `MTSE`(0)=[[gdma]],
`MSDHC`(1)=[[gsdhc]], `MFCU`(2)=[[efx-sapphire-fcu]] `io_ddrA`. Tek slave, sertleştirilmiş
denetleyicinin `io_ddrMasters_0_*` AXI portudur. Böylece yazılım SoC'un CPU trafiği, DMA'nın
NIC trafiği ve SD'nin depolama trafiği aynı arbiter üzerinden serileştirilir. Denetleyici,
[[efx-sapphire-hpsoc-slb]]'ye bağlı `qcrv32_inst1` alt sistemine aittir. Bu, iki SoC'un tek
belleği paylaşmasının teknik yoludur ([[dual-soc-architecture]]).

### NPU yükü (2026-09, M8)
Anahtara iki yeni master yuvası eklendi (`MDNN`, rezerve `MCODEC`), ROUND_ROBIN_1 korundu.
[[stalyanpu]] paylaşımlı 128-bit porttan 2,4 GB/s planlama değeriyle modellendi; board'da
sayaç tabanlı 2,5 GB/s etkin ölçüldü. Tasarım DDR'a bağlıydı: giriş dolumu kare süresinin
%35'i. Board kilidi: bekleyen okuma yanıtı tüketilmeden port yazmayı kabul etmiyor; çözüm
rd_dma kanal başına 64 beat FIFO ve `rready` sabit 1. Yazma DMA 32 B işlemlerden
256 B..4 KB burst'lere geçti.

### NPU paylaşımlı anahtardan ayrıldı (2026-09-15, M9)
Döşeme çift tamponu dolum çevrimlerini 3,6 M'den 1,04 M'ye indirdiği hâlde DDR yarışması
`run_idle` ve `wr_wait`'e kaydı, epilog/yazma örtüşmesi (A2) ise board sayaçlarını hiç
değiştirmedi. Kare süresinden türetilen etkin bant genişliği 63,8 MB/kare ÷ 35,6 ms ≈
**1,8 GB/s** idi: sınır [[lpddr4x-controller]]'ın kendisi değil, sert SoC üzerinden geçen
`io_ddrMasters_0` köprü yolu ve anahtarın paylaşımıydı. Bunun üzerine NPU, denetleyicinin
dedicated 512-bit `axi_target0` portuna [[snpu-axi-up512]] genişleticisiyle bağlandı;
`MDNN` yuvası boşta kaldı (bağlantı `ti375_oob_top.v` HEAD'de). Paylaşımlı anahtar
artık yalnız FCU, gDMA ve SDHC trafiğini serileştirir; NPU trafiği bu arbitrasyonun
dışındadır. Sonuç 5,69 M çevrim, 43,9 fps, MAC %85.

### Güncel durum ve codec yükü (2026-09-24)
Paylaşımlı anahtar HEAD'de beş master taşır: gDMA, SD, FCU, npu1 (`MDNN`) ve eMMC (`MEMMC`,
codec için ayrılan eski yuva). Video codec [[stalyavpu]] altıncı master olarak eklenecek;
1080p30 IPB çözmede tahmini yükü 500 MB/s altında (çıkış yazma 94, MC okuma 190-380 MB/s).
Bu yol sert SoC önbellekleriyle tutarlı olduğu için Linux sürücüsü açısından da tercih edildi
([[stalyavpu-decision-record]]).

## Örnekler
- FCU DDR penceresi `0x0000_1000` tabanında; DMA `MTSE` portu üzerinden Ethernet çerçevelerini aynı belleğe yazar.
- Paylaşımlı yol sınırı: A2 örtüşmesi sim'de demo0 15,3 k → 13,5 k çevrim kazandırdı, board'da 8,89 M çevrim aynen kaldı.

## İlişkili Kavramlar
- [[axi-interconnect-topology]]: bu anahtarın içinde yer aldığı iki katmanlı topoloji ve NPU'nun dedicated porta taşınması
- [[dual-soc-architecture]]: paylaşımın motive ettiği mimari
- [[ethernet-datapath]]: DMA trafiğinin kaynağı
- [[analytic-performance-model]]: DDR sınırı modeli, 2,5 GB/s varsayımının dedicated portta düşük kalması
- [[board-bringup-flow]]: ölçüm akışı ve M9 tablosu
- Varlıklar: [[snpu-axi-up512]], [[lpddr4x-controller]], [[ti375-devkit]], [[gdma-dnn]]
- [[dnn-accelerator-options]]: veri yolu karşılaştırması

## Kaynaklar
- [[hardware-architecture]], [[system-overview]]
- [[stalyanpu-bringup-guide]]: DDR yolu düzeltmeleri, ölçümler, dedicated porta geçiş
- [[stalyanpu-perf-plan]]: paylaşımlı yolun ~1,8 GB/s etkin sınırı
- [[stalyanpu-decision-record]]: bant genişliği bütçesi
- [[dnn-integration-readme]]: MDNN/MCODEC yuvaları
