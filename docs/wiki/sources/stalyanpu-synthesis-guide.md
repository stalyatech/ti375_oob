---
title: "Kaynak: StalyaNPU Sentez Rehberi (M5, M7, M8, M9 zamanlama)"
type: source
source_file: "ip/stalyanpu/docs/synthesis-guide.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, synthesis, efinity, timing, dsp48, integration]
---

# Kaynak: StalyaNPU Sentez Rehberi (M5, M7, M8, M9 zamanlama)

## Özet
[[stalyanpu]]'nun [[efinity-toolchain]] 2025.2 ile tek başına sentezini (M5), `ti375_oob`
projesine entegrasyonunu (M7), M8'de görülen zamanlama davranışını ve M9'daki iki kapanış
adımını (yapısal düzeltmeler, sonra dedicated DDR portu build'i) anlatır. Üç bağımsız Efinity
projesi (`chain`, `conv`, `top`), kaydırma yazmacı tabanlı sarmalayıcı yöntemi, Ti375 DSP
sütun kısıtı, RAM çıkarımı ve boru bölme düzeltmeleri, M7 bağlantı tablosu ve kaynak
tabloları belgede yer alır. Son durum: tam tasarım seed 6 ile `io_ddrMasters_0_clk`
**+0,038 ns**, peri +0,240 ns, board 43,9 fps.

## Temel Çıkarımlar
- Ti375'te 1344 DSP48 28 sütun × 48 blok; CASCIN/CASCOUT sütun dışına çıkamaz, 32'lik kaskaddan en fazla 28 yerleşir; çözüm `CASC_LEN=8` ile dört fiziksel kaskat ([[dsp-chain-systolic-array]]).
- M7: tam tasarım +0,005 ns (seed 1, effort 3), 1217 DSP48, 1478 RAM10. M8: slack build'den build'e −0,2..−0,6 ns oynadı, −0,58 ns'lik build board'da bozuk sonuç üretti.
- M9 yapısal kapanış: kayıtlı `rst_all` ve zincir başına reset kopyası, üç kademeli maxpool max ağacı → +0,013 ns (seed 3).
- Dedicated port build'i: LUT4 98,1k, FF 94,1k, DSP48 1223, RAM10 1606; kısıtsız seed taraması 4/5/6 pozitif; port pin kısıtları eklenince ihlaller çıktı, genişletici kayıtlı yapıldı, son +0,038 ns.
- Her build board'da CRC ve iki koşumda aynı sonuçla doğrulanır; kural değişmedi.

## Detaylı Notlar
**Sarmalayıcı yöntemi ve koşum.** Modül portları binlerce bit olduğundan her sarmalayıcı dört
pin kullanır (`clk_in` 125 MHz, `rst_i`, `sin`, `sout`): girişler kaydırma yazmacından sürülür,
çıkışlar kayıtlı xor ağacıyla katlanır, eşleyici tasarımı budayamaz. PLL_BL2 ile 250 MHz.
`run_syn.py <proje> --flow map|pnr|all|none`.

**DSP sütun kısıtı.** Deneyler: 24 × 32 (768) 269 MHz; 28 × 32 (896) 263 MHz; 30 × 32, 32 × 32
ve 64 × 16 placer iç hatası; 24 × 43 (1032) 256 MHz; 128 × 8 (1024) 258 MHz. Bölünmüş zincir
gecikmesi `CHAIN_LEN+2+log2(CHAIN_LEN/CASC_LEN)`; maliyet 4,6k EFX_ADD, 9,9k SRL8
([[efx-dsp48]], [[ti375c529]]).

**RAM çıkarımı ve boru düzeltmeleri (M5).** Epilog parametre/LUT tabloları `snpu_ep_lane` ile
RAM10'a; maxpool satır tamponu tek RAM'e; residual ve requant yolları üç dört aşamaya; adres
üretecine iki aşamalı boru; biriktirici RMW bölündü (döşeme ≥ 4 piksel); sequencer ve rd_dma
çarpımları kayıtlı veya artımlı; geniş yazmaçlardan reset kaldırıldı (`min-sr-fanout` 64).
Motor 149 → 195 → 225 → 256 MHz. Bu liste [[fpga-timing-closure]] kavramının M5 kısmıdır.

**M7 entegrasyonu.** Veri düzlemi `snpu_top` `gAXIM_5to1_switch` `MDNN=3` yuvasında, 128-bit
([[axi-interconnect-topology]]); anahtar AXI ID taşımadığından `snpu_rd_dma` yanıtları
ihraç sırasıyla eşler. Tablo CSR'ı yumuşak SoC ([[efx-sapphire-fcu]]) `sp_apbSlave_0`
üst yarısında (`0xF810_4000`, `snpu_apb_cdc.v` köprüsü, alt yarı [[gdma]]) gösterir ve sert
SoC `io_apbSlave_0`'ı sürücüsüz sayar. Bu tablo M7 hâlini anlatır ve M8 sonrası
güncellenmemiştir: HEAD'de CSR sert SoC ([[efx-sapphire-hpsoc-slb]]) AXI-A üzerinden
`0xE810_4000`'dedir ([[stalyanpu-bringup-guide]], [[accelerator-control-plane-apb]]).
Kapanış dört ek düzeltme ve seed/effort taraması istedi (−0,162 → +0,005). Sonuç LUT4 92,4k,
FF 85,7k, DSP 1217, RAM10 1478.

**M8 zamanlama notları.** Kapatılan yollar: maxpool satır sınırı karşılaştırmaları, epilog
çıkış zp toplamı, wfifo'dan 32 zincire ağırlık dağıtımı, epilog `adv` residual bayrağı
kopyası. Kalan en kötü yol −0,35 ns yazma DMA birleştiricisi eşlemesi. Negatif slack bu
cihazda gerçekten kırılıyor; board doğrulaması her build için zorunlu ([[board-bringup-flow]]).

**M9 zamanlama kapanışı (2026-09-15).** İki yapısal düzeltme: `snpu_top` içinde `rst_all`
kayıtlı ve `snpu_pe_array` her zincire kendi kayıtlı reset kopyasını verir (`rst_c`),
`soft_rst → DSP RST` yolu (−0,35) ikiye bölünür; maxpool 5 girişli max ağacı üç kademe
(`m01/m23 → m03 → çıkış`), yalnız beşinci satır okuması boruyu bekler (`tb_layer_demo3`
30,3 k → 26,7 k çevrim). Tam tasarım +0,013 ns, seed 3 effort 3. Board 28,1 fps.

**Dedicated DDR portu build'i (2026-09-15).** NPU `AXI_DW=256` + [[snpu-axi-up512]] +
`axi_target0` (512-bit): paylaşımlı build'e göre +5,7k LUT, +8k FF (genişletici kuyrukları,
A2 tabloları, 512-bit veri yolu). Kısıtsız seed taraması (effort 3, aynı map netlist'i):
seed 1 −0,040, 2 −0,007, 3 −0,110, 4 +0,087, 5 +0,017, 6 +0,088; proje seed 6. Bu tarama
`npu_ddr_*` pinleri kısıtsızken yapıldı; pin kısıtları eklenince `npu_ddr_rready` −1,58 ns,
ardından `arlen`, `arready`, `wready`, `arstn` çıktı ([[ddr-port-pin-constraints]]).
Genişletici port yönünde tamamen kayıtlı yapıldı, `arstn` false path. Son build (seed 6,
kısıtlı) +0,038 ns, peri +0,240, board 43,9 fps ALL PASS, iki koşum aynı CRC.

**Kaynak durumu.** 2026-09-02 tablosu: `snpu_top` tek başına LUT4 45,7k, FF 44,8k, DSP 1186,
RAM10 1149; cihaz payları DSP %88, RAM10 %43, XLR %25. Döşeme çift tamponu sonrası `snpu_top`:
LUT4 48,8k, RAM10 1269 (+26 üçüncü beat FIFO'su), 233 MHz (−0,29 ns). Belgenin 2026-09-02
"Zamanlama durumu" bölümündeki 244 MHz / −0,105 ns değeri ile M9 bölümlerindeki pozitif
slack yan yanadır; sonuncusu geçerlidir. Tam tasarım DSP 1217 (M7) → 1223 (M9), RAM10
1478 → 1606.

> ❓ **Belirsiz:** Başlık hâlâ "(M5)" ve "Kaynak durumu" tablosu 2026-09-02 tarihlidir;
> dedicated port build'i için blok başına dağılım (yalnız toplamlar) verilmemiştir.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[efx-dsp48]], [[efinity-toolchain]], [[ti375c529]], [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[gdma]], [[snpu-axi-up512]], [[lpddr4x-controller]]
- İlgili kavramlar: [[fpga-timing-closure]], [[dsp-chain-systolic-array]], [[board-bringup-flow]], [[axi-interconnect-topology]], [[accelerator-control-plane-apb]], [[ddr-port-pin-constraints]], [[dual-soc-architecture]]
- Destekleyen kaynaklar: [[stalyanpu-architecture]], [[stalyanpu-readme]], [[stalyanpu-bringup-guide]], [[stalyanpu-perf-plan]]

## Alıntılar
- "Yani 32 uzunluklu kaskadlardan en fazla 28 tane yerleşir (sütun başına bir). Çözüm: `snpu_pe_chain` zinciri `CASC_LEN=8` ile dört fiziksel kaskada böler" (satır 68-69)
- "Son build (seed 6, kısıtlı): `io_ddrMasters_0_clk` +0,038 ns, peri +0,240 ns, board 43,9 fps ALL PASS, iki koşum aynı CRC." (satır 203-205)
