---
title: "YOLOv8s"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 8
tags: [yolov8s, dnn, object-detection, int8, coco]
---

# YOLOv8s

## Tanım
Ultralytics YOLOv8 ailesinin "small" nesne tespit modeli. [[stalyanpu]] projesinin hedef
ağıdır: 1080p kaynaktan 640×384 letterbox giriş, INT8, 30 fps.

## Temel Bilgiler
**Hesap yükü.** 640×384'te **8,58 GMAC/kare** (640×640'ta 14,3 GMAC; Ultralytics'in
28,6 GFLOP değeriyle uyumlu). 30 fps için 258 GMAC/s sürekli işlem gücü gerekir; bu değer
[[dnn-accelerator-options]] kararının ve [[analytic-performance-model]]'in çıkış noktasıdır.
Doğal 1920×1088 çıkarım (73 GMAC/kare) hedeften çıkarılmıştır; 640×640 için uzatma hedefi
≥ 20 fps.

**Op kümesi.** Conv 1×1 ve 3×3 (stride 1/2), SiLU, residual Add, Concat, Split, Upsample ×2
(nearest), SPPF MaxPool 5×5 s1 p2. Tüm kanal ofsetleri 32'nin katı olduğundan NC32HW
düzeninde Concat/Split/Upsample sıfır kopyadır; neck'teki Resize + skip concat'i
`TWO_SRC` ile iki kaynaktan okunur ([[descriptor-isa]]). Kesim noktası altı head 1×1 conv
çıkışı (3 ölçek × {box 64, cls 80}); DFL, decode, sigmoid ve NMS CPU'da (sert RISC-V, < 1 ms).

**Derlenmiş biçim.** 66 descriptor, 52 tampon, scratch 11,6 MB, blob 11,3 MB
(benzersiz ağırlık 11,1 MB). DDR trafiği modelde 63,8 MB/kare. Baskın gruplar Detect.P3
(%13), L2.c2f (%11), L4.c2f (%8), L0 (%8); stem L0 (IC=3) tek başına 601 kçevrim modelde,
board'da descriptor 0 1,8 M çevrim.

**Nicemleme.** ONNX opset 13, BN katlanmış. INT8 PTQ ile COCO val (500 görüntü) mAP50-95
44,86 → 44,07 (düşüş 0,78, kapı 2,0); MSE aralık araması, 256 kalibrasyon görüntüsü
([[int8-quantization-flow]], [[stalyanpu-accuracy-report]]). SiLU kuyruğundaki büyük
değerler tespit bilgisi taşıdığından aralık kırpma hızla zarar verir.

**Doğrulama ve board.** 66 katmanın her biri kırpılmış geometride RTL'de altınla bit bit;
board'da tam kare 66 descriptor bit bit doğru: M8 sonu 24,6 fps, M9 (2026-09-15) döşeme
çift tamponu ile 28,1 fps, dedicated 512-bit DDR portu ile **43,9 fps** (5,69 M
çevrim/kare, MAC %85; 30 fps hedefi aşıldı) ([[board-bringup-flow]]).

## Kaynaklarda Geçişi
- [[stalyanpu-readme]]: hedef tanımı ve kilometre taşları
- [[stalyanpu-architecture]]: baskın katman grupları, NC32HW uyumu, L0 stem planı
- [[stalyanpu-isa-descriptor]]: 66 descriptor, tampon yerleşimi, kanal hizası
- [[stalyanpu-decision-record]]: GMAC/kare hesabı, 640×640 ve 1080p değerlendirmesi
- [[stalyanpu-verification-guide]]: Y1/Y2 katman ve tam ağ testleri
- [[stalyanpu-toolchain-guide]]: export, calibrate, eval komutları; katman tablosu `perf/layers.py`
- [[stalyanpu-bringup-guide]]: board'da tam kare ölçümleri
- [[stalyanpu-accuracy-report]]: mAP sonuçları

## İlişkiler
- [[stalyanpu]]: bu model için tasarlanan hızlandırıcı
- [[stalyanpu-toolchain]]: ONNX'ten descriptor'a dönüştüren araç zinciri
- [[openeye]]: op kümesini (SiLU, Add, Concat, Split, Upsample, SPPF) desteklemeyen önceki hızlandırıcı
- [[int8-quantization-flow]], [[analytic-performance-model]], [[descriptor-isa]]: ilgili kavramlar
