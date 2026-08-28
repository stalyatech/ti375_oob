# StalyaNPU: YOLOv8s için INT8 CNN hızlandırıcısı

> **DURUM (2026-08-28): M0 tamamlandı.** Dal `stalya-fmu_v2.0-npu`. OpenEye yerine sıfırdan
> tasarlanan hızlandırıcının karar kaydı, mimarisi, ISA taslağı, performans modeli, ONNX
> ön yüzü ve ilk RTL adımı (DSP48 DUAL sarmalayıcı + kaskad zinciri, Efinix sim modeliyle
> bit bit doğrulandı) hazır. Sonraki adım M1 (nicemleme + referans model + mAP).
> Üst seviye tasarım (`ti375_oob_top.v`) henüz değişmedi; OpenEye bitstream'i bozulmadı.

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
| [bringup-guide.md](bringup-guide.md) | Board üzerinde doğrulama akışı (M8) |

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

# Birim testleri
.venv-stalyanpu\Scripts\python -m pytest ip/stalyanpu/py -q
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit -j 3
```

## Kilometre taşları

| M | Teslimat | Kapı | Durum |
|---|----------|------|-------|
| M0 | Dal, ağaç, karar kaydı, mimari, ISA, perf modeli, ONNX lowering, DSP sarmalayıcı + zincir RTL/TB | perf ≥ 30 fps; lowering 0 desteklenmeyen op; TB `efx_dsp48.v` ile bit-kesin | **tamam** (perf 32,9 fps @2,4 GB/s, marj ince; bkz. architecture.md) |
| M1 | Kalibrasyon, nicemleme, bit-kesin refmodel, mAP | INT8 mAP50-95 düşüşü ≤ 2,0 | |
| M2 | Emitter, blob, tiler, allocator, `interp.py`, altın üretici | interp ≡ runner tüm ağ | |
| M3 | Dizi + acc + ibuf + wfifo + epilog RTL, birim TB'ler, AXI bellek modeli | tümü PASS | |
| M4 | DMA, seq, csr, `snpu_top`; katman testleri | PASS, çevrim ±%15 | |
| M5 | Dizi-tek Efinity sentezi | 250 MHz pozitif slack | |
| M6 | YOLOv8s katman-katman + tam ağ sim | %100 PASS | |
| M7 | `ti375_oob_top.v` entegrasyonu (OpenEye çıkar) | map/pnr/pgm PASS | |
| M8 | Board bring-up | ≥ 30 fps ölçüm | |
| M9 | Dokümantasyon, dedicated DDR portu, Linux yer tutucu | | |
