---
title: "EfxSapphireFCU ve EfxSapphireHpSoc_slb Karşılaştırması"
type: comparison
created: 2026-07-03
updated: 2026-07-03
tags: [soc, comparison, architecture]
---

# EfxSapphireFCU ve EfxSapphireHpSoc_slb Karşılaştırması

## Özet
İki SoC, [[dual-soc-architecture]]'nin iki alanını oluşturur: [[efx-sapphire-fcu]] uçuş
uygulama işlemcisi (yazılım/soft, tam özellikli), [[efx-sapphire-hpsoc-slb]] ise ev-işleri/
konfigürasyon cephesidir (donanım blok/hard). Uçuş-kritik yük FCU'da yoğunlaşır.

## Karşılaştırma Tablosu

| Boyut | [[efx-sapphire-fcu]] (yazılım) | [[efx-sapphire-hpsoc-slb]] (donanım) |
|-------|-------------------------------|--------------------------------------|
| Rol | Uçuş uygulama işlemcisi | Ev-işleri / konfigürasyon / hata-ayıklama köprüsü |
| Gerçekleme | Fabric'te sentezlenen soft SoC | Sertleştirilmiş işlemci bloğu (`qcrv32_inst1`) |
| Çekirdek | 4× [[vexriscv]] RV32IMAFDC, 200 MHz | Sertleştirilmiş RISC-V (RV32IMAFDC) |
| DRAM erişimi | Master `MFCU` (`io_ddrA`, 128-bit) | DDR denetleyici AXI portunun sahibi (`io_ddrMasters_0`) |
| Çevre birim pinleri | 3× UART/SPI/I2C + GPIO sürer | Kendi çevre fabric'i açık (kullanılmaz) |
| Çevre adres bloğu | `0xF80x_xxxx` | `0xE80x_xxxx` |
| Hata-ayıklama | `io_jtag_*` ← `sys_jtag_io_*` (soft tap) | Fabric tap'i `jtagCtrl_*`/`ut_jtagCtrl_*` sürer |
| Reset | HpSoc ve kendi watchdog'u resetleyebilir | FCU'ya `io_asyncReset` üretir |
| OS/çalışma zamanı | [[nuttx]] (Linux yetenekli) | Bare-metal ev-işleri |
| Veri düzlemi | [[gtse-mac]], [[gdma]], [[gsdhc]] yönetir | Veri düzlemi kaldırılmış (`608bd67`) |

## Detaylı Analiz
FCU, çift-hassasiyet FPU, MMU ve geniş (128-bit) bellek master'ı ile hesaplama-yoğun uçuş
yazılımını taşır; ayrıca tüm gerçek G/Ç pinlerini sürdüğü için sistemin dış dünyayla
arayüzüdür. HpSoc, sertleştirilmiş DDR denetleyicisine sahip olması ve FCU'ya reset/JTAG
sağlaması nedeniyle bir "platform yöneticisi" gibi davranır; kendi çevre birimleri ve `axiA`'sı
bu tasarımda kasıtlı olarak boş bırakılmıştır. Reset topolojisi tek yönlüdür (HpSoc → FCU),
bu da güvenlik analizi için not edilmiştir ([[fmu-notes]]).

## Sonuç
Uçuş fonksiyonları için FCU birincil hedeftir; HpSoc bring-up, konfigürasyon ve hata-ayıklama
için kullanılır. İki alan [[shared-dram-arbitration]] ile tek belleği paylaşır.

## Kaynaklar
- [[system-overview]], [[hardware-architecture]], [[change-analysis]]
