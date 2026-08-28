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
| U2 | `tb_pe_chain` | `snpu_skew` ×2 + `snpu_pe_chain` (32) | 32'lik nokta çarpım kuyruğu, gecikme `CHAIN_LEN+2`, akış sırasında shadow doldurma + latch, geçiş sınırı vektörü, uç ağırlıklar | PASS |
| U2b | `tb_pe_chain_16` | aynı, `CHAIN_LEN=16` | parametrelendirme | PASS |
| U3..U8 | epilog, LUT, rd/wr DMA, maxpool5, sequencer | | M3/M4 | |
| L1..L8 | `tb_npu_layer`: 1×1, 3×3 s1, 3×3 s2, stem, residual, concat ofseti, upsample, maxpool5 | `snpu_top` + AXI bellek modeli | `interp.py` altınıyla bit bit, çevrim ±%15 model | M4 |
| N1/N2 | YOLOv8s katman-katman / tam ağ | | %100 PASS | M6 |

Mutasyon denetimi (M0): `snpu_dsp_mac2` içinde iki ağırlık lane'i yer değiştirilince
`tb_pe_chain` ilk vektörde FAIL verir; TB'nin gerçekten karşılaştırdığı doğrulandı.

## Koşum

```
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit -j 3
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py tb_pe_chain --seed 7 --dump
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit --behav
```

Süre (M0, host): U1 1,1 s, U2 4,8 s, U2b 1,7 s vendor modeliyle. Tam kare (≈7,6 M
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
