---
title: "OpenEye — Eyeriss Tarzı DNN Hızlandırıcısı"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 3
tags: [dnn, accelerator, openeye, eyeriss, row-stationary, historical]
---

# OpenEye — Eyeriss Tarzı DNN Hızlandırıcısı

## Tanım
[[learning-chips-lab]] tarafından SHL-2.1 lisansıyla yayımlanan, Eyeriss mimarisini temel alan
satır sabit (row-stationary) veri akışlı açık kaynak DNN hızlandırıcısı. `ti375_oob` platformuna
Hard SoC tarafında entegre edilmiş, simülasyonda bit bit doğrulanmış, ardından **2026-08-28'de
durdurulmuştur**.

## Temel Bilgiler

### Geometri ve performans
Bu projede kullanılan konfigürasyon: 2x2 cluster (`CLUSTER_ROWS=2`, `CLUSTER_COLUMNS=2`),
`BRANCHES=1`, `BUFFER_WIDTH=10`, `RAM_CELLS=8`, `DMA_BITWIDTH=64`, `QUANT_AMOUNT=32`. Çekirdek
`io_dnnClk` 100 MHz'de çalışır; 96 MAC/çevrim ile tepe değeri yaklaşık 19 GOPS'tur. Tasarımda
BRAM yoğundur (RAM10 894/2688, %33). Bu tavan YOLOv8s 640×384 @30 fps hedefinin çok altında
kaldığından, [[dnn-accelerator-options]] değerlendirmesi sonucunda yerine [[stalyanpu]]
tasarlanmıştır.

### Entegrasyon
Üst modül `open_eye_mt_v1_0`; veri düzlemi [[gdma-dnn]] üzerinden `gAXIM_5to1_switch`
`MDNN=3` yuvasıyla [[lpddr4x-controller]]'a çıkar ([[shared-dram-arbitration]]). Kontrol
`cfg_reg` (16×32-bit) Hard SoC APB3 penceresinin üst yarısında `apb3_2_axi4_lite` köprüsü
arkasındadır ([[accelerator-control-plane-apb]]). Done kesmesi `openeye_irq` → 2-FF → üst seviye
`userInterruptI` (PLIC ID 9), W1C 0x3C ([[hard-soc-fabric-interrupt-path]]). Tasarım
[[ti375c529]]'a sığmış ve timing kapanmıştır (2026-08-27). Doğrulama `sim/openeye/`
altındaki [[file-driven-directed-testbench]] ile yapılmış; tam oturan konvolüsyon vektörü
(8 filtre, 3x3, 8x8x4 giriş, 463 kelime → 256 beat) TensorFlow altın modeliyle bit bit eşleşmiştir.

### Fork ve dallar
`ip/OpenEye` alt modülü `stalyatech/OpenEye` fork'unu izler (`origin`); `upstream` =
Learning-Chips-Lab/OpenEye. Dallar:
- **`stalya`**: üretim tabanı, upstream `ca5a7dc` + tek commit ile yerel yamalar. Alt modülün
  izlediği daldır.
- **`stalya-upstream`** (`21db525`): upstream `fe2f5ed` (2026-08-20) üzerine tam port; sentez
  geçer, simülasyon geçmez. Efinity uyumluluk yamaları, cocotb harness sürücüleri ve gelişmiş
  testbench burada bekler.
- Fork `main` upstream `main` ile güncel tutulur.

### Yerel yama listesi (`stalya` dalı)
| Dosya | Yama |
|-------|------|
| `fpga/hdl/open_eye_axi_v1_0.v` | `QUANT_AMOUNT=32` parametresi; yinelenen `.BUFFER_WIDTH` kaldırıldı |
| `hdl/OpenEye_FPGA.v` | `USE_INTERNAL_PARAMS` self-define; VERI-1466 stray `temp_var=0` ve `psum_data_i_reg` çoklu sürücü reset'i kaldırıldı |
| `src/open_eye/generator.py` | Port listesi virgülü `",\n".join` ile (Windows text-mode seek kusuru) |
| `src/open_eye/conv_mapper.py` | quantize/offset döngü sınırı sabit 1024 yerine `params.QUANT_AMOUNT` |
| `src/open_eye/dense_mapper.py` | Aynı QUANT_AMOUNT ölçekleme yaması |

Üretilen dosyalar: `hdl/dma_storage.v`, `hdl/include/regmap_params.vh` (doğru kaynak
`test/cocotb_fpga/regmap.yaml`, 54 register). Yedek: `docs/dnn-integration/patches/`.

### Upstream bisect özeti
Upstream `main` fonksiyonel olarak bozuktur; yalın checkout da conv testinde bias-only çıktı
verir. `ca5a7dc` PASS; `d19314a` psum_enable temizlemesini kaldırarak birinci regresyonu,
`ff4f99f` PE.v yeniden yazımıyla ikinci regresyonu getirir; `3531eb3` tek satırlık düzeltmeyle son
sağlam commit'tir. 2x2 çok-cluster yolu `3531eb3`'te bile düşer. Ayrıntı ve yöntem:
[[openeye-upstream-issue]], [[upstream-regression-bisect]].

### Durum
**Durduruldu, 2026-08-28.** Gerekçe: mimari tavan hedefin çok altında ve upstream sağlıksız.
Git geçmişine göre (`f119069`) OpenEye ve gDMA_dnn dosyaları, [[stalyanpu]] `MDNN` yuvasını
aldığında proje kaynak listesinden ve `ti375_oob_top.v`'den çıkarılmıştır. `ip/OpenEye`
alt modülü, `sim/openeye/` ve `docs/dnn-integration/` tarihsel referans olarak diskte durur.
Donanım bring-up hiç yapılmamıştır.

## Kaynaklarda Geçişi
- [[dnn-integration-readme]]: entegrasyonun gerçeklenen son durumu, yama listesi, bisect tablosu
- [[dnn-integration-gui-ip-steps]]: IP üretim planı ve ilk adres/IRQ önerisi (tarihsel)
- [[openeye-upstream-issue]]: upstream regresyon raporu taslağı

## İlişkiler
- [[learning-chips-lab]]: upstream sahibi ve lisans veren
- [[gdma-dnn]]: `dma_i`/`dma_o` stream'lerini DDR ile taşıyan DMA
- [[stalyanpu]]: yerine geçen kurum içi hızlandırıcı
- [[dnn-accelerator-options]]: durdurma kararının bağlamı
- [[efx-sapphire-hpsoc-slb]]: kontrol ve kesme yolunun bağlandığı Hard SoC tarafı
- [[ti375c529]]: hedef aygıt, kaynak kullanımı
- [[axi-interconnect-topology]]: `gAXIM_5to1_switch` `MDNN` yuvası
- [[efinity-toolchain]]: sentez, PnR ve Python 3.11 ortamı
