---
title: "Kaynak: Efinity GUI IP Manager, DNN Pipeline IP Üretimi (tarihsel)"
type: source
source_file: "docs/dnn-integration/gui-ip-steps.md"
author: "volvox"
date: 2026-08-27
created: 2026-09-15
updated: 2026-09-15
tags: [dnn, openeye, efinity, ip-generation, apb, dma, historical]
---

# Kaynak: Efinity GUI IP Manager, DNN Pipeline IP Üretimi (tarihsel)

> ⏸️ **Tarihsel belge.** Buradaki IP üretim adımları tamamlanmıştır; sayfa birebir GUI değerleri
> için referans olarak durur. Gerçeklenen durum [[dnn-integration-readme]] sayfasındadır.

## Özet
[[openeye]] DNN hızlandırıcısı ve codec yuvası için [[efinity-toolchain]] GUI IP Manager'da
üretilmesi gereken üç IP'yi birebir parametrelerle anlatan çalışma talimatıdır: DDR anahtarına
yeni bir master yuvası, OpenEye stream'lerini taşıyan [[gdma-dnn]] ve Hard SoC'ta bir APB3
peripheral portunun açılması. IP üretimi CLI ile güvenilir olmadığından adımlar GUI'de insan eliyle
yapılmış, sonrasındaki sentez ve PnR `efx_run` ile koşulmuştur. Belge ayrıca kontrol düzlemi
kararını (APB3 köprüsü) ve önerilen adres / IRQ haritasını içerir.

## Temel Çıkarımlar
- Hard SoC'un fabric'e AXI master'ı yoktur (`axiA` slave, `intf_axim` yalnız DDR master'ı);
  özel fabric peripheral'e desteklenen erişim yolu APB3 peripheral portudur.
- Bu desen, [[efx-sapphire-fcu]]'nun [[gdma]]'yı APB ile kontrol etmesiyle birebir aynıdır ve
  mevcut `rtl/apb3_2_axi4_lite.v` köprüsüyle AXI4-Lite'a çevrilir ([[accelerator-control-plane-apb]]).
- Üç IP: `gAXIM_4to1_switch` (efx_axi_interconnect v5.4, S_PORTS 3→4), `gDMA_dnn`
  (efx_dma v6.4.2, 64-bit stream kanalları) ve [[efx-sapphire-hpsoc-slb]] regen (`peri_apb_0 = 1`).
- Hard SoC regen çalışan `place` durumunu bozar; en yüksek etkili adım budur.

## Detaylı Notlar

### Kontrol düzlemi kararı
Plandan revizyon olarak Hard SoC'un fabric AXI master'ı bulunmadığı tespit edilmiş, Efinity
Sapphire Hard SoC'ta desteklenen yol olan APB3 peripheral portu (`peri_apb_0..4`, o an kapalı)
seçilmiştir. Topoloji: Hard SoC `io_apbSlave_0` (APB3 master) → PADDR dekodu → üç hedef:
`gDMA_dnn` ctrl (APB native), `apb3_2_axi4_lite` → OpenEye `cfg_reg`, `apb3_2_axi4_lite` →
`codec_h26x_stub` ctrl.

### IP 1: DDR anahtarı
`efx_axi_interconnect` v5.4, `axi_infra` kütüphanesi; mevcut `ip/gAXIM_3to1_switch` referans
alınır, yalnız `S_PORTS` 3'ten 4'e çıkar. Diğer parametreler: `M_PORTS=1`, `DATA_WIDTH=128`,
`ADDR_WIDTH=32`, `ID_WIDTH=8`, `USER_WIDTH=3`, `PROTOCOL=AXI4`, `ARB_MODE=ROUND_ROBIN_1`.
Belge, codec'in aynı anda eklenmesi halinde `S_PORTS=5` ile `gAXIM_5to1_switch` üretilmesini
seçenek olarak sunar; gerçekleşen bu seçenek olmuştur ([[axi-interconnect-topology]],
[[shared-dram-arbitration]]).

### IP 2: gDMA_dnn
`efx_dma` v6.4.2, `bridges_and_adaptors` kütüphanesi; mevcut `ip/gDMA` referans alınır
(MemExtWidth=128, SG mode, async). Kanal A MEM→STREAM (Output, Width=64, SG, BurstSize ~1024)
OpenEye `dma_i`'yi besler; kanal B STREAM→MEM (Input, Width=64, SG) `dma_o` sonucunu DDR'a yazar.
`CTRL_ASYNC_MODE=1` (APB saati ≠ DDR saati), kanal AsyncMode=1 (stream saati ≠ DDR). Mevcut gDMA
8-bit Ethernet stream'leri için ayarlıdır; burada stream genişliği OpenEye `DMA_BITWIDTH=64` ile
eşleşir.

### IP 3: Hard SoC APB3 portu
`EfxSapphireHpSoc_slb` IP'si configure edilerek APB peripheral 0 etkinleştirilir
(`hard_ip_args.ini`: `peri_apb_0 = 1`, `peri_apb_0_size = 65536`). Top'a `io_apbSlave_0_*`
master portu eklenir. Bu adım Linux/OS'tan bağımsızdır.

### Adres haritası (öneri)
Hard SoC APB penceresinde: `gDMA_dnn` 0x0000–0x3FFF (APB native), OpenEye `cfg_reg` 0x4000–0x40FF,
`codec_h26x_stub` 0x8000–0x80FF. DDR yuvaları `MTSE=0, MSDHC=1, MFCU=2, MDNN=3` (codec ile
`MCODEC=4`). DNN done IRQ: `userInterruptA`; codec: `userInterruptB`.

### Üretim sonrası plan
Üst seviye wiring (`open_eye_mt_v1_0`, `gDMA_dnn`, anahtar, köprü, `openeye_irq`,
`codec_h26x_stub`), `MDNN`/`AXIM_DEV` localparam'ları, `MHSDC → MSDHC` düzeltmesi
([[fmu-notes]]'ta işaretlenen yazım hatası), OpenEye kaynaklarının `ti375_oob.xml`'e eklenmesi
ve `USE_INTERNAL_PARAMS` define'ı.

> ⚠️ **Çelişki:** Bu belge DNN IRQ'sunu `userInterruptA`'ya bağlar ve `gAXIM_4to1_switch`
> üretir. Gerçeklenen tasarım ([[dnn-integration-readme]]) `userInterruptI` (PLIC ID 9) ve
> `gAXIM_5to1_switch` (`MDNN=3`, `MCODEC=4`) kullanır. Kesme yolu bulgusu için bkz.
> [[hard-soc-fabric-interrupt-path]].

> ⚠️ **Çelişki:** Codec kontrol penceresi (0x8000–0x80FF) ve `userInterruptB` burada planlanmış,
> ancak README'ye göre APB dekodu genişletilmemiş, `codec_h26x_stub` örneklenmemiş ve `MCODEC`
> boşta kalmıştır; 0x8000+ erişimleri cfg yoluna aliaslanır.

## Bağlantılar
- İlgili varlıklar: [[openeye]], [[gdma-dnn]], [[gdma]], [[efx-sapphire-hpsoc-slb]],
  [[efx-sapphire-fcu]], [[efinity-toolchain]], [[lpddr4x-controller]]
- İlgili kavramlar: [[accelerator-control-plane-apb]], [[hard-soc-fabric-interrupt-path]],
  [[axi-interconnect-topology]], [[shared-dram-arbitration]], [[dual-soc-architecture]]
- İlgili kaynaklar: [[dnn-integration-readme]] (gerçeklenen durum), [[fmu-notes]]

## Alıntılar
- "Hard SoC'un fabric'e AXI master'ı yok (`axiA` slave; `intf_axim` yalnızca DDR master'ı)."
  (Kontrol düzlemi kararı bölümü).
- "Bu, FCU'nun `gDMA`'yı APB ile kontrol etmesiyle birebir aynı desendir." (aynı bölüm).
