---
title: "Kaynak: StalyaNPU Doğruluk Raporu (M1)"
type: source
source_file: "ip/stalyanpu/docs/accuracy-report.md"
author: "volvox"
date: 2026-08-28
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, quantization, int8, ptq, coco, map, yolov8s]
---

# Kaynak: StalyaNPU Doğruluk Raporu (M1)

## Özet
[[yolov8s]] modelinin INT8 eğitim sonrası nicemlemesinin (PTQ) COCO val2017 üzerinde
ölçülmüş doğruluğunu raporlar. FP32 referans mAP50-95 44,86; MSE aralık aramasıyla INT8
44,07, düşüş **0,78 puan** (kapı ≤ 2,0). Min/max, yüzdelik ve KL/entropi yöntemleri
karşılaştırılmış; üretim kalibrasyonu `--method mse`, 256 görüntü olarak seçilmiştir.

## Temel Çıkarımlar
- Değerlendirme: 500 val2017 görüntüsü (seed 1), kalibrasyon 256 görüntü (seed 0, ayrık küme), letterbox 640×384 gri 114, conf 0,001, IoU 0,7, max 300; FP32 (onnxruntime) ve INT8 (bit-kesin referans model) aynı numpy tail ile.
- Kırpma zarar veriyor: aralık daraldıkça mAP hızla düşer (yüzdelik 99,0 → 16,7 puan kayıp).
- SQNR yanıltıcı: en iyi kalibrasyonda orta katmanlarda ~17 dB kalır ama mAP en yüksektir; kararlar mAP ile verilir.
- Hata kaynağı erken katmanlar (katman 0/1 SQNR 28/24,5 dB); SiLU'nun çift nicemlenmesi katman başına yalnız 1,5-3 dB ekler, 10-bit LUT indeksi büyük kazanç getirmez.
- Kanal başına aktivasyon ölçeği gerekirse ISA'nın param bloğu (OC başına 8 bayt) buna yer bırakır; M1'de gerekmedi.

## Detaylı Notlar
**Nicemleme şeması.** Ağırlık int8 simetrik, OC başına ölçek; aktivasyon int8 asimetrik,
tensör başına ölçek ve zp; zp bias'a katlanır, dolgu zp ile. Conv çıkışı (ön-aktivasyon)
int8'e requant (u16 çarpan, yarım yukarı), SiLU 256'lık LUT, residual Add birleşik ölçekle,
Concat/Split/MaxPool/Upsample ölçek birleştirme (union-find, 11 grup). Kesim altı head 1×1
conv çıkışı; DFL/decode/NMS float. Bu şema [[int8-quantization-flow]] kavramının
ölçülmüş sürümüdür; uygulama [[stalyanpu-toolchain-guide]]'da, donanım aritmetiği
[[stalyanpu-isa-descriptor]]'da tanımlıdır.

**Sonuçlar (COCO val 500).**

| Kalibrasyon aralığı | mAP50-95 | mAP50 | Düşüş | Kapı ≤ 2,0 |
|---|---:|---:|---:|:---:|
| FP32 referans | 44,86 | 60,87 | | |
| MSE araması | 44,07 | 60,16 | 0,78 | evet |
| min/max (256 görüntü) | 43,80 | 59,64 | 1,05 | evet |
| yüzdelik 99,999 | 42,70 | 59,25 | 2,15 | hayır |
| yüzdelik 99,99 | 41,69 | 58,08 | 3,17 | hayır |
| yüzdelik 99,9 | 39,45 | 55,57 | 5,41 | hayır |
| yüzdelik 99,0 | 28,12 | 40,48 | 16,73 | hayır |

MSE araması min/max'tan başlayıp ortak katsayıyla daraltır; ön-aktivasyonda hata SiLU
sonrası ölçülür. KL/entropi prototipi asimetrik aralık uyarlaması hatalı olduğundan (mAP 0)
koddan çıkarıldı. FP32 değeri yayınlanan 640×640 sonucuyla (44,9) uyumludur; 640×384
letterbox'ın kendi kaybı ayrıca ölçülmemiştir.

**Bulgular.** (1) YOLOv8'in SiLU aktivasyonlarında kuyruktaki büyük değerler tespit bilgisi
taşır; MSE çoğu tensörde min/max'a yakın, bazılarında biraz daha dar aralık seçer. (2) SQNR
yalnız hata ayıklama içindir (`scratch: sqnr.py`). (3) `fsilu` deneyi (SiLU'yu tam
biriktiriciden float hesaplayıp tek nicemleme) çift nicemlemenin maliyetini 1,5-3 dB olarak
ölçtü. (4) Kanal başına aktivasyon ölçeği için donanımda kanal başına zp dolgusu ve OC
başına LUT gerekir.

**Karar.** Üretim kalibrasyonu `--method mse`, 256 görüntü (CLI varsayılanı). Daha büyük
kalibrasyon kümesi (1000 görüntü) ve ölçek birleştirme gruplarında tensör başına ayrı yeniden
ölçek (`res_mult_a/b` hazır) M2 sırasında denenebilir; ISA değişmez.

**Yeniden üretme ve süreler.** `export` → `calibrate --ncalib 256 --method mse` → `eval
--n 500 --seed 1`. Kalibrasyon ≈ 1,5 dk (minmax) / 3,5 dk (mse); INT8 referans kare 0,75 s;
500 görüntülük FP32+INT8 değerlendirme ≈ 8 dk (tek süreç).

> ❓ **Belirsiz:** Rapor referans modelin mAP'ını verir; board'daki RTL çıktısı referansla
> bit bit eşleştiğinden ([[stalyanpu-bringup-guide]]) aynı mAP donanım için de geçerli
> sayılabilir, ama donanım çıktısından doğrudan mAP ölçümü belgelenmemiştir.

## Bağlantılar
- İlgili varlıklar: [[yolov8s]], [[stalyanpu-toolchain]], [[stalyanpu]]
- İlgili kavramlar: [[int8-quantization-flow]]
- Destekleyen kaynaklar: [[stalyanpu-toolchain-guide]], [[stalyanpu-isa-descriptor]], [[stalyanpu-readme]]

## Alıntılar
- "Kırpma zarar veriyor. Aralık daraldıkça mAP hızla düşüyor (99,0 yüzdelik → 16,7 puan). YOLOv8'in SiLU aktivasyonlarında kuyruktaki büyük değerler tespit bilgisi taşıyor." (satır 38-40)
- "Üretim kalibrasyonu: `--method mse`, 256 görüntü (CLI varsayılanı). Kabul: düşüş 0,78 puan (kapı 2,0)." (satır 56-57)
