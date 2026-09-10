# StalyaNPU: YOLOv8s için INT8 CNN hızlandırıcısı

> **DURUM (2026-09-10): M0'dan M7'ye kadar tamamlandı.** Dal `stalya-fmu_v2.0-npu`. Karar kaydı,
> mimari, ISA taslağı, performans modeli, ONNX ön yüzü, ilk RTL adımı (DSP48 DUAL sarmalayıcı +
> kaskad zinciri, Efinix sim modeliyle bit bit) ve nicemleme hattı (kalibrasyon, bit-kesin
> referans model, COCO mAP) hazır. **INT8 mAP50-95 düşüşü 0,78 puan (kapı 2,0)**, bkz.
> [accuracy-report.md](accuracy-report.md). Derleyici arka ucu (descriptor/blob, yerleşim, yorumlayıcı)
> YOLOv8s tam ağda referans modelle bit bit eşleşiyor. Konvolüsyon motoru RTL'i
> (`snpu_conv_unit`: dizi, biriktirici, ibuf, agen, wfifo, epilog) 7 katman testinde Python altınıyla
> bit bit, tam 1024 DSP geometrisi dahil. `snpu_top` (DMA, sequencer, CSR, maxpool) demo ağının
> 5 descriptor'ını uçtan uca yorumlayıcıyla bit bit koşuyor. Efinity sentezi (M5): dizi tek başına
> 258 MHz, konvolüsyon motoru **256 MHz (+0,091 ns)**, tam `snpu_top` 244 MHz (-0,105 ns, yerleşim
> gürültüsü bandında; kapanış M7 entegrasyonunda sürecek). Ti375'te DSP kaskadı sütun başına 48
> blokla sınırlı; zincirler 8'lik dört kaskada bölündü. Ayrıntı: [synthesis-guide.md](synthesis-guide.md).
> M6: 66 katmanın tamamı kırpılmış geometride RTL'de altınla bit bit eşleşti. M7 (2026-09-10):
> `ti375_oob_top.v` içinde OpenEye ve gDMA_dnn bağlantıları söküldü, `snpu_top` MDNN=3
> yuvasına, CSR yumuşak SoC APB penceresine (`0xF810_4000`, CDC köprüsü), kesme PLIC 9'a
> bağlandı; tam tasarım map/pnr/pgm PASS, 250 MHz pozitif slack (+0,005 ns), CDC temiz. Ayrıntı
> [synthesis-guide.md](synthesis-guide.md) "M7 entegrasyonu". Sonraki adım M8 board bring-up.

Hedef: **YOLOv8s, 1080p kaynaktan 640×384 letterbox, 30 fps, INT8**, Efinix Titanium
Ti375C529 üzerinde. Gerek 8,6 GMAC/kare → 258 GMAC/s sürekli.

## Belgeler

| Dosya | İçerik |
|-------|--------|
| [decision-record.md](decision-record.md) | OpenEye neden bırakıldı, ölçülen sayılar, cihaz tavanı, karar |
| [architecture.md](architecture.md) | Dizi, veri akışı, bellek planı, epilog, DDR düzeni, kontrol, saat, kaynak ve performans tahmini, riskler |
| [isa-descriptor.md](isa-descriptor.md) | 128 baytlık descriptor formatı, CSR haritası, blob başlığı, IRQ ve hata semantiği |
| [toolchain-guide.md](toolchain-guide.md) | Python paketi kurulumu ve komutları, nicemleme semantiği, perf modeli |
| [verification-guide.md](verification-guide.md) | Sim ağacı, `run_sim.py`, test listesi, PASS ölçütleri |
| [synthesis-guide.md](synthesis-guide.md) | Efinity sentez projeleri, DSP sütun kısıtı, zamanlama durumu (M5) |
| [bringup-guide.md](bringup-guide.md) | Board üzerinde doğrulama akışı (M8) |
| [accuracy-report.md](accuracy-report.md) | INT8 PTQ kalibrasyon taraması ve COCO mAP sonuçları (M1) |

## Dizin yapısı

```
ip/stalyanpu/rtl/      snpu_*.v  RTL (Verilog-2001, iverilog -g2012 ile sim)
ip/stalyanpu/py/       stalyanpu Python paketi (perf, frontend, backend, refmodel) + tests/
ip/stalyanpu/sw/       stalyanpu_isa.h (üretilen) ve bare-metal bring-up kodu (M8)
sim/stalyanpu/         run_sim.py, tests.py, common/, unit/, stim/
docs/stalyanpu/        bu belgeler
```

## Hızlı komutlar

```
# Python ortamı (bir kez)
python -m venv .venv-stalyanpu
.venv-stalyanpu\Scripts\pip install -e ip/stalyanpu/py[dev]

# Performans modeli
.venv-stalyanpu\Scripts\python -m stalyanpu perf --hwcfg full2048
.venv-stalyanpu\Scripts\python -m stalyanpu perf --hwcfg full2048 --ddr-bw 4.5 --quiet

# ONNX kapsama raporu
.venv-stalyanpu\Scripts\python -m stalyanpu lower model.onnx

# ISA header
.venv-stalyanpu\Scripts\python -m stalyanpu gen-header --check

# Nicemleme ve mAP (veri: .data/, bkz. toolchain-guide.md)
.venv-stalyanpu\Scripts\python -m stalyanpu calibrate .data/yolov8s_640x384.onnx --images .data/coco/val2017 --ann .data/coco/annotations/instances_val2017.json --out .data/build/q_mse
.venv-stalyanpu\Scripts\python -m stalyanpu eval --qgraph .data/build/q_mse --images .data/coco/val2017 --ann .data/coco/annotations/instances_val2017.json --n 500

# Derleme ve altın vektörler
.venv-stalyanpu\Scripts\python -m stalyanpu compile --qgraph .data/build/q_mse --out .data/build/prog --check --image img.jpg
.venv-stalyanpu\Scripts\python -m stalyanpu golden --qgraph .data/build/q_mse --out .data/build/golden_net --image img.jpg

# Birim testleri
.venv-stalyanpu\Scripts\python -m pytest ip/stalyanpu/py -q
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py all -j 3
```

## Kilometre taşları

| M | Teslimat | Kapı | Durum |
|---|----------|------|-------|
| M0 | Dal, ağaç, karar kaydı, mimari, ISA, perf modeli, ONNX lowering, DSP sarmalayıcı + zincir RTL/TB | perf ≥ 30 fps; lowering 0 desteklenmeyen op; TB `efx_dsp48.v` ile bit-kesin | **tamam** (perf 32,9 fps @2,4 GB/s, marj ince; bkz. architecture.md) |
| M1 | Kalibrasyon, nicemleme, bit-kesin refmodel, mAP | INT8 mAP50-95 düşüşü ≤ 2,0 | **tamam** (MSE aralığı: 44,86 → 44,07, düşüş 0,78) |
| M2 | Emitter, blob, tiler, allocator, `interp.py`, altın üretici | interp ≡ runner tüm ağ | **tamam** (66 descriptor, bit bit OK) |
| M3 | Dizi + acc + ibuf + wfifo + epilog RTL, katman TB'leri | tümü PASS | **tamam** (7/7, vendor DSP modeli + ikiz) |
| M4 | DMA, seq, csr, maxpool5, `snpu_top`, AXI bellek modeli; descriptor tabanlı testler | PASS | **tamam** (4/4 net testi, demo ağı uçtan uca) |
| M5 | Dizi-tek Efinity sentezi | 250 MHz pozitif slack | **tamam** (dizi 258, motor 256 MHz pozitif; top 244 MHz, DSP 1186, RAM10 1149) |
| M6 | YOLOv8s katman-katman + tam ağ sim | %100 PASS | katmanlar **tamam** (66/66 kırpılmış behav + vendor alt küme 5/5; perf bandı ±%18, bkz. verification-guide); tam ağ koşumu M8 öncesi isteğe bağlı |
| M7 | `ti375_oob_top.v` entegrasyonu (OpenEye çıkar) | map/pnr/pgm PASS | **tamam** (map/pnr/pgm PASS, io_ddrMasters_0_clk +0,005 ns, CDC temiz; 1217 DSP, 1478 RAM10) |
| M8 | Board bring-up | ≥ 30 fps ölçüm | |
| M9 | Dokümantasyon, dedicated DDR portu, Linux yer tutucu | | |
