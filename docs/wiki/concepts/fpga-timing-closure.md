---
title: "FPGA Zamanlama Kapanışı (250 MHz)"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 4
tags: [timing, slack, efinity, placer, seed-sweep, 250mhz, m9]
---

# FPGA Zamanlama Kapanışı (250 MHz)

## Tanım
[[stalyanpu]]'nun `io_ddrMasters_0_clk` (250 MHz, 4,0 ns) saat alanında pozitif slack'e
ulaştırılması süreci. Dizi ve motor tek başına kapanmış, tam tasarım M7'de bir kez +0,005 ns
görmüş, M8'de build'ler arası -0,2 ile -0,6 ns arasında oynamıştı. M9'da (2026-09-15) reset
ağacı ve maxpool borusu düzeltmeleri, ardından dedicated DDR portu pin kısıtları ve kayıtlı
genişleticiyle tam tasarım **+0,038 ns** ile kapandı (seed 6, tüm saatler pozitif). Negatif
slack'in board'da gerçekten bozuk sonuç ürettiği gözlenmiştir; kural değişmedi, her build
board'da CRC ile doğrulanır.

## Detaylı Açıklama
**Kademeli hedefler.** M5 kapısı dizi + acc tek başına 250 MHz, ≥ 0,3 ns slack. Ölçülen:
dizi (32×32, `CASC_LEN=8`) 258 MHz, +0,125 ns; motor (`snpu_conv_unit`) 256 MHz, +0,101 ns
(ara adımlar 149 → 195 → 225 → 256 MHz); tam `snpu_top` tek başına 139 MHz'den 244 MHz'e
(-0,105 ns). %88 DSP doluluğunda yerleşim gürültüsü koşudan koşuya ±0,3 ns oynatır.

**DSP sütun kısıtı.** [[efx-dsp48]] kaskadı sütun dışına çıkamaz; 32 uzunluklu kaskaddan en
fazla 28 yerleşir. Çözüm dört fiziksel kaskat × 8 DSP ve SRL hizalamalı kayıtlı toplama
ağacı ([[dsp-chain-systolic-array]]).

**M5 boru düzeltmeleri.** Epilog parametre/LUT tabloları RAM10'a (`snpu_ep_lane`); maxpool
satır tamponu tek RAM'e; residual yeniden ölçek üç aşamaya, requant üç aşamaya; adres üreteci
iki aşamalı boru (S_PASS_WAIT koruması); biriktirici RMW bölmesi (döşeme ≥ 4 piksel); cfg
kopyaları kanal başına yerel; sequencer ve rd_dma çarpımları kayıtlı/artımlı; çıkış adresi
tablo + koşan toplama; taşma bayrağı iki kayıtlı adım; geniş yazmaçlardan reset kaldırma,
`min-sr-fanout` 64; `use-logic-for-small-mem` eşiği 8.

**M7 entegrasyonu.** Dört ek düzeltme (agen sınır karşılaştırması `a1`'e, `mp_busy_q` ve
`bank_free_q` kayıtlı, rd_dma 32×16 çarpımı iki 16×16 yarıya) ve seed/effort taraması:
-0,162 → -0,088 → -0,028 → seed 2 -0,013, seed 3 -0,024, seed 4 -0,126, **seed 1 effort 3
+0,005 ns**. `placer_effort_level` 3'e alındı. Sonuç 1217 DSP48, 1478 RAM10, CDC temiz.
Bu build [[stalyanpu-readme]] M7 kapısını geçti.

**M8 gözlemi.** Aynı tasarımın sonraki build'lerinde slack -0,2 ile -0,6 ns arasında oynadı;
-0,58 ns'lik bir build [[ti375-devkit]] üzerinde tüm çıkış bölgelerini bozuk, koşumdan koşuma
farklı CRC ile üretti. Sonuç: **negatif slack bu cihazda gerçekten kırılabilir ve sonuçlar
deterministik değildir**; her build için board CRC doğrulaması zorunludur
([[board-bringup-flow]]). M8'de kapatılan yollar: maxpool satır sınırı karşılaştırmaları,
epilog çıkış zp toplamı (s9), wfifo'dan 32 zincire ağırlık dağıtımı (ek kayıt,
`shadow_ready` bir çevrim geç), epilog `adv` için residual bayrağı kopyası. Kalan en kötü yol
(-0,35 ns) yazma DMA birleştiricisinin adres eşleme karşılaştırması
(`in_addr → hit → q_mem CE`); önerilen çözüm eşlemeyi bir çevrim önce kaydetmek.

**M9 kapanışı (2026-09-15).** İki yapısal düzeltme tam tasarımı önce +0,013 ns'ye
(seed 3, effort 3, paylaşımlı port build'i) getirdi:
- Reset ağacı: `snpu_top` içinde `rst_all = rst || soft_rst` kayıtlı; `snpu_pe_array` her
  zincire kendi kayıtlı reset kopyasını (`rst_c`) verir, böylece `soft_rst → DSP RST`
  yolu (-0,35 ns) iki kısa yola bölündü. Dizi resetten bir çevrim geç çıkar
  ([[dsp-chain-systolic-array]]).
- Maxpool: 5 girişli max ağacı üç kademeye bölündü (`m01/m23 → m03 → çıkış`); yalnız 5.
  satır okuması boruyu bekler.

Döşeme çift tamponu ve dedicated 512-bit port eklendikten sonra kısıtsız seed taraması
(effort 3, aynı map): seed 1 -0,040, 2 -0,007, 3 -0,110, 4 +0,087, 5 +0,017, 6 +0,088 ns.
Bu tarama `npu_ddr_*` port pinleri kısıtsızken yapıldığı için yanıltıcıydı: "+0,088 ile
kapalı" build board'da ilk dolumda asıldı, -0,110'luk build çalıştı. `pt.sdc` pin kısıtları
`constraints.sdc`'ye taşınınca ihlaller port sınırında çıktı (`rready` -1,58 ns, `arlen`,
`arready`/`wready`, `arstn`); [[snpu-axi-up512]] port yönünde tamamen kayıtlı yapıldı ve
`arstn` false path oldu ([[ddr-port-pin-constraints]]). Son build seed 6:
`io_ddrMasters_0_clk` **+0,038 ns**, peri +0,240 ns; LUT4 98,1k, FF 94,1k, DSP48 1223,
RAM10 1606; board 43,9 fps, iki koşum aynı CRC.

**Yedek planlar (artık gerekmedi).** `CHAIN_LEN=16` + fabric toplayıcı; son çare 200 MHz
(model 29,3 fps @2,4 GB/s). Kapanış için `efx_run_pnr_sweep` seed taraması kullanıldı.

M7 kapısı ile M8 notları arasındaki görünür çelişki (tek build için geçilen kapı, sonraki
build'lerde negatif slack) M9 kapanışıyla çözüldü: [[stalyanpu-readme]] M7 satırı tek
build'in sonucuydu, [[stalyanpu-synthesis-guide]] M8 notları yerleşim gürültüsünü anlatıyordu
ve 24,6 fps bitstream'inin slack değeri kayıtlı değildi. HEAD bitstream'in slack'i (+0,038
ns) ve board sonucu birlikte kayıtlıdır.

## Örnekler
- Sarmalayıcı yöntemi: `clk_in` 125 MHz, `rst_i`, `sin`, `sout` dört pin; girişler kaydırma yazmacından, çıkışlar xor ağacıyla; PLL_BL2 ile 250 MHz, `create_clock -period 4.0 clk`.
- Yerleşim deneyi tablosu: 24×32 269 MHz, 28×32 263 MHz, 24×43 256 MHz, 128×8 258 MHz.
- Kaynak (map, 2026-09-02): `snpu_top` LUT4 45,7k, FF 44,8k, ADD 16,8k, SRL8 10,5k, DSP 1186, RAM10 1149.

## İlişkili Kavramlar
- [[dsp-chain-systolic-array]]: kaskat bölmesinin nedeni, zincir başına kayıtlı reset
- [[ddr-port-pin-constraints]]: sert blok port pinleri kısıtsızken slack raporunun anlamsızlaşması
- [[board-bringup-flow]]: negatif slack'in board'da görünme biçimi ve zorunlu CRC doğrulaması
- [[axi-interconnect-topology]]: `io_ddrMasters_0_clk` alanının paylaşımı
- [[dual-soc-architecture]]: CDC köprüleri (APB 200 MHz → 250 MHz, IRQ)
- Varlıklar: [[snpu-axi-up512]] (port sınırında kayıtlı yapılan modül), [[efinity-toolchain]] (seed taraması, `pt.sdc`)

## Kaynaklar
- [[stalyanpu-synthesis-guide]]: M5 bulguları, M7 entegrasyonu, M8 zamanlama notları, M9 kapanışı ve seed taraması
- [[stalyanpu-bringup-guide]]: port pinleri kısıtları ve son build sonucu
- [[stalyanpu-readme]]: M5 ve M7 kapı sonuçları
- [[stalyanpu-architecture]]: risk R2 ve yedek planlar
