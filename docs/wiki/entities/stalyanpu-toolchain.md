---
title: "StalyaNPU Araç Zinciri (py/stalyanpu)"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 7
tags: [stalyanpu, toolchain, python, compiler, quantization, golden-model]
---

# StalyaNPU Araç Zinciri (py/stalyanpu)

## Tanım
[[stalyanpu]] için yazılan Python paketi. ONNX lowering, INT8 kalibrasyon ve nicemleme,
bit-kesin referans model, descriptor/blob derleyici ve yorumlayıcı, simülasyon altın
vektörleri, analitik performans modeli ve board araçlarını tek `python -m stalyanpu`
komutu altında toplar. Sistem Python 3.14 ile düz venv'de çalışır; TensorFlow ve Efinity
python311 gerekmez.

## Temel Bilgiler
**Komutlar.** `perf` ([[analytic-performance-model]]), `lower`, `gen-header`, `export`,
`calibrate`, `eval`, `check-tail`, `compile`, `golden`, `ipgen`, `gui`; ayrıca `stalyanpu.board.ddrimage`
ve `sw/baremetal/npu_test/board.py` (program, openocd, run, dumplog, npu) board akışında
kullanılır ([[board-bringup-flow]]).

**Katmanlar.**
- `hwcfg.py`: HwConfig (dizi geometrisi, tamponlar, saat, DDR, ek yük sabitleri; `full2048`,
  `small256` presetleri); RTL `snpu_pkg.vh` ile aynı değerler.
- `frontend/`: ONNX yükleme, op kısıt denetimleri (Conv 1×1/3×3 s1/s2, MaxPool 5s1p2,
  Resize nearest ×2, Concat/Split 32 hizası, SiLU deseni), NPU/CPU kesimi, Conv+SiLU ve
  Conv+Add füzyonu, `NpuGraph` IR.
- `quant/` ve `refmodel/`: kalibrasyon (min/max, yüzdelik, MSE araması), union-find ölçek
  birleştirme, OC başına u16 mult/shift, SiLU LUT; `QRunner` int8 conv'u im2col × float64
  matmul ile tam hesaplar (YOLOv8s karesi ≈ 0,75 s); `tail.py` DFL/decode/NMS
  ([[int8-quantization-flow]]).
- `backend/`: `isa.py` tek doğru kaynak (descriptor, CSR, blob; C başlığı buradan üretilir),
  `layout.py` NC32HW, `weightpack.py`, `tiler.py`, `alloc.py` sıfır kopya first-fit,
  `emit.py`, `interp.py` sayfalı seyrek bellekli yorumlayıcı, `compile.py`
  ([[descriptor-isa]]).
- `golden/`: `mem.hex`, `golden.hex`, `golden.json`; katman ve demo ağı vektörleri.
- `perf/`: [[yolov8s]] katman tablosu (yaml'dan, ONNX gerekmez), katman başına çevrim modeli, rapor.
- `eval/`: letterbox ön işleme, COCO mAP (pycocotools).

**Kapılar.** M0: lowering 0 desteklenmeyen op; M1: INT8 mAP düşüşü 0,78 ≤ 2,0
([[stalyanpu-accuracy-report]]); M2: YOLOv8s tam ağda `interp == runner` bit bit, 546 pytest.
Aynı Python kodu hem altın vektörleri hem descriptor'ları ürettiğinden derleyici doğruluğu
riski (R6) `interp ≡ runner` kapısıyla karşılanır.

**Veri.** `.data/` (gitignore): `yolov8s.pt`, `yolov8s_640x384.onnx`, COCO açıklamaları,
yalnız kullanılan 739 val2017 görüntüsü; `[export]` ekstrası (torch, ultralytics,
pycocotools) yalnız dışa aktarma ve mAP için.

**M9 eklemeleri (2026-09-15).**
- `emit.py`: döşeme çift tamponu için her döşemenin giriş ayak izinin ibuf'un yarısına
  sığdığını derleme sırasında denetler; donanım aynı şartı hata 7 (geometri) ile korur.
- `isa.py`: DBG0/DBG1 bit düzeni üç kanallı okuma DMA'sına göre yenilendi; DBG6 (0x58,
  `dbg_ext_i`) eklendi. `board.py npu` DBG0/DBG1'i yeni düzene göre, DBG6'yı
  [[snpu-axi-up512]] alanlarına göre çözer. `board.py program` OpenOCD açıkken JTAG'in
  kaybolmaması için önce sunucuyu kapatır.
- `sim/tests.py`: sistem testleri `_256` ve `_up512` varyantlarıyla (`MEM_DW` parametresi,
  512'de genişletici araya girer) kayıtlı; `+EXPECT_OVERLAP=1` dolum/koşum örtüşmesini
  şart koşar. pytest 546, sim paketi 22/22 PASS.

**IP Generator ve `ipgen` (2026-09-15).** `gui/` alt paketi yerel web arayüzünü ekler
(`python -m stalyanpu gui`, `gui.cmd`, `gui.sh`, `stalyanpu-gui`; stdlib HTTP sunucusu, ek
bağımlılık yok): geometri/saat/DDR portu seçimiyle anlık fps ve kaynak kestirimi, ONNX'ten
blob'a seçimli akış zinciri, board adımları, IP paketi üretimi ve canlı iş logları.
Destekleyen kütüphane eklemeleri: `hwcfg.validate/legal_geometries/geometry_word/DDR_PORTS`
(`load()` kopya döndürür), `perf/adapter.py` (ONNX graf'ından katman tablosu),
`perf/resources.py` (hiyerarşik rapora çapalı DSP/RAM10/XLR), `perf/calibration.py` (board
çapaları), `backend/rtlparams.py` (Verilog parametreleri, define'lar, sarmalayıcılar,
`-P` sim argümanları), `quant/images.py` (`calibrate --image-dir`), `perf --model/--json`,
`syn/run_syn.py --project-dir`. pytest 589 ([[stalyanpu-ip-generator]]).

## Kaynaklarda Geçişi
- [[stalyanpu-ip-generator]]: web arayüzü, `ipgen`, adaptör, kaynak kestirimi, ölçüm çapası
- [[stalyanpu-readme]]: paket dizini ve hızlı komutlar
- [[stalyanpu-isa-descriptor]]: `isa.py` tek kaynak, `weightpack.py`, `alloc.py`, `emit.py`, `interp.py`, DBG6
- [[stalyanpu-toolchain-guide]]: kurulum, komut tablosu, paket düzeni, nicemleme semantiği, perf formülü
- [[stalyanpu-verification-guide]]: `golden.unit`, `golden.demo`, `stalyanpu golden`, `perf_compare.py`, `tests.py` varyantları
- [[stalyanpu-bringup-guide]]: `ddrimage`, `build.py`, `board.py`, OpenOCD sırası
- [[stalyanpu-accuracy-report]]: `export`, `calibrate`, `eval` ile yeniden üretim

## İlişkiler
- [[stalyanpu]]: hedef donanım
- [[yolov8s]]: derlenen model
- [[ti375-devkit]]: board araçlarının hedefi
- [[snpu-axi-up512]]: `board.py`'nin DBG6 ile çözdüğü genişletici
- [[efinity-toolchain]]: Efinity OpenOCD ve FTDI programlayıcı `board.py` tarafından çağrılır
- Kavramlar: [[int8-quantization-flow]], [[descriptor-isa]], [[analytic-performance-model]], [[board-bringup-flow]]
