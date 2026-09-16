---
title: "Kaynak: StalyaNPU Araç Zinciri"
type: source
source_file: "ip/stalyanpu/docs/toolchain-guide.md"
author: "volvox"
date: 2026-09-14
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, toolchain, python, quantization, compiler, perf-model]
---

# Kaynak: StalyaNPU Araç Zinciri

## Özet
`py/stalyanpu` Python paketinin ([[stalyanpu-toolchain]]) kurulumunu, komut satırı
arayüzünü, referans modeli, derleyici arka ucunu, paket düzenini, nicemleme semantiğini ve
analitik performans modelinin formülünü anlatır. Paket sistem Python 3.14 ile düz venv'de
çalışır; Efinity python311 ve `.pydeps-openeye` hilesi gerekmez; TensorFlow yoktur.

## Temel Çıkarımlar
- Komutlar: `perf`, `lower`, `gen-header` (M0); `export`, `calibrate`, `eval`, `check-tail` (M1); `compile`, `golden` (M2).
- Referans model `refmodel/` int8 conv'u im2col × float64 matmul ile tam hesaplar; `QRunner` YOLOv8s 640×384 karesini ≈ 0,75 s'de yürütür.
- Nicemleme: ağırlık int8 simetrik OC başına, aktivasyon int8 tensör başına asimetrik; requant `mult ∈ [2^15, 2^16)`, `shift ∈ [0,47]`, yarım yukarı; SiLU 256 girişli LUT; ölçek birleştirme union-find.
- M2 kapısı: YOLOv8s tam ağda `interp == runner` bit bit, 546 pytest.
- Performans modeli: `cycles = max(cyc_mac + cyc_tile, cyc_ddr) + t_op`; varsayılanlar t_pass 10, t_tile 200, t_op 4000, DDR 2,4 GB/s (ek yükler 2026-09-16'da üç board karesine oturtuldu, önceki değerler 40 / 150 / 500).

## Detaylı Notlar
**Kurulum ve veri.** `python -m venv .venv-stalyanpu`, `pip install -e py[dev]`; `[export]`
ekstrası (torch, ultralytics, pycocotools) yalnız ONNX dışa aktarma ve COCO mAP için.
`.data/` altında `yolov8s.pt`, `yolov8s_640x384.onnx`, COCO açıklamaları ve yalnız kullanılan
739 val2017 görüntüsü (kalibrasyon seed 0 ilk 256, değerlendirme seed 1 ilk 500;
`eval/coco.py:image_list` deterministik).

**Komutlar.** `perf [--hwcfg full2048|small256|cfg.json] [--width --height] [--ddr-bw]
[--clk] [--cpu-ms] [--markdown]` analitik çevrim modeli ve fps; `lower model.onnx [--cut]`
ONNX'i hızlandırıcı op kümesine indirir ve kapsama raporu üretir; `gen-header [--check]`
`stalyanpu_isa.h` üretir; `export` ultralytics ile ONNX; `calibrate ... [--ncalib 256]
[--method mse|minmax|percentile]` lowering + kalibrasyon + nicemleme (`qgraph.json/npz`,
`calib_stats.json`); `eval` FP32 (onnxruntime) ve INT8 mAP'i aynı numpy tail ile;
`check-tail` numpy DFL/decode çıktısını ONNX head ile karşılaştırır; `compile --qgraph
--out [--base 0x20000000 --scratch 0x28000000] [--check] [--image]` descriptor + blob
(`frame.bin`, `alloc.json`); `golden` sim vektörleri (`mem.hex`, `golden.hex`, `golden.json`).

**Referans model.** `intops.py` (int8 conv, OC başına requant, LUT, residual add iki
yeniden ölçek yolu, maxpool5, upsample2, concat/split), `runner.py` (`QRunner`, `keep_all`),
`tail.py` (anchor, DFL softmax-beklenti, decode, sigmoid, sınıf-ofsetli NMS; ONNX head ile
fark kutu 1e-4 px, skor 2e-7), `quant/` (`calib.py`, `ranges.py`, `params.py`, `qgraph.py`).

**Backend.** `layout.py` NC32HW paketleme; `weightpack.py` ağırlık/param/LUT; `tiler.py`
döşeme seçimi (perf modeli de kullanır); `alloc.py` sıfır kopya yerleşim + first-fit;
`emit.py` descriptor/blob; `interp.py` descriptor yorumlayıcı (sayfalı seyrek bellek);
`compile.py`; `golden/`. Ayrıntı [[descriptor-isa]] ve [[stalyanpu-isa-descriptor]].

**Paket düzeni.** `hwcfg.py` (HwConfig: dizi geometrisi, tamponlar, saat, DDR, ek yük
sabitleri, presetler), `perf/{layers,model,report}.py`, `frontend/{onnx_import,patterns,
lower,graph}.py` (Conv 1×1/3×3 s1/s2, MaxPool 5s1p2, Resize nearest ×2, Concat/Split 32
hizası, SiLU deseni; NPU/CPU kesimi; Conv+SiLU ve Conv+Add füzyonu), `backend/`,
`golden/`, `refmodel/`, `quant/`, `eval/`; `tests/` 546 pytest.

**Nicemleme semantiği.** [[int8-quantization-flow]] kavramının uygulama tanımı: giriş zp
`-zp_in·Σw` ile int32 bias'a katlanır, dolgu `zp_in`, dizi düz `Σ int8·int8`; bağıl
hassasiyet 2^-15; SiLU ön-aktivasyon tensörünün kendi ölçeği ayrıca kalibre edilir;
Concat/Add/Split/MaxPool/Upsample kenarlarında ölçek birleştirme, "kabalaşma katsayısı"
> 4 raporlanır; kalibrasyon 256 COCO val görüntüsü, letterbox 640×384 gri 114, varsayılan
MSE araması ([[stalyanpu-accuracy-report]]). Kesim altı head 1×1 conv çıkışı; DFL, decode,
sigmoid, NMS CPU'da (`tail.py` ve C ikizi).

**Performans modeli.** [[analytic-performance-model]] formülü katman başına:
`n_pass = ceil(IC/n_ic)·k²`, `n_oct = ceil(OC/n_oc)`,
`cyc_mac = Σ_t n_oct·n_pass·(P_t + t_pass)`, `cyc_tile = n_tiles·t_tile + ilk döşeme dolumu`,
`cyc_ddr = baytlar / (bant genişliği / saat)`, `cycles = max(cyc_mac + cyc_tile, cyc_ddr) + t_op`.
Döşeme: tam çıkış satırları, `P_t ≤ p_max`, giriş ayak izi ≤ ibuf/2. Model M6'da sim, M8'de
donanım sayaçlarıyla kalibre edilir ([[stalyanpu-verification-guide]], [[stalyanpu-bringup-guide]]).

> ❓ **Belirsiz:** Belge board araçlarını (`stalyanpu.board.ddrimage`, `board.py`) komut
> tablosunda listelemez; bunlar yalnız [[stalyanpu-bringup-guide]]'da geçer.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu-toolchain]], [[stalyanpu]], [[yolov8s]]
- İlgili kavramlar: [[int8-quantization-flow]], [[descriptor-isa]], [[analytic-performance-model]]
- Destekleyen kaynaklar: [[stalyanpu-isa-descriptor]], [[stalyanpu-accuracy-report]], [[stalyanpu-verification-guide]], [[stalyanpu-readme]]

## Alıntılar
- "Kapı (M2): YOLOv8s tam ağda `interp == runner` bit bit (gerçek COCO görüntüsü), 546 pytest." (satır 55)
- "cycles = max(cyc_mac + cyc_tile, cyc_ddr) + t_op" (satır 108)
