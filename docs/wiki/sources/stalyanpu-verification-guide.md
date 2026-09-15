---
title: "Kaynak: StalyaNPU Doğrulama"
type: source
source_file: "ip/stalyanpu/docs/verification-guide.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, verification, simulation, iverilog, testbench, dsp48]
---

# Kaynak: StalyaNPU Doğrulama

## Özet
[[stalyanpu]] RTL'inin simülasyon tabanlı doğrulamasını anlatır: Icarus Verilog 12
(`-g2012`) ile derlenen `sim/` ağacı, `run_sim.py` koşucusu, PASS ölçütü, birim (U), katman
(L), ağ (N) ve YOLOv8s (Y) test listesi, kırpılmış katman koşumu yöntemi, M9 döşeme çift
tamponu sim sonuçları, M6 performans karşılaştırması ve `efx_dsp48.v` modelinden doğrulanan
DSP48 DUAL semantiği. Bugünkü sürüm üç yeni birim testi (`tb_wr_dma`, `tb_rd_dma`,
`tb_axi_up512`) ve ağ testlerine eklenen örtüşme denetimini (`+EXPECT_OVERLAP`) içerir.
Nihai kanıt vendor DSP modeliyledir; `--behav` davranışsal ikizi hız için kullanılır.

## Temel Çıkarımlar
- Vendor modeli `C:\Programs\Efinity\2025.2\sim_models\verilog\efx_dsp48.v` doğrudan derlenir; davranışsal ikiz `SNPU_SIM_BEHAV` ile seçilir ([[efx-dsp48]]).
- Kademeler: U1..U5 (DSP, zincir, yazma DMA, okuma DMA, genişletici), L1..L7 (`snpu_conv_unit`), N1/N2 (`snpu_top` + AXI bellek modeli), Y1 (66 descriptor tek tek), Y2 (tam ağ, 4-6 saat).
- Y1 66/66 PASS (behav); vendor modeliyle alt küme l0/l4/l26/l30/l65 5/5 PASS, yeni sequencer ile de bit bit.
- M9 çift tampon: `tb_net_demo` 120 512 → 106 495, tam geometri demo 94 919 → 89 968 çevrim; çıkış bölgeleri değişmedi.
- Yeni `tb_axi_up512`: 300 rastgele yazma + 300 okuma burst'ü, sonra eş zamanlı trafik; yazılımdaki bellek kopyasıyla kelime kelime; 3 tohum PASS.

## Detaylı Notlar
**Ağaç ve koşucu.** `run_sim.py all|unit|<test> [--seed N] [--behav] [--dump] [-j N]`;
`tests.py` test kaydı (top, dosya listesi, parametre override, `needs_dsp_model`);
`common/tb_util.svh` makroları; `common/lfsr16.sv` backpressure LFSR'ı. PASS ölçütü: log'da
tam bir `<top>: PASS` satırı, hiç `FAIL` yok, vvp çıkış kodu 0. Yapı
[[file-driven-directed-testbench]] kavramının StalyaNPU uygulamasıdır.

**Birim testleri.** U1 `tb_dsp_mac`: her çevrim `$signed` çarpım + kaskad toplamı, iki lane,
CE ile latch, 24-bit sarma ve OVFL, 20k rastgele çevrim. U2 `tb_pe_chain`: 32'lik nokta
çarpım, gecikme `CHAIN_LEN+2+log2(CHAIN_LEN/CASC_LEN)`, akış sırasında shadow dolumu; U2b
`CHAIN_LEN=16` ([[dsp-chain-systolic-array]]). U3 `tb_wr_dma`: burst birleştirme, seyrek
girişte 8 sözcüğe dolma, beat adresleri. U4 `tb_rd_dma`: üç kanalda eş zamanlı rastgele üç
seviyeli komutlar, 4 KB sınırı geçen parçalar, burst bölme; her sözcük öngörülen adres,
`last` ve `dst` ile karşılaştırılır. U5 `tb_axi_up512`: [[snpu-axi-up512]] + 512-bit
`axi4_mem_model`; 1..64 kelimelik burst'ler, rastgele başlangıç şeridi, boşluk ve durak.
Mutasyon denetimi (M0): iki ağırlık lane'i yer değiştirilince TB ilk vektörde FAIL verir.

**Katman ve ağ testleri.** L1..L6 `small512` (16×16, 512 MAC) geometrisinde 1×1, 3×3, stride
2, residual, dolgu kanalları, 6 döşeme; L7 tam geometri 3×3 40→96 SiLU. N1 demo ağının tek
descriptor'ları; M9'dan itibaren tezgah dolum/koşum örtüşme çevrimlerini sayar
(`+EXPECT_OVERLAP=1` ile > 0 şartı) ve her ibuf yazımının dolum yarısında kaldığını denetler.
N2 5 descriptor zincirleme, 6 bölge bit bit. Y1 `tb_yolo_l0..l65` gerçek ağırlık ve girişle,
tek `yolo_layer` vvp derlemesi; Y2 `tb_yolo_net` 66 descriptor'ı uçtan uca yürütür. Vektörler
`stalyanpu.golden.*` ve `python -m stalyanpu golden` ile üretilir ([[stalyanpu-toolchain]]);
`tb_npu_net` belleği iki pencereye yükler, APB ile CSR programlar ([[descriptor-isa]]),
kesmeyi bekler, bölgeleri bayt bayt karşılaştırır.

**Kırpılmış katman koşumları.** Tam 640×384'te bir katman saatler sürer (vendor modeliyle
~80 çevrim/s). Descriptor ilk iki döşemeye kırpılır (`--max-tiles`), CRC güncellenir;
yorumlayıcı ve RTL aynı kırpılmış descriptor'ı yürüttüğünden karşılaştırma bit kesindir.
Kırpılmış geometri `golden.json` `run_dims` alanına yazılır.

**M9 çift tampon sonucu.** Aynı vektörler, eski ve yeni sequencer (small512, vendor modeli,
`+BP=1`):

| Test | Eski | Yeni | Açıkta dolum | Örtüşme |
|------|-----:|-----:|-------------:|--------:|
| `tb_layer_demo0` (stem, 3 döşeme) | 18 250 | 15 274 | 2 133 | 4 354 |
| `tb_layer_demo1` (residual) | 14 167 | 13 539 | 691 | 1 383 |
| `tb_layer_demo3` (maxpool5) | 30 307 | 30 307 | 0 | 0 |
| `tb_net_demo` (5 descriptor) | 120 512 | 106 495 | 5 916 | 19 750 |
| `tb_net_demo_full` (32×32) | 94 919 | 89 968 | 14 544 | 5 509 |

YOLOv8s kırpılmış descriptor'ları yeni sequencer ile: l0 33 745 çevrim (açıkta 9 023, örtüşme
10 461), l4 27 515, l26 16 989 (tek döşeme), l30 82 159, l65 6 831; 5/5 bit bit. Kazanç yalnız
zamanlamadan gelir. Board karşılığı [[stalyanpu-bringup-guide]] tablosundadır (24,6 → 28,1 fps).

**Performans karşılaştırması (M6).** `sim/perf_compare.py` yolo katman loglarındaki
`CYCLE_CNT`'i [[analytic-performance-model]] kestirimleriyle karşılaştırır: tümü ardışık
modelde RTL %17,9 hızlı, yalnız giriş dolgusu ardışık modelde %17,6 yavaş; gerçek makine
ikisinin ortasında. Kırpılmış koşular DDR payını abarttığından bant tam kare için üst sınırdır.

**DSP48 semantiği.** DUAL modda yüksek lane `A[18:8]×B[17:8]` (11×10), düşük lane
`A[7:0]×B[7:0]`; iki bağımsız 24-bit toplayıcı, taşıma bit 24'te kesilir, `OVFL` iki lane'in
VEYA'sı; `CASCOUT_SEL="W"`, `B_REG_USE_CE=1`. Belge silikon farkı riskini (R1) ve tek zincir
smoke testini hâlâ plan olarak yazar; M8/M9 tam kare bit bit eşleşmeleri bu riski fiilen
kapatmıştır.

> ❓ **Belirsiz:** Belge M9 sonrası toplam test sayısını vermez (perf planı 17/17, günün
> sonunda 22/22 PASS); `tb_yolo_net` (Y2) için sonuç satırı yoktur, yalnız süre kestirimi.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[efx-dsp48]], [[stalyanpu-toolchain]], [[yolov8s]], [[snpu-axi-up512]], [[efinity-toolchain]]
- İlgili kavramlar: [[file-driven-directed-testbench]], [[dsp-chain-systolic-array]], [[descriptor-isa]], [[analytic-performance-model]]
- Destekleyen kaynaklar: [[stalyanpu-architecture]], [[stalyanpu-toolchain-guide]], [[stalyanpu-isa-descriptor]], [[stalyanpu-bringup-guide]], [[stalyanpu-perf-plan]]

## Alıntılar
- "PASS ölçütü: log'da tam bir `<top>: PASS` satırı, hiç `FAIL` satırı yok, vvp çıkış kodu 0. ... nihai kanıt vendor modeliyledir." (satır 22-24)
- "Çıkış bölgeleri her durumda bit bit aynı; kazanç yalnız zamanlamadan gelir." (satır 88)
