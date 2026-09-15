---
title: "DNN Hızlandırıcı Seçenekleri: OpenEye, Ölçeklenmiş OpenEye ve StalyaNPU"
type: comparison
created: 2026-09-15
updated: 2026-09-15
tags: [openeye, stalyanpu, dnn, accelerator, decision, performance, m9]
---

# DNN Hızlandırıcı Seçenekleri: OpenEye, Ölçeklenmiş OpenEye ve StalyaNPU

## Özet
2026-08-28 karar kaydı, [[yolov8s]] 640×384 @30 fps INT8 hedefine (8,58 GMAC/kare,
258 GMAC/s) ulaşmak için üç seçeneği karşılaştırdı: mevcut [[openeye]] 2×2 küme yapısı,
OpenEye'ın RTL sınırları içinde ölçeklenmiş hali ve sıfırdan yazılacak [[stalyanpu]] tam
dizi. Hedef OpenEye'ın mimari tavanının >45 katı olduğundan (bugünkü yapıya göre >380×)
karar StalyaNPU lehine verildi.

## Karşılaştırma Tablosu

| Boyut                                | OpenEye (bugün)                                                                                             | OpenEye üst sınır                                                           | StalyaNPU tam dizi                                                                                                       |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Geometri                             | 2×2 küme × 3×4 PE = 48 PE, `PARALLEL_MACS=2`                                                                | 8×2 küme = 192 PE (`CLUSTER_COLUMNS=2` sabit, `PARALLEL_MACS` 4 RTL'de yok) | 32 zincir × 32 [[efx-dsp48]] DUAL = 1024 DSP                                                                             |
| MAC/çevrim                           | 96                                                                                                          | 384                                                                         | 2048                                                                                                                     |
| Saat                                 | 100 MHz (Fmax 114,6)                                                                                        | ~115 MHz                                                                    | 250 MHz                                                                                                                  |
| Tepe                                 | 9,6 GMAC/s                                                                                                  | ~40 GMAC/s                                                                  | 512 GMAC/s (≈1,02 TOPS INT8)                                                                                             |
| Hedefe göre fps (tepe, sıfır ek yük) | 0,67                                                                                                        | ~2,8                                                                        | 59,7 tepe; model 32,9 @2,4 GB/s; board 24,6 (M8), **43,9 (M9, dedicated 512-bit DDR portu)**                            |
| Kaynak                               | 114 853 XLR, 1802/2688 RAM10, 152 DSP                                                                       | 4× küme RAM10'a sığmaz (psum tamponları tek başına 1024 blok)               | tahmin 77k XLR, 933 RAM10, 1120 DSP; gerçek (M7) 1217 DSP, 1478 RAM10; (M9) 1223 DSP, 1606 RAM10                        |
| Veri yolu                            | Tek 64-bit AXIS @100 MHz = 0,8 GB/s; katman başına tam yeniden yükleme; referans katmanda DMA'ya 3,7× bağlı | aynı                                                                        | Kendi AXI4 DMA'ları; M8'e kadar 128-bit paylaşımlı yuva (etkin ~1,8 GB/s), M9'dan itibaren dedicated 512-bit `axi_target0` portu ([[snpu-axi-up512]]) |
| Mimari                               | Row-stationary, NoC                                                                                         | aynı                                                                        | Ağırlık-sabit sistolik DSP kaskadı ([[dsp-chain-systolic-array]])                                                        |
| Op desteği                           | Conv, Dense, ReLU/LeakyReLU, 2×2 pool; `same` simetrik padding; ≤32 filtre/aktarım                          | aynı                                                                        | Conv 1×1/3×3 s1/s2, SiLU LUT, residual Add, Concat/Split/Upsample ×2 sıfır kopya, SPPF MaxPool 5 s1 ([[descriptor-isa]]) |
| Bilinen hatalar                      | 10×10×8 ve üstü girişte çıktı beat'lerinin yarısı; upstream `d19314a`, `ff4f99f` regresyonları              | aynı                                                                        | yeni tasarım, M0..M7 kapılarıyla doğrulandı                                                                              |
| Durum                                | `ti375_oob_top.v`'den M7'de söküldü                                                                         | değerlendirilmedi                                                           | M9 tamam: board'da 43,9 fps, bit bit doğru, zamanlama +0,038 ns                                                          |

## Detaylı Analiz
**İşlem gücü.** Gerek 258 GMAC/s sürekli. OpenEye bugün 9,6 GMAC/s (0,67 fps); en iyimser
ölçekleme bile ~40 GMAC/s (~2,8 fps). StalyaNPU 512 GMAC/s tepe ile hedef için %50 kullanım
gerektirir; [[analytic-performance-model]] 2,4 GB/s paylaşımlı portta 32,9 fps (%55) verir.

**Kaynak.** OpenEye 48 PE için 1802 RAM10 kullanır (%67); 4× küme sığmaz. StalyaNPU'nun
RAM10 kullanımı 1478 (%55) ile daha düşük, DSP kullanımı 1217/1344 (%90) ile çok yüksektir.
Cihaz tavanı [[ti375c529]]: 362 880 XLR, 2688 RAM10, 1344 DSP48; OpenEye ve `gDMA_dnn`
çıkınca ~289k XLR, ~2359 RAM10, ~1319 DSP boşalır.

**Veri yolu.** OpenEye tek 64-bit AXIS ile DMA'ya bağlıdır ve her katmanda tam yeniden
yükleme yapar. StalyaNPU on-chip 512 KB ibuf halkası ve 512 KB biriktiriciyle döşeme başına
okur, ağırlıkları tüketim sırasında akıtır. M8'de paylaşımlı 128-bit yuvada tasarım DDR'a
bağlıydı (giriş dolumu %35, etkin ~1,8 GB/s); M9'da dedicated 512-bit `axi_target0`
portuna geçince MAC payı %85'e çıktı ve tasarım hesaba bağlı hâle geldi
([[shared-dram-arbitration]], [[lpddr4x-controller]]).

**Op kümesi.** YOLOv8s'in SiLU, Add, Concat, Split, Upsample ve SPPF MaxPool ihtiyaçları
OpenEye'da yoktur; StalyaNPU bunları epilog, NC32HW düzeni ve `snpu_maxpool5` ile karşılar.

**Risk.** OpenEye'ın bilinen çıktı hataları ve upstream regresyonları vardı; StalyaNPU'nun
riskleri (DSP silikon davranışı, 250 MHz kapanışı, DDR bant genişliği, DSP bütçesi, PTQ
mAP, derleyici doğruluğu) kilometre taşı kapılarıyla yönetildi. M9 sonunda 250 MHz
kapanışı (+0,038 ns, [[fpga-timing-closure]]) ve DDR bant genişliği riski (dedicated port)
kapanmış, 30 fps hedefi 43,9 fps ile aşılmıştır ([[board-bringup-flow]]).

## Sonuç
OpenEye'ı optimize etmek hedefe yaklaştıramaz; mimari tavan hedefin çok altındadır ve
RAM10 yoğunluğu ölçeklemeyi engeller. StalyaNPU hedefe erişen seçenek oldu: teorik tepe
512 GMAC/s, board'da **43,9 fps** (bit bit doğru, iki koşumda aynı CRC, 2026-09-15); kalan
işler stem L0 modu ve ağırlık tekrar akışı gibi marj kalemleridir. OpenEye yalnızca çok
küçük ağlar ve ReLU tabanlı op kümesi için anlamlı kalır; bu projede M7'de tasarımdan
çıkarılmıştır.

## Kaynaklar
- [[stalyanpu-decision-record]]: tüm ölçüm ve tavan sayıları
- [[stalyanpu-architecture]]: StalyaNPU kaynak tahmini
- [[stalyanpu-synthesis-guide]]: gerçekleşen kaynak ve zamanlama
- [[stalyanpu-bringup-guide]]: board fps (24,6 → 43,9)
- [[stalyanpu-perf-plan]]: M9 adımları ve sonuçları
- [[stalyanpu-readme]]: kilometre taşı durumu
