# StalyaNPU doğruluk raporu (M1)

Tarih: 2026-08-28. Model: YOLOv8s (ultralytics 8.4, `yolov8s.pt`), ONNX opset 13, giriş 640×384,
BN katlanmış. Değerlendirme: COCO val2017'den 500 görüntü (seed 1), kalibrasyon 256 görüntü
(seed 0, ayrık küme), letterbox 640×384 gri 114, conf 0,001, IoU 0,7, max 300; FP32
(onnxruntime) ve INT8 (bit-kesin referans model, `refmodel/`) **aynı numpy tail** ile
(`tail.py`, ONNX head çıktısıyla farkı kutu 1e-4 px). mAP pycocotools.

## Nicemleme şeması (değerlendirilen)

- Ağırlık int8 simetrik, çıkış kanalı başına ölçek.
- Aktivasyon int8 asimetrik, **tensör başına** ölçek ve zp; zp bias'a katlanır, dolgu zp.
- Conv çıkışı (ön-aktivasyon) int8'e requant (u16 çarpan, yarım yukarı), SiLU 256'lık LUT
  (int8→int8), residual Add birleşik ölçekle, Concat/Split/MaxPool/Upsample ölçek birleştirme
  (union-find, 11 grup).
- Kesim: altı head 1×1 conv çıkışı; DFL/decode/NMS float.

## Sonuçlar (COCO val 500, mAP50-95 / mAP50)

| Kalibrasyon aralığı | mAP50-95 | mAP50 | Düşüş (puan) | Kapı ≤ 2,0 |
|---------------------|---------:|------:|-------------:|:----------:|
| FP32 referans | **44,86** | 60,87 | | |
| **MSE araması** (min/max'tan başlayıp ortak katsayıyla daraltma; ön-aktivasyonda hata SiLU sonrası) | **44,07** | **60,16** | **0,78** | **evet** |
| min/max (256 görüntü) | 43,80 | 59,64 | 1,05 | evet |
| yüzdelik 99,999 (görüntü başına ortalama) | 42,70 | 59,25 | 2,15 | hayır |
| yüzdelik 99,99 | 41,69 | 58,08 | 3,17 | hayır |
| yüzdelik 99,9 | 39,45 | 55,57 | 5,41 | hayır |
| yüzdelik 99,0 | 28,12 | 40,48 | 16,73 | hayır |

Bir KL/entropi (TensorRT tarzı) prototipi de denendi; asimetrik aralık uyarlaması hatalıydı
(mAP 0) ve koddan çıkarıldı. MSE zaten kapıyı geniş marjla sağladığından tekrar ele alınmadı.

FP32 değeri, yayınlanan 640×640 sonucuyla (44,9) uyumludur; 640×384 letterbox'ın kendi
kaybı ayrıca ölçülmemiştir çünkü COCO görüntüleri çoğunlukla 4:3'e yakındır.

## Bulgular

1. **Kırpma zarar veriyor.** Aralık daraldıkça mAP hızla düşüyor (99,0 yüzdelik → 16,7 puan).
   YOLOv8'in SiLU aktivasyonlarında kuyruktaki büyük değerler tespit bilgisi taşıyor. MSE
   araması çoğu tensörde min/max'a yakın, bazılarında biraz daha dar aralık seçiyor ve en
   iyi sonucu veriyor.
2. **SQNR yanıltıcı.** Sinyal/nicemleme gürültü oranı en iyi kalibrasyonda orta katmanlarda
   ~17 dB kalır ama mAP en yüksektir; kararlar mAP ile verilir, SQNR yalnız hata ayıklama
   içindir (`scratch: sqnr.py`).
3. **Hata kaynağı erken katmanlar.** Katman 0/1 çıkışlarının tensör-başına temsil SQNR'ı
   28/24,5 dB (99,99 kalibrasyonunda); sonraki katmanlar bu hatayı taşır (zincir 17 ile 21 dB arası).
   SiLU'nun int8 ön-aktivasyon üzerinden çift nicemlenmesi katman başına yalnız 1,5 ile 3 dB
   ekler (`fsilu` deneyi: SiLU'yu tam biriktiriciden float hesaplayıp tek nicemleme).
   Yani 10-bit LUT indeksi tek başına büyük kazanç getirmez.
4. **Kanal başına aktivasyon ölçeği** (tüketici ağırlıklarına katlanır) daha fazla marj
   isterse yol: donanımda kanal başına zp dolgusu ve OC başına LUT gerekir; ISA'da param
   bloğu zaten OC başına 8 bayt (bias, mult, shift + 1 bayt zp için yer). M1'de gerekmedi.

## Karar

Üretim kalibrasyonu: **`--method mse`, 256 görüntü** (CLI varsayılanı). Kabul: düşüş
0,78 puan (kapı 2,0). Daha büyük kalibrasyon kümesi (1000 görüntü) ve ölçek birleştirme
gruplarında tensör başına ayrı yeniden ölçek (descriptor'da `res_mult_a/b` hazır) M2 sırasında
denenebilir; ISA değişmez.

## Yeniden üretme

```
python -m stalyanpu export --weights yolov8s.pt --out .data/yolov8s_640x384.onnx
python -m stalyanpu calibrate .data/yolov8s_640x384.onnx --images .data/coco/val2017 \
    --ann .data/coco/annotations/instances_val2017.json --out .data/build/q_mse --ncalib 256 --method mse
python -m stalyanpu eval --qgraph .data/build/q_mse --images .data/coco/val2017 \
    --ann .data/coco/annotations/instances_val2017.json --n 500 --seed 1
```

Süreler (host, CPU): kalibrasyon ≈ 1,5 dk (minmax) / 3,5 dk (mse); INT8 referans kare 0,75 s;
500 görüntülük FP32+INT8 değerlendirme ≈ 8 dk (tek süreç).
