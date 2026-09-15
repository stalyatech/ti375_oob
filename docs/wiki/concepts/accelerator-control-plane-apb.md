---
title: "Hızlandırıcı Kontrol Düzlemi: APB3 Penceresi"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [apb, axi-lite, control-plane, address-map, hard-soc]
---

# Hızlandırıcı Kontrol Düzlemi: APB3 Penceresi

## Tanım
Fabric'teki bir hızlandırıcının ve DMA'sının SoC tarafından tek bir APB3 peripheral penceresi
üzerinden kontrol edilmesi deseni: 64 KB pencere `PADDR[14]` ile ikiye bölünür, alt yarı DMA
kontrolüne (APB native), üst yarı `apb3_2_axi4_lite` köprüsü arkasındaki hızlandırıcı register
bloğuna gider.

## Detaylı Açıklama
Desenin gerekçesi [[dnn-integration-gui-ip-steps]]'te verilir: Efinity Sapphire Hard SoC'un
fabric'e AXI master'ı yoktur (`axiA` slave, `intf_axim` yalnız DDR master'ı). Özel bir fabric
peripheral'e erişmenin desteklenen yolu IP configurator'da bir APB peripheral portu açmaktır
(`peri_apb_0 = 1`, `peri_apb_0_size = 65536`); bu, top'a `io_apbSlave_0_*` master portu ekler.
Aynı desen [[efx-sapphire-fcu]]'nun [[gdma]]'yı `sp_apbSlave_0` ile kontrol etmesinde zaten
kullanılır.

Gerçeklenen dekod ([[dnn-integration-readme]], Hard SoC `io_apbSlave_0` @ 0x100000):

| `PADDR[14]` | Alt pencere | Hedef | Köprü |
|---|---|---|---|
| 0 | 0x0000..0x3FFF | [[gdma-dnn]] ctrl | APB native (`PADDR[13:0]`) |
| 1 | 0x4000+ | [[openeye]] `cfg_reg` (16×32-bit) | `rtl/apb3_2_axi4_lite.v` → AXI4-Lite |

**Adres aliaslama:** cfg tarafında yalnız 6 bit adres dekodlanır, dolayısıyla 0x4000 üstündeki
tüm pencere 16 register üzerine katlanır. Planlanan codec penceresi (0x8000+) da bugün cfg yoluna
aliaslanır; codec eklenirken dekod genişletilmelidir. `rtl/openeye_axilite_adapter.v` bu karar
sonrası ölü koda dönüşmüştür.

Saat alanları: APB köprüsü ve register bloğu `io_peripheralClk` (200 MHz) üzerindedir; register
bloğu hızlandırıcı saatinde çalışıyorsa araya CDC girer. OpenEye'da `cfg_reg` peri saatindeydi;
[[stalyanpu]] entegrasyonunda ise CSR penceresi yumuşak SoC'un `sp_apbSlave_0` üst yarısına
(`PADDR[14]=1`, yazılım tabanı `0xF810_4000`) taşınmış ve `rtl/snpu_apb_cdc.v` toggle köprüsüyle
250 MHz NPU saatine geçirilmiştir; Hard SoC `io_apbSlave_0` o yapılandırmada sürücüsüzdür.
Bu M7 durumudur. M8'den itibaren (HEAD) köprü yeniden Hard SoC `io_apbSlave_0` penceresine
alınmıştır: AXI-A `0xE800_0000` → `0xE810_0000`, NPU CSR `0xE810_4000`, `PADDR[14]=0`
ayrılmış ve her zaman hazır; yumuşak SoC'taki üst yarı boş kalır ([[stalyanpu]],
[[board-bringup-flow]]).
Yani `PADDR[14]` bölme deseni korunmuş, master tarafı değişmiştir.

Kesme temizleme (W1C) register'ı da bu pencerede yaşar; bkz. [[hard-soc-fabric-interrupt-path]].

## Örnekler
- OpenEye: `0x100000 + 0x3C` yerine `0x100000 + 0x4000 + 0x3C` W1C register'ı; `0x100000 + 0x0`
  gDMA_dnn descriptor kontrolü.
- FCU / gDMA: `sp_apbSlave_0` alt yarısı gDMA, üst yarısı (StalyaNPU sonrası) NPU CSR.

> ⚠️ **Çelişki:** [[dnn-integration-gui-ip-steps]] codec kontrolü için 0x8000–0x80FF ayrı bir
> pencere planlar; README'ye göre bu dekod hiç eklenmemiştir ve 0x8000+ cfg yoluna aliaslanır.

## İlişkili Kavramlar
- [[hard-soc-fabric-interrupt-path]]: aynı pencerede W1C temizleme
- [[dual-soc-architecture]]: hangi SoC'un hangi APB penceresini sürdüğü
- [[axi-interconnect-topology]]: veri düzlemi bu kontrol düzleminden bağımsızdır

## Kaynaklar
- [[dnn-integration-gui-ip-steps]]: kontrol düzlemi kararı ve önerilen adres haritası
- [[dnn-integration-readme]]: gerçeklenen dekod ve aliaslama notu
