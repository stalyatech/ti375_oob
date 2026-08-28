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
| L1 | `tb_conv_conv1x1` | `snpu_conv_unit` (small512: 16×16, 512 MAC) | 1×1, 32→32, 2 IC grubu | PASS |
| L2 | `tb_conv_conv3x3` | aynı | 3×3, 32→64 (2 OC döşemesi), SiLU | PASS |
| L3 | `tb_conv_conv3x3s2` | aynı | 3×3 stride 2, 64→32, SiLU | PASS |
| L4 | `tb_conv_conv_res` | aynı | 3×3, SiLU + residual akışı | PASS |
| L5 | `tb_conv_conv_pad80` | aynı | 1×1, 48→80 (3 plane, dolgu kanalları) | PASS |
| L6 | `tb_conv_conv_tiles` | aynı | 3×3, 6 döşeme (tile_rows=2) | PASS |
| L7 | `tb_conv_full` | tam geometri 32×32 (1024 DSP) | 3×3, 40→96, SiLU | PASS |
| U3..U8 | rd/wr DMA, maxpool5, sequencer, AXI bellek modeli | | M4 | |
| N1/N2 | `tb_npu_layer`/`tb_npu_net`: descriptor tabanlı, `interp.py` altınıyla | `snpu_top` | bit bit, çevrim ±%15 | M4/M6 |

Katman testleri (`group=layer`) vektörlerini `stalyanpu.golden.unit` üretir (`tests.py` `gen`
kancası; `sim/stalyanpu/stim/<case>/` altında `cfg/ibuf/w/prm/lut/res/golden.hex`). Ağırlık,
residual ve çıkış akışlarında rastgele boşluk/durak (`+BACKPRESSURE=1`); etiketler (tile, plane,
px) yayın sırasıyla karşılaştırılır. `+DEBUG=1..4` iç izler, `+WATCHDOG=n` bekçi süresi.

Mutasyon denetimi (M0): `snpu_dsp_mac2` içinde iki ağırlık lane'i yer değiştirilince
`tb_pe_chain` ilk vektörde FAIL verir; TB'nin gerçekten karşılaştırdığı doğrulandı.

## Koşum

```
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit -j 3
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py tb_pe_chain --seed 7 --dump
.venv-stalyanpu\Scripts\python sim/stalyanpu/run_sim.py unit --behav
```

Süre (host, vendor modeli): U1 1,1 s, U2 4,8 s, U2b 1,7 s; L1..L6 4 ile 40 s arası; L7 (1024 DSP,
2304 ağırlık sözcüğü) ≈ 100 s. Tam kare (≈7,6 M
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
