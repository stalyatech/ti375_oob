---
title: "Kaynak: DNN (OpenEye) + Codec Entegrasyon Devri"
type: source
source_file: "docs/dnn-integration/README.md"
author: "volvox"
date: 2026-08-28
created: 2026-09-15
updated: 2026-09-15
tags: [dnn, openeye, accelerator, dma, interrupt, simulation, historical]
---

# Kaynak: DNN (OpenEye) + Codec Entegrasyon Devri

## Özet
`ti375_oob` FMU platformuna [[openeye]] DNN hızlandırıcısının ve rezerve bir H.264/H.265 codec
yuvasının Hard SoC tarafına eklenmesini belgeleyen durum sayfasıdır. 2026-08-27 itibarıyla
donanım entegrasyonu, fonksiyonel simülasyon ve kesme yolu tamamlanmış, tasarım [[ti375c529]]'a
sığmış ve timing kapanmıştır. Bir gün sonra, 2026-08-28'de, hat durdurulmuştur: hedef
(YOLOv8s 640×384 @30 fps) OpenEye'ın mimari tavanının çok üstündedir ve yerine [[stalyanpu]]
tasarlanmaktadır (karar bağlamı: [[dnn-accelerator-options]]). Sayfa artık tarihsel referanstır.

## Temel Çıkarımlar
- Veri düzlemi: [[gdma-dnn]] (efx_dma 6.4.2, SG mod, 64-bit AXIS) DDR'a `gAXIM_5to1_switch`
  üzerinden `MDNN=3` yuvasıyla çıkar; `MCODEC=4` rezerve ve boştadır.
- Kontrol düzlemi: Hard SoC APB3 peripheral 0 penceresi `PADDR[14]` ile ikiye bölünür
  ([[accelerator-control-plane-apb]]).
- Kesme: DNN done kesmesi üst seviye `userInterruptI` üzerinden Hard SoC PLIC ID 9'a gider;
  W1C temizleme cfg penceresi 0x3C'tedir ([[hard-soc-fabric-interrupt-path]]).
- Doğrulama: çekirdek tam oturan konvolüsyon vektöründe (8 filtre, 8x8x4) TensorFlow altın
  modeliyle bit bit eşleşir ([[file-driven-directed-testbench]]).
- Upstream `main` fonksiyonel olarak bozuktur; üretim tabanı `ca5a7dc` + yerel yamalarda kalır
  ([[upstream-regression-bisect]]).

## Detaylı Notlar

### Mimari
Saat düzeni üç alana ayrılır: OpenEye çekirdeği ve her iki stream ucu `io_dnnClk` (100 MHz,
PLL çıkışı 3, out_divider 40); `cfg_reg` ve APB köprüsü `io_peripheralClk` (200 MHz); gDMA_dnn
veri tarafı `io_ddrMasters_0_clk`. CDC'ler gDMA_dnn'in async kanallarında ve `pulse_sync` / 2-FF
senkronizörlerde toplanır. DDR erişimi [[shared-dram-arbitration]] altındaki 5 girişli anahtar
üzerinden [[lpddr4x-controller]]'a ulaşır ([[axi-interconnect-topology]]).

Kapanış rakamları (2026-08-27): setup slack `io_peripheralClk` +0,147 ns, `io_ddrMasters_0_clk`
+0,191 ns, `io_dnnClk` +1,234 ns; hold temiz; CDC raporu uyarısız. OpenEye BRAM yoğundur
(RAM10 894/2688, %33); geometri büyütülürse RTL parametreleri, `gen_stimulus.py` geometrisi ve
blok üretimi birlikte güncellenmelidir.

### Kesme yolu
Kaynağın en önemli bulgusu, [[efx-sapphire-hpsoc-slb]]'nin hard SoC olmadığı, Efinity'nin
ürettiği yumuşak çevre birimi alt sistemi olduğudur; onun `userInterrupt*` çıkışları kendi IRQ
kaynaklarıdır ve boşta bırakılır. Asıl hard SoC (`ti375_oob.peri.xml` içindeki `qcrv32_inst1`)
üst seviye `userInterruptA..L` portlarını PLIC girişi olarak tüketir, harf indeksi PLIC ID'dir.
DNN yolu: `openeye_irq` `dma_o` son beat'inde sticky `dnn_done_irq` üretir; 2-FF senkronizör
peri saatine taşır; `userInterruptI` = PLIC ID 9. Temizleme 0x3C'e bit 0 yazımıyla peri
domaininde darbe üretir, `rtl/pulse_sync.v` (toggle + 3-FF) darbeyi `io_dnnClk`'ya geçirir.
BSP'de `SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT = 9` tanımlıdır.

### Fonksiyonel simülasyon
`sim/openeye/` altında OpenEye'ın Python doğrulama altyapısı `ONLY_FILES=1` modunda stimulus ve
altın referans üretir; doğrulama saf Icarus directed testbench ile yapılır. `tb_openeye_core.v`
çekirdeği, `tb_openeye_glue.v` APB köprüsü ve tam W1C zincirini test eder. Sonuç: glue PASS, core
serbest akış + backpressure PASS (256 beat). İki bilinen sınır vardır: dosya sırasıyla
karşılaştırma (upstream'in `output_order` permütasyonu ve dolgu maskesi yok) ve büyük katmanlarda
(10x10x8, 12x12x8) RTL'in beklenen beat'lerin yarısını üretmesi; bu nedenle commit edilen vektör
tam oturan şekildir.

### Yerel yamalar ve upstream
`ip/OpenEye` alt modülü stalyatech fork'unun `stalya` dalını izler (upstream `ca5a7dc` + tek
commit ile 5 yamalı, 2 üretilmiş dosya). Yedek `patches/openeye-local-patches.diff` altındadır.
Upstream `fe2f5ed`'e (2026-08-20) tam port yapılmış (`stalya-upstream`, `21db525`), sentez geçmiş
ama simülasyon geçmemiştir: çekirdek yalnız bias değerlerini geri basar. Bisect iki regresyon
bulmuştur: `d19314a` (psum_enable temizlemesi kaldırıldı) ve `ff4f99f` (PE.v yeniden yazımı).
Ayrıntı: [[openeye-upstream-issue]].

### Codec yuvası
Codec için APB dekodu genişletilmemiş, `rtl/codec_h26x_stub.v` xml'de hazır ama örneklenmemiş,
`MCODEC=4` boştadır. `rtl/openeye_axilite_adapter.v` ölü koddur; Hard SoC'ta fabric AXI master
bulunmadığından APB köprüsü tercih edilmiştir.

> ⚠️ **Çelişki:** Bu kaynak `userInterruptI` (PLIC ID 9) ve `gAXIM_5to1_switch` tanımlar;
> [[dnn-integration-gui-ip-steps]] ise DNN IRQ'sunu `userInterruptA`'ya ve 4'e 1 anahtara
> bağlar. README gerçeklenen durumdur, GUI adımları ilk plandır.

> ❓ **Belirsiz:** Sayfa "kalan iş" olarak donanım bring-up ve Linux yazılımını listeler; hat
> durdurulduğundan bu adımlar OpenEye için hiç yapılmamıştır. Git geçmişi (`f119069`) OpenEye ve
> gDMA_dnn dosyalarının [[stalyanpu]] `MDNN` yuvasını aldığında proje kaynak listesinden
> çıkarıldığını gösterir; `ip/OpenEye` alt modülü ve `sim/openeye/` diskte durur.

## Bağlantılar
- İlgili varlıklar: [[openeye]], [[gdma-dnn]], [[learning-chips-lab]], [[efx-sapphire-hpsoc-slb]],
  [[ti375c529]], [[lpddr4x-controller]], [[efinity-toolchain]], [[stalyanpu]]
- İlgili kavramlar: [[hard-soc-fabric-interrupt-path]], [[accelerator-control-plane-apb]],
  [[file-driven-directed-testbench]], [[upstream-regression-bisect]], [[shared-dram-arbitration]],
  [[axi-interconnect-topology]], [[dual-soc-architecture]], [[dnn-accelerator-options]]
- İlgili kaynaklar: [[dnn-integration-gui-ip-steps]] (çelişen), [[openeye-upstream-issue]] (destekleyen)

## Alıntılar
- "`EfxSapphireHpSoc_slb` hard SoC değil, Efinity'nin ürettiği yumuşak çevre birimi alt
  sistemidir; onun `userInterrupt*` çıkışları kendi IRQ kaynaklarıdır" (Kesme yolu bölümü).
- "Karar: üretimde `stalya` (`ca5a7dc` + yamalar) kalır." (Upstream durumu bölümü).
