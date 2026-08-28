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
| `python -m stalyanpu export [--weights yolov8s.pt] [--out x.onnx] [--height 384 --width 640] [--opset 13]` | ultralytics ile ONNX dışa aktarma (`[export]` ekstrası) | M1 |
| `python -m stalyanpu calibrate model.onnx --images val2017/ --ann instances_val2017.json --out build/q [--ncalib 256] [--method mse\|minmax\|percentile] [--percentile 99.99] [--outputs-method minmax] [--seed 0]` | Lowering + kalibrasyon + nicemleme; `qgraph.json/npz` ve `calib_stats.json` yazar | M1 |
| `python -m stalyanpu eval --qgraph build/q --images val2017/ --ann ... [--n 500] [--seed 1] [--report r.json]` | Aynı numpy tail ile FP32 (onnxruntime) ve INT8 (referans model) mAP | M1 |
| `python -m stalyanpu check-tail model.onnx image.jpg` | numpy DFL/decode çıktısını ONNX head çıktısıyla karşılaştırır | M1 |
| `compile`, `golden`, `check`, `sens` | Blob emitter, altın vektör, interp≡runner, duyarlılık | M2 |

Veri: `.data/` (gitignore) altında `yolov8s.pt`, `yolov8s_640x384.onnx`, `coco/annotations/instances_val2017.json`
ve `coco/val2017/` (yalnız kullanılan 739 görüntü: kalibrasyon seed 0 ilk 256, değerlendirme seed 1 ilk 500;
`eval/coco.py:image_list` deterministik). Görüntüler `coco_url` alanından tek tek indirilebilir,
tam zip gerekmez.

## Referans model (`refmodel/`)

- `intops.py`: int8 conv (im2col × float64 matmul, 2^53 altında tam; 4608×2^14 en kötü durum), OC başına
  requant, LUT, residual add (iki yeniden ölçek yolu), maxpool5, upsample2, concat/split.
- `runner.py`: `QRunner` nicemlenmiş grafiği CHW int8 tensörlerle yürütür (`keep_all` ile tüm ara
  tensörler, altın vektörler için). YOLOv8s 640×384 bir kare ≈ 0,75 s.
- `tail.py`: anchor üretimi, DFL softmax-beklenti, decode, sigmoid, sınıf-ofsetli NMS
  (conf 0,001, IoU 0,7, max 300). ONNX head çıktısıyla fark: kutu 1e-4 px, skor 2e-7.
- `quant/`: `calib.py` (ORT ile tüm gerekli tensörleri tek geçişte; min/max ve ortalama yüzdelik),
  `ranges.py` (union-find ölçek birleştirme, `range_to_qparams`), `params.py` (OC başına ağırlık
  ölçeği, zp katlanmış int32 bias, u16 mult/shift, SiLU LUT, residual parametreleri),
  `qgraph.py` (kaydet/yükle).

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
  refmodel/{intops,runner,tail}.py   bit-kesin op'lar, yürütücü, DFL/NMS kuyruğu
  quant/{calib,ranges,params,qgraph}.py  istatistik, aralık seçimi, tamsayı parametreler, kayıt
  eval/{preprocess,coco}.py  letterbox, COCO mAP
tests/                      pytest (539 test)
```

## Nicemleme semantiği (M1'de uygulandı)

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
- Kalibrasyon: 256 COCO val görüntüsü, letterbox 640×384 (gri 114). Aralık yöntemi
  **MSE araması** (varsayılan; ön-aktivasyon tensörlerinde hata SiLU sonrası ölçülür), min/max ve
  yüzdelik seçenekleri ölçüldü (bkz. accuracy-report.md). Ölçek birleştirme için grup aralığı üyelerin birleşimidir.
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
