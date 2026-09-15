---
title: "INT8 Nicemleme Akışı"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 5
tags: [quantization, int8, ptq, calibration, requant, silu-lut]
---

# INT8 Nicemleme Akışı

## Tanım
[[yolov8s]] FP32 modelini [[stalyanpu]] donanımının tamsayı aritmetiğine indiren eğitim
sonrası nicemleme (PTQ) hattı: kalibrasyon, OC başına ağırlık ölçeği, tensör başına
aktivasyon ölçeği, u16 requant, SiLU LUT, ölçek birleştirme ve bit-kesin referans model.
Donanım çıktısı referans modelle bit bit eşleştiğinden doğruluk yalnız bu akışta ölçülür.

## Detaylı Açıklama
**Şema.** Ağırlıklar int8 simetrik, çıkış kanalı başına ölçek (`absmax/127`). Aktivasyonlar
int8 tensör başına asimetrik (`scale`, `zp ∈ [-128,127]`). Giriş sıfır noktası `-zp_in·Σw`
ile int32 bias'a katlanır; dolgu `zp_in` ile yapılır; dizi düz `Σ int8·int8` hesaplar
([[dsp-chain-systolic-array]]).

**Requant ve epilog.** `s = acc32 + bias`; `q = ((s·mult) + 2^(shift-1)) >> shift` ile
`mult ∈ [2^15, 2^16)`, `shift ∈ [0,47]`, yarım yukarı yuvarlama; `sat8(q + zp_pre)`; SILU
bayrağıyla `y = LUT[q + 128]` (katman başına 256 girişli int8→int8 tablo, ön-aktivasyon
tensörünün kendi ölçeği ayrıca kalibre edilir); residual yolunda iki ayrı yeniden ölçek
(`res_mult_a/b`, `res_shift_a/b`) ve `zp_out2`. Bağıl hassasiyet 2^-15. Referans
`refmodel/fixedpoint.py`; RTL epilogu bununla bit bit karşılaştırılır. Param bloğu OC başına
8 bayt ([[descriptor-isa]]).

**Ölçek birleştirme.** Concat/Add/Split/MaxPool/Upsample kenarlarında union-find ile aralık
birleşimi (YOLOv8s'te 11 grup); "kabalaşma katsayısı" > 4 raporlanır.

**Kalibrasyon.** 256 COCO val2017 görüntüsü (seed 0), letterbox 640×384 gri 114; ORT ile
tüm gerekli tensörler tek geçişte. Yöntemler: min/max, yüzdelik (görüntü başına ortalama),
**MSE araması** (min/max'tan başlayıp ortak katsayıyla daraltma; ön-aktivasyonda hata SiLU
sonrası ölçülür). KL/entropi prototipi hatalıydı ve çıkarıldı. Üretim varsayılanı `--method
mse`, 256 görüntü.

**Referans model ve kesim.** `QRunner` int8 conv'u im2col × float64 matmul ile tam hesaplar
(2^53 altında; en kötü 4608×2^14); YOLOv8s karesi ≈ 0,75 s. Kesim altı head 1×1 conv çıkışı;
DFL softmax-beklenti, decode, sigmoid, sınıf-ofsetli NMS (conf 0,001, IoU 0,7, max 300)
`tail.py`'de ve sert RISC-V'de C ikizinde float çalışır. ONNX head ile fark kutu 1e-4 px.

**Sonuç.** COCO val 500 görüntüde mAP50-95 44,86 → 44,07 (düşüş 0,78, kapı 2,0); mAP50
60,87 → 60,16. Min/max 1,05 düşüşle kapıyı geçer; yüzdelik 99,999 ve altı geçmez. Bulgular:
aralık kırpma SiLU kuyruğundaki tespit bilgisini yok eder; SQNR mAP'ı öngörmez (orta
katmanlarda ~17 dB'de mAP en yüksek); hata erken katmanlardan gelir; SiLU'nun çift
nicemlenmesi katman başına 1,5-3 dB, yani 10-bit LUT indeksi büyük kazanç getirmez.

**Yedekler.** Kanal başına aktivasyon ölçeği (tüketici ağırlıklarına katlanır) donanımda
kanal başına zp dolgusu ve OC başına LUT ister; ISA param bloğu buna yer bırakır. QAT yedek
plan olarak listelidir (risk R5). Daha büyük kalibrasyon kümesi ve gruplarda tensör başına
ayrı yeniden ölçek ISA değişmeden denenebilir.

## Örnekler
- Requant dolgu OC'leri: bias 0, mult 2^15, shift 15 (kimlik ölçek).
- `fsilu` deneyi: SiLU'yu tam biriktiriciden float hesaplayıp tek nicemleme; çift nicemlemenin maliyetini ölçmek için.
- Yeniden üretim: `export` → `calibrate --ncalib 256 --method mse` → `eval --n 500 --seed 1`; kalibrasyon ≈ 3,5 dk, değerlendirme ≈ 8 dk.

## İlişkili Kavramlar
- [[descriptor-isa]]: param bloğu, LUT tabanı, sıfır noktaları ve residual ölçek alanları
- [[dsp-chain-systolic-array]]: düz int8 nokta çarpımı, DSP içinde birikim olmaması
- [[analytic-performance-model]]: nicemlemenin performans modeline etkisi yoktur; her ikisi `hwcfg` üstünde çalışır

## Kaynaklar
- [[stalyanpu-accuracy-report]]: kalibrasyon taraması, mAP tablosu, bulgular ve karar
- [[stalyanpu-toolchain-guide]]: nicemleme semantiği, `quant/` ve `refmodel/` modülleri
- [[stalyanpu-isa-descriptor]]: epilog aritmetiği ve param paketleme
- [[stalyanpu-architecture]]: epilog satırı ve nicemleme özeti
- [[stalyanpu-readme]]: M1 kapısı (0,78 ≤ 2,0)
