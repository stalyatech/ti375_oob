---
title: "Kaynak: Karar Kaydı (StalyaVPU)"
type: source
source_file: "ip/stalyavpu/docs/decision-record.md"
author: "volvox"
date: 2026-09-24
created: 2026-09-24
updated: 2026-09-24
tags: [stalyavpu, codec, h264, hevc, decision, resources, ram10]
---

# Kaynak: Karar Kaydı (StalyaVPU)

## Özet
2026-09-24 tarihli karar: `ti375_oob` tasarımına H.264/H.265 video codec IP'si [[stalyavpu]]
eklenir. Önce H.264 decoder (High profile, progressive, 8-bit 4:2:0, CABAC ve CAVLC),
ardından aynı boru hattına HEVC decoder, en son encoder yapılır. Hedef 1920x1080 30 fps,
DDR'dan DDR'a. Kaynak ölçümü, codec'i sınırlayan kaynağın DSP48 değil blok RAM olduğunu
gösterdi; bu yüzden npu0'ın tamponları küçültülür. Belge ayrıca stateless yazılım/donanım
bölümünü, ayrı 160 MHz saati ve DDR/kontrol/kesme bağlantı kararlarını kaydeder.

## Temel Çıkarımlar
- Bu cihazda codec'i sınırlayan kaynak **RAM10** (2305/2688 dolu, DRC eşiğinde 114 boş); ikinci
  kısıt XLR (DRC %85 ile yaklaşık 87k). DSP48 bol: 531 boş.
- npu0 (32x16) `p_max` 1024→512, `ibuf` 512→256 KB: yaklaşık 461 RAM10 boşalır, model fps
  25,1 → 24,9 ([[analytic-performance-model]]).
- Decoder stateless: slice header ve DPB yazılımda, `slice_data()` sonrası donanımda;
  descriptor alanları V4L2 stateless kontrollerine eşlenir.
- H.264 makrobloğu 16x16 CTU olarak işlenir; CABAC motoru iki standartta ortak.
- Boş DDR switch yuvası yok (codec için ayrılan yuva 4 eMMC'de): `gAXIM_5to1_switch` 6:1 olur.

## Detaylı Notlar

### Hedef ve kullanıcı kararları
Kullanıcı dört kararı verdi: ilk codec H.264, hedef 1080p30, npu0 tampon küçültmesi, test
akışları ffmpeg ile üretilmiş akışlar ve ITU conformance alt kümesi. Tasarımda kamera veya
ekran arayüzü olmadığı için çıkış NV12 kare olarak DDR'da kalır ve [[stalyanpu]]'ya veya ağa
beslenebilir.

### Kaynak ölçümü
2026-09-24 build'i (seed 2): XLR 220 760 / 362 880, RAM10 2305 / 2688, DSP48 813 / 1344.
NPU'lar RAM10'un 1948'ini, DSP48'in 788'ini kullanır. PLIC'te yalnız `userInterruptC` boş.
`io_ddrMasters_0_clk` (250 MHz) +0,080 ns ile kapanmış, pay az ([[fpga-timing-closure]]).

### NPU küçültmesi
Değerlendirilen seçenekler: npu0 tamponlarını küçültmek (seçildi), npu1'i kaldırmak (679 RAM10,
202 DSP48, 56k XLR ve switch yuvası 3 boşalır ama toplam 24,7 fps'e düşer, 30 fps hedefinin
altına iner), ikisi birden. Artan npu0 DDR trafiği (63,2 → 80,4 MB/kare) npu0'ın dedicated
portunda kalır. Uygulama entegrasyon adımında `python -m stalyanpu system apply` ile
([[multi-instance-npu]]).

### Mimari kararlar
1. Stateless bölüm: slice header ayrıştırması 1 GHz sert RISC-V çekirdeğinde ucuz, donanımda pahalı.
2. Ortak omurga: bitstream okuyucu, CABAC motoru, DMA, referans önbelleği, bi/weighted tahmin,
   rekonstrüksiyon ve çıkış yazıcı iki standartta ortak.
3. `vpu_clk` 160 MHz: CABAC bin döngüsü 250 MHz'te kapanmaz; kaynak kullanılmayan `io_dnnClk`
   PLL çıkışı (/40 → /25).
4. DDR: 6:1 switch, yuva 5 `MVPU`, 128-bit, asenkron köprü; bu yol sert SoC önbellekleriyle
   tutarlıdır ([[shared-dram-arbitration]], [[axi-interconnect-topology]]).
5. Kontrol: sert SoC APB `0xE810_C000`, `snpu_apb_cdc` ile saat geçişi
   ([[accelerator-control-plane-apb]]); kesme PLIC 3 ([[hard-soc-fabric-interrupt-path]]).

### Riskler
H.264 + HEVC decoder kullanılabilir XLR'ı aşabilir, encoder kesin aşar; HEVC aşamasından önce
npu1 kaldırma veya ayrı bitstream varyantı sorulacak. 250 MHz alanına eklenen yuva zamanlamayı
zorlayabilir.

## Bağlantılar
- İlgili varlıklar: [[stalyavpu]], [[stalyanpu]], [[lpddr4x-controller]], [[ti375c529]], [[efx-dsp48]]
- İlgili kavramlar: [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[multi-instance-npu]], [[analytic-performance-model]], [[fpga-timing-closure]]
- Destekleyen kaynaklar: [[stalyanpu-decision-record]] (aynı cihaz tavanı ölçüm yöntemi)

## Alıntılar
- "Sonuç: bu cihazda codec'i sınırlayan kaynak **blok RAM**, ikinci sırada XLR. DSP48 bol."
