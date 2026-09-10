# StalyaNPU doğrulama

Simülatör: Icarus Verilog 12 (`C:\Program Files\iverilog`), `-g2012`. Verilator host'ta
yok; kurulursa `run_sim.py --sim verilator` eklenir (TB'ler her iki aracın kabul ettiği SV
alt kümesiyle yazılır). Efinix DSP48 modeli
`C:\Programs\Efinity\2025.2\sim_models\verilog\efx_dsp48.v` doğrudan derlenir
(`SNPU_DSP_MODEL` ortam değişkeniyle yol değiştirilebilir).

## Ağaç

```
sim/stalyanpu/
  run_sim.py        koşucu: run_sim.py all|unit|<test> [--seed N] [--behav] [--dump] [-j N] [--plusargs +X=..]
  tests.py          test kaydı: top, dosya listesi, parametre override, needs_dsp_model
  common/tb_util.svh   TB_CHECK, TB_FINISH, TB_WATCHDOG makroları
  common/lfsr16.sv     backpressure için LFSR (sim/openeye ile aynı taps, 16'hACE1)
  unit/             birim TB'ler
  stim/unit/        küçük, commit edilen vektörler; stim/ altındaki diğerleri gitignore
  sim_build/        derleme çıktıları ve loglar (gitignore)
```

PASS ölçütü: log'da tam bir `<top>: PASS` satırı, hiç `FAIL` satırı yok, vvp çıkış kodu 0.
`run_sim.py` çıkış kodu = başarısız test sayısı. `--behav`, `-DSNPU_SIM_BEHAV` ile RTL'deki
davranışsal DSP ikizini seçer (vendor modelsiz, hızlı); nihai kanıt vendor modeliyledir.

## Test listesi

| # | Test | DUT | Kontrol | Durum |
|---|------|-----|---------|-------|
| U1 | `tb_dsp_mac` | `snpu_dsp_mac2` FIRST/LAST ve gövde örnekleri | Her çevrim `$signed` çarpım + kaskad toplamı ile karşılaştırma; her iki lane; CE ile ağırlık latch'i; 24-bit sarma ve OVFL; uç değerler (-128·-128 vb.); reset ortasında; 20k rastgele çevrim | PASS (vendor + behav) |
| U2 | `tb_pe_chain` | `snpu_skew` ×2 + `snpu_pe_chain` (32) | 32'lik nokta çarpım kuyruğu, gecikme `CHAIN_LEN+2+log2(CHAIN_LEN/CASC_LEN)`, akış sırasında shadow doldurma + latch, geçiş sınırı vektörü, uç ağırlıklar | PASS |
| U2b | `tb_pe_chain_16` | aynı, `CHAIN_LEN=16` | parametrelendirme | PASS |
| L1 | `tb_conv_conv1x1` | `snpu_conv_unit` (small512: 16×16, 512 MAC) | 1×1, 32→32, 2 IC grubu | PASS |
| L2 | `tb_conv_conv3x3` | aynı | 3×3, 32→64 (2 OC döşemesi), SiLU | PASS |
| L3 | `tb_conv_conv3x3s2` | aynı | 3×3 stride 2, 64→32, SiLU | PASS |
| L4 | `tb_conv_conv_res` | aynı | 3×3, SiLU + residual akışı | PASS |
| L5 | `tb_conv_conv_pad80` | aynı | 1×1, 48→80 (3 plane, dolgu kanalları) | PASS |
| L6 | `tb_conv_conv_tiles` | aynı | 3×3, 6 döşeme (tile_rows=2) | PASS |
| L7 | `tb_conv_full` | tam geometri 32×32 (1024 DSP) | 3×3, 40→96, SiLU | PASS |
| N1 | `tb_layer_demo0/1/3` | `snpu_top` + `axi4_mem_model` (small512) | Demo ağının tek descriptor'ı: stem (3 döşeme), residual conv (split kaynak), maxpool5 (upsample görünüm); descriptor CRC, param/LUT yükleme, DMA, yazma adresleri; `interp.py` altınıyla bölge karşılaştırması | PASS |
| N2 | `tb_net_demo` | aynı | Demo ağının 5 descriptor'ı zincirleme, descriptor başına dump bölgeleri dahil 6 bölge bit bit | PASS |
| Y1 | `tb_yolo_l0` .. `tb_yolo_l65` (`group=yolo`, `all` dışı, `.data/build/q_mse` ister) | tam geometri 32×32, 16/32 MB pencereler | Derlenmiş YOLOv8s'in 66 descriptor'ının her biri tek başına, gerçek ağırlık ve gerçek girişle; üreteç yorumlayıcıyı k. descriptor'a kadar koşturur ve descriptor'ı ilk 2 döşemeye kırpar (`--max-tiles`); bellek imajı yalnız okunan sayfaları içerir, tezgah `mem0/mem1.hex` varsa `$readmemh` ile yükler; 66 test tek `yolo_layer` vvp derlemesini paylaşır | **66/66 PASS** (behav ikiz); vendor modeliyle alt küme l0/l4/l26/l30/l65 **5/5 PASS** |
| Y2 | `tb_yolo_net` (`group=yolo_net`) | tam geometri | 66 descriptor'lık listeyi sequencer uçtan uca yürütür (tam 640×384, kırpma yok), 6 head çıkışı karşılaştırılır | koşum ~4-6 saat (behav) |

Katman testleri (`group=layer`) vektörlerini `stalyanpu.golden.unit` üretir (`tests.py` `gen`
kancası; `sim/stalyanpu/stim/<case>/` altında `cfg/ibuf/w/prm/lut/res/golden.hex`). Ağırlık,
residual ve çıkış akışlarında rastgele boşluk/durak (`+BACKPRESSURE=1`); etiketler (tile, plane,
px) yayın sırasıyla karşılaştırılır. `+DEBUG=1..4` iç izler, `+WATCHDOG=n` bekçi süresi.

Descriptor testleri (`group=net`) vektörlerini `stalyanpu.golden.demo` (demo ağı, small512) ve
`python -m stalyanpu golden` (YOLOv8s) üretir: `mem.hex` (blob + giriş), `golden.hex`,
`regions.txt` (base bayt), `run.txt` (`+DESC_BASE/+DESC_COUNT`). `tb_npu_net` belleği
`$fgets/$sscanf` ile iki pencereye (blob, scratch) yükler, APB ile CSR programlar,
`done`/`error` kesmesini bekler ve bölgeleri bayt bayt karşılaştırır. `+BP=0` AXI duraklarını
kapatır, `+DEBUG=1..5` sequencer/bank/DMA izleri, `+DUMP_REGION=<dosya>` üretilen bölgeleri döker.

Mutasyon denetimi (M0): `snpu_dsp_mac2` içinde iki ağırlık lane'i yer değiştirilince
`tb_pe_chain` ilk vektörde FAIL verir; TB'nin gerçekten karşılaştırdığı doğrulandı.

### Kırpılmış katman koşumları

Tam 640×384 geometride bir katmanın simülasyonu saatler sürer (vendor DSP
modeliyle ~80 çevrim/s). Bu yüzden katman testleri descriptor'ı ilk iki
döşemeye kırpar: out_h ve in_h kırpılır (stride 2'de in = 2*out-1), n_tiles
ve out_plane_stride yeniden yazılır, CRC güncellenir. Yorumlayıcı ve RTL
aynı kırpılmış descriptor'ı yürüttüğü için karşılaştırma bit kesindir;
gerçek ağırlıklar, gerçek giriş satırları ve gerçek kanal genişlikleri
korunur. Tarama davranışsal DSP ikiziyle koşulur (~4x hız); vendor modeli
temsilci bir alt kümede (stem, residual, maxpool, upsample+concat, head)
ayrıca koşturulur. Kırpılmış geometri `golden.json` içindeki `run_dims`
alanına yazılır ve perf_compare model kestirimini o boyutlarla yapar.

## Performans karşılaştırması (M6)

`sim/stalyanpu/perf_compare.py`, yolo katman loglarındaki `CYCLE_CNT`
değerlerini performans modelinin katman kestirimleriyle karşılaştırır ve
sapma tablosu basar. Sonuç (66 katman, kırpılmış koşular,
`perf_compare_m6.txt`): ölçüm iki analitik sınırın arasında kalır. Tümü
ardışık modelde RTL %17,9 hızlı, yalnız giriş dolgusu ardışık modelde
%17,6 yavaş çıkar; gerçek makine ilk gölge dolumlarını ve paylaşılan AXI
portunu kısmen serileştirdiği için ikisinin ortasındadır. Kırpılmış
koşular DDR payını abarttığından bu bant tam kare için üst sınırdır; tam
karede MAC baskındır ve fps projeksiyonu M0 modelinden gelir. Tekil küçük
katmanlarda sabit ek yükler (CRC, param/LUT yüklemesi) yüzdeyi büyütür,
değerlendirme toplam üzerinden yapılır.

## Koşum

```
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit -j 3
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py tb_pe_chain --seed 7 --dump
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit --behav
```

Süre (host, vendor modeli): U1 1,1 s, U2 4,8 s, U2b 1,7 s; L1..L6 4 ile 40 s arası; L7 (1024 DSP,
2304 ağırlık sözcüğü) ≈ 100 s; N1 90 ile 120 s; N2 (5 descriptor, 215 k çevrim) ≈ 400 s. Tam kare (≈7,6 M
çevrim, 1024 DSP) için iverilog saatler sürecektir; katman-katman paralel koşum ve
`small256` geometrisi asıl kaldıraçtır (M4'te ölçülür).

## DSP48 DUAL modu: doğrulanan davranış

`efx_dsp48.v` modelinden okunan ve U1/U2 ile sınanan semantik:

- `MODE="DUAL"`: yüksek lane `A[18:8]×B[17:8]` (11×10), düşük lane `A[7:0]×B[7:0]` (8×8);
  çarpımlar 24-bit lane'lere işaret genişletilir; toplayıcı iki bağımsız 24-bit
  (`EFX_DSP48_add_sub #(.W(24))`), taşıma bit 24'te kesilir; `OVFL` iki lane'in VEYA'sı.
- `OP=2'b00` → `M + N`; `N_SEL="CONST0"` (zincir başı) veya `"CASCIN"`; `M_SEL="P"`.
- `CASCOUT_SEL="W"` kayıtlı toplayıcı çıkışını verir; 48-bit kaskad iki lane'i birlikte taşır.
- `B_REG_USE_CE=1`, diğer kademeler CE'yi yok sayar: `CE` = ağırlık latch'i.
- Gecikme: x örneklenen kenar s → `casc_o` s+2 sonrası, `o` (O_REG) s+3 sonrası.
  Zincir: s + CHAIN_LEN + 2.

Silikon davranışı sim modelinden farklı olabilir (risk R1): M5 öncesi tek zincirli board
smoke testi planlıdır.
