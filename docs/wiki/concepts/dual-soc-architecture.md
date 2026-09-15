---
title: "Çift-SoC Mimarisi"
type: concept
created: 2026-07-03
updated: 2026-09-15
source_count: 5
tags: [architecture, soc, concept]
---

# Çift-SoC Mimarisi

## Tanım
Tek FPGA üzerinde iki bağımsız RISC-V hesaplama alanının, uçuş uygulaması ile platform
ev-işlerini fiziksel olarak ayırırken tek bir DRAM'i paylaşacak şekilde bir arada bulunması.

## Detaylı Açıklama
**Uygulama/uçuş alanı** yazılım SoC [[efx-sapphire-fcu]]'dur: 4 çekirdek, FPU-D, MMU,
[[nuttx]]/Linux yetenekli; tüm kart G/Ç'sini ve Ethernet/SD/DMA veri düzlemini yönetir.
**Ev-işleri/platform alanı** sertleştirilmiş [[efx-sapphire-hpsoc-slb]]'dur: konfigürasyon,
JTAG hata-ayıklama köprüsü, reset üretimi ve sertleştirilmiş [[lpddr4x-controller]] AXI
portunun sahipliği. İki alan [[shared-dram-arbitration]] ile tek belleği, [[axi-interconnect-topology]]
ile de anahtar katmanlarını paylaşır. Bu ayrımın gerekçe ve ödünleşimleri [[fcu-vs-hpsoc]]
karşılaştırmasında incelenir.

### NPU sahipliği (2026-09)
Hızlandırıcı denetimi M7'de yumuşak SoC APB'sinde, M8'den itibaren sert SoC AXI-A/APB
penceresinde; kesme her iki durumda sert SoC PLIC 9. Veri düzlemi M8'e kadar paylaşımlı
anahtarın `MDNN` yuvasından, M9'dan (2026-09-15) itibaren [[lpddr4x-controller]]'ın
dedicated 512-bit `axi_target0` portundan DDR'a; NPU trafiği artık iki SoC'un paylaştığı
köprü yolunun dışındadır. Bkz. [[stalyanpu]], [[accelerator-control-plane-apb]],
[[axi-interconnect-topology]].

## Örnekler
- FCU tüm çevre birim pinlerini (UART/SPI/I2C/GPIO) sürerken, HpSoc'un kendi çevre fabric'i açık bırakılır.
- HpSoc, FCU'ya reset verebilir; FCU watchdog'u ise kendini resetler (tek yönlü reset topolojisi, bkz. [[fmu-notes]]).

## İlişkili Kavramlar
- [[shared-dram-arbitration]]: alanların belleği nasıl paylaştığı
- [[axi-interconnect-topology]]: kontrol/veri düzlemi anahtarları
- [[flight-management-unit]]: bu mimarinin hizmet ettiği rol
- [[hard-soc-fabric-interrupt-path]]: iki SoC'un kesme yollarının farkı

## Kaynaklar
- [[system-overview]], [[hardware-architecture]], [[change-analysis]]
- [[stalyanpu-bringup-guide]]: sert SoC'tan sürüş
- [[stalyanpu-synthesis-guide]]: M7 yumuşak SoC bağlantısı
