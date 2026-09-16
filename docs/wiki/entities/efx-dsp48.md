---
title: "EFX_DSP48 (Titanium DSP48 DUAL bloğu)"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-16
source_count: 5
tags: [dsp48, efinix, titanium, mac, int8]
---

# EFX_DSP48 (Titanium DSP48 DUAL bloğu)

## Tanım
Efinix Titanium ailesinin sert DSP bloğu. [[ti375c529]]'da 1344 adet, 28 sütun × 48 blok
olarak dizilidir. [[stalyanpu]] dizisi bu bloğu `MODE="DUAL"` ile kullanır; bir blok iki
bağımsız INT8 çarpım-toplama yaptığından **DSP başına 2 MAC/çevrim** sağlar.

## Temel Bilgiler
**DUAL modu semantiği** (sim modeli `C:\Programs\Efinity\2025.2\sim_models\verilog\efx_dsp48.v`,
U1/U2 testbench'leriyle doğrulanmış): yüksek lane `A[18:8]×B[17:8]` (11×10), düşük lane
`A[7:0]×B[7:0]` (8×8); çarpımlar 24-bit lane'lere işaret genişletilir; toplayıcı iki bağımsız
24-bit, taşıma bit 24'te kesilir; `OVFL` iki lane'in VEYA'sı. 48-bit CASCIN/CASCOUT iki lane'i
birlikte taşır. `OP=2'b00` → `M + N`; `N_SEL` zincir başında `CONST0`, gövdede `CASCIN`;
`M_SEL="P"`; `CASCOUT_SEL="W"` kayıtlı toplayıcı çıkışını verir.

**StalyaNPU sarmalayıcısı** (`snpu_dsp_mac2.v`): `A={sext11(x), x}`, `B={sext10(w_hi), w_lo}`,
`A_REG=B_REG=P_REG=W_REG=1`, `O_REG=LAST`, `W_SEL="X"`, `SIGNED=1`, `RST_SYNC=1`; yalnız
`B_REG_USE_CE=1`, böylece `CE` ağırlık latch'i olur. Gecikme: x örneklenen kenar s →
`casc_o` s+2, `o` s+3. `SNPU_SIM_BEHAV` ile davranışsal ikiz vardır; nihai kanıt vendor
modeliyledir. DSP içinde birikim yapılmaz: 32 çarpım ≤ 2^19 olduğundan 24-bit lane taşmaz.

**Sütun kısıtı.** CASCIN/CASCOUT zinciri sütun dışına çıkamaz; 32 uzunluklu kaskaddan en
fazla 28 tane yerleşir. Bu yüzden zincirler `CASC_LEN=8` ile dört fiziksel kaskada bölünür ve
SRL hizalama + kayıtlı toplama ağacıyla birleşir ([[dsp-chain-systolic-array]],
[[fpga-timing-closure]]).

**Bütçe.** Dizi 1024, epilog 128 (kanal başına 2 requant + 2 residual), seq/rd_dma/agen
çarpımları; `snpu_top` tek başına 1186, tam tasarım 1217 DSP48 (%88-90). Emniyet supapları:
residual çarpanlarını LUT'a almak, requant'ı yarı hıza düşürmek. OpenEye tasarımı yalnızca
152 DSP kullanıyordu ([[dnn-accelerator-options]]). İlk supap 2026-09-16'da uygulandı: residual
çarpımları lane başına iki tabloya alındı, sequencer, okuma DMA ve adres üreteci çarpımları
paylaştırıldı; dizi dışı maliyet 174'ten 74 DSP48'e, `snpu_top` 32×32 1198'den 1098'e indi
([[stalyanpu-dsp-overhead-sharing]]).

**Risk.** Silikon davranışının sim modelinden farklı olması (R1) listede ilk sıradaydı; M8'de
tam kare bit bit eşleşmesi bu riski fiilen kapatmıştır ([[board-bringup-flow]]).

## Kaynaklarda Geçişi
- [[stalyanpu-readme]]: DSP kaskadının sütun başına 48 blokla sınırlı olduğu notu
- [[stalyanpu-architecture]]: sarmalayıcı parametreleri, zincir ve gecikme
- [[stalyanpu-decision-record]]: DUAL modu = DSP başına 2 INT8 MAC, cihaz tavanı 1344 DSP
- [[stalyanpu-synthesis-guide]]: 28 sütun × 48 blok, yerleşim deneyleri, DSP dağılımı
- [[stalyanpu-verification-guide]]: doğrulanan DUAL semantiği, U1/U2 testleri

## İlişkiler
- [[stalyanpu]]: bloğu 1024 adet kullanan hızlandırıcı
- [[ti375c529]]: bloğu barındıran cihaz
- [[efinity-toolchain]]: sim modeli ve yerleşim aracı
- [[dsp-chain-systolic-array]]: bloğun dizi içindeki rolü
- [[fpga-timing-closure]]: kaskat bölme ve yerleşim etkisi
