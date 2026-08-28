# StalyaNPU araç zinciri

Python paketi `ip/stalyanpu/py/stalyanpu`. Sistem Python 3.14 ile plain venv çalışır
(numpy 2.5, onnx 1.22, onnxruntime 1.29 tekerlekleri mevcut); Efinity python311 ve
`.pydeps-openeye` hilesi bu paket için gerekmez. TensorFlow yok.

## Kurulum

```
python -m venv .venv-stalyanpu
.venv-stalyanpu\Scripts\pip install -e ip/stalyanpu/py[dev]
```

`[export]` ekstrası (torch, ultralytics, pycocotools) yalnız ONNX dışa aktarma ve COCO mAP
için gerekir; M1'de kurulur.

## Komutlar

| Komut | İşlev | Durum |
|-------|-------|-------|
| `python -m stalyanpu perf [--hwcfg full2048\|small256\|cfg.json] [--width 640 --height 384] [--ddr-bw GB/s] [--clk MHz] [--cpu-ms] [--markdown] [--quiet]` | Analitik çevrim modeli, katman tablosu, grup özeti, fps | M0 |
| `python -m stalyanpu lower model.onnx [--cut tensor ...] [--dump]` | ONNX'i hızlandırıcı op kümesine indir, kapsama raporu | M0 |
| `python -m stalyanpu gen-header [--check] [--out path]` | `stalyanpu_isa.h` üret / güncelliğini denetle | M0 |
| `compile`, `eval`, `golden`, `check`, `sens` | Nicemleme, mAP, altın vektör, interp≡runner, duyarlılık | M1, M2 |

## Paket düzeni

```
stalyanpu/
  hwcfg.py            HwConfig: dizi geometrisi, tamponlar, saat, DDR bant genişliği, ek yük sabitleri; presetler
  perf/layers.py      YOLOv8s katman tablosu (yaml yapısından üretilir, ONNX gerekmez)
  perf/model.py       katman başına çevrim modeli (döşeme seçimi, MAC/DDR sınırı)
  perf/report.py      tablo ve özet
  frontend/onnx_import.py   ONNX yükleme, şekil çıkarımı, sabitler
  frontend/patterns.py      op kısıt denetimleri (Conv 1x1/3x3 s1/s2, MaxPool 5s1p2, Resize nearest x2, Concat/Split 32 hizası, SiLU deseni)
  frontend/lower.py         bölümleme (NPU/CPU kesimi), füzyon (Conv+SiLU, Conv+Add), görünüm op'ları
  frontend/graph.py         NpuGraph IR
  backend/isa.py            descriptor/CSR/blob tanımı (tek kaynak)
  backend/gen_header.py     C başlığı üretici
  refmodel/fixedpoint.py    requant (u16 çarpan, yarım yukarı), quantize_multiplier, SiLU LUT
tests/                      pytest (528 test)
```

## Nicemleme semantiği (M1'de uygulanacak, sabitlendi)

- Ağırlıklar int8 simetrik, çıkış kanalı başına ölçek (`absmax/127`).
- Aktivasyonlar int8 tensör başına asimetrik (`scale`, `zp ∈ [-128,127]`). Giriş sıfır
  noktası `-zp_in·Σw` ile int32 bias'a katlanır; dolgu `zp_in` ile yapılır; dizi düz
  `Σ int8·int8` hesaplar.
- Requant: `mult ∈ [2^15, 2^16)`, `shift ∈ [0,47]`, yarım yukarı yuvarlama, int8 doyurma
  (`refmodel/fixedpoint.py`, RTL bununla bit bit karşılaştırılır). Bağıl hassasiyet 2^-15.
- SiLU: katman başına 256 girişli int8→int8 tablo; ön-aktivasyon tensörünün kendi ölçeği
  ayrıca kalibre edilir.
- Concat/Add/Split/MaxPool/Upsample kenarlarında ölçek birleştirme (union-find, aralık
  birleşimi); "kabalaşma katsayısı" > 4 raporlanır. Residual Add için iki çarpanlı yol
  descriptor'da hazırdır (`res_mult_a/b`).
- Kalibrasyon: 256 COCO val görüntüsü, letterbox 640×384 (gri 114), aktivasyonlar
  yüzdelik 99,99 (head çıkışları MSE), histogram 2048 kutu.
- Kesim: altı head 1×1 conv çıkışı (3 ölçek × {box 64, cls 80}). DFL, decode, sigmoid, NMS
  CPU'da (`refmodel/tail.py` ve C ikizi).

## Performans modeli

Katman başına:

```
n_pass   = ceil(IC/n_ic) · k²          n_oct = ceil(OC/n_oc)
cyc_mac  = Σ_t n_oct · n_pass · (P_t + t_pass)
cyc_tile = n_tiles · t_tile + ilk döşemenin açık ibuf dolumu
cyc_ddr  = (giriş + ağırlık·n_tiles + residual + çıkış baytı) / (bant genişliği / saat)
cycles   = max(cyc_mac + cyc_tile, cyc_ddr) + t_op
```

Döşeme: tam çıkış satırları, `P_t ≤ p_max` ve giriş ayak izi (halo dahil) ≤ ibuf/2.
Varsayılanlar `hwcfg.py`'de (t_pass 40, t_tile 150, t_op 500, DDR 2,4 GB/s). Model M6'da
sim çevrimleriyle, M8'de donanım sayaçlarıyla kalibre edilir. Sonuçlar için
[architecture.md](architecture.md) "Performans" bölümü.
