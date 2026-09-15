---
title: "EfxSapphireHpSoc_slb (Donanım Blok SoC)"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-15
source_count: 6
tags: [soc, riscv, sapphire, hard-processor, housekeeping]
---

# EfxSapphireHpSoc_slb (Donanım Blok SoC)

## Tanım
Sertleştirilmiş (hard) RISC-V işlemci bloğu sarmalayıcısı; tasarımın **ev-işleri /
konfigürasyon / JTAG hata-ayıklama köprüsü** cephesi. Üst modülde `u_top_peripherals` olarak
örneklenir.

## Temel Bilgiler
Kendi çevre birimi fabric'i ve `axiA` portu bu tasarımda **açık** (kullanılmayan) bırakılmıştır.
Sürdükleri: fabric JTAG tap'i (`jtagCtrl_*` / `ut_jtagCtrl_*` — [[efx-sapphire-fcu]]'ya hata-
ayıklama köprüsü), konfigürasyon denetleyicisi (`cfg_*`), FCU'yu resetleyen `io_asyncReset` ve
`io_gpio_sw_n`. Sertleştirilmiş DDR denetleyicisinin AXI portu ISF'te `qcrv32_inst1`'e bağlıdır
ve üst seviyede `io_ddrMasters_0` olarak yüzeye çıkar. `608bd67` commit'iyle bu SoC'tan
TSEMAC/SDHC/SLB switch kaldırılmış, geriye ev-işleri kalmıştır ([[oob-to-fmu-transformation]]).

### DNN hızlandırıcı denetimi (2026-08/09)
- `EfxSapphireHpSoc_slb` sert SoC'un kendisi değil, Efinity'nin ürettiği yumuşak çevre birimi alt sistemidir; `userInterrupt*` çıkışları kendi IRQ kaynaklarıdır ve boşta bırakılır. Fabric kesmeleri üst seviye `userInterruptA..X` portlarıyla sert SoC PLIC'ine gider (harf sırası = PLIC ID). Bkz. [[hard-soc-fabric-interrupt-path]].
- APB peripheral 0 (`peri_apb_0 = 1`, 64 KB, CPU adresi `0xE810_0000`) [[openeye]] için açıldı; bugün `PADDR[14]=1` yarısı `snpu_apb_cdc` köprüsüyle [[stalyanpu]] CSR'ına (`0xE810_4000`) gider (`ti375_oob_top.v` HEAD). Bkz. [[accelerator-control-plane-apb]].
- M8 bring-up'ta NPU sert SoC'tan sürülür (AXI-A `0xE800_0000` → köprü → `io_apbSlave_0`); DFL/decode/sigmoid/NMS kuyruğu sert RISC-V'de (< 1 ms, float). Kesme PLIC 9 (`userInterruptI`).
- Boot RAM (`OCR_FILE_PATH` boş) sıfır okunur; hart reset sonrası `mtvec=0` fault döngüsündedir. Sert SoC UART'ı fabric'te boşta.

## Kaynaklarda Geçişi
- [[system-overview]]: çift-SoC ayrımı
- [[hardware-architecture]]: SoC örnekleri bölümü
- [[change-analysis]]: donanım SoC değişiklikleri

- [[stalyanpu-bringup-guide]]: sert SoC'tan sürülen M8 bring-up akışı
- [[stalyanpu-synthesis-guide]]: M7 entegrasyon tablosu (eski yumuşak SoC CSR yolu)
- [[dnn-integration-readme]]: APB peripheral 0 ve kesme yolu bulguları

## İlişkiler
- [[efx-sapphire-fcu]]: karşılaştırma [[fcu-vs-hpsoc]]; JTAG köprüsü ve reset kaynağı
- [[lpddr4x-controller]]: AXI portuna sahip olduğu bellek denetleyicisi
- [[ti375c529]]: barındığı cihaz
- [[stalyanpu]]: CSR'ını sürdüğü hızlandırıcı
- [[ti375-devkit]]: bring-up board'u
- [[board-bringup-flow]]: T1..T5 test akışı
- [[hard-soc-fabric-interrupt-path]]: kesmelerin PLIC'e ulaşma yolu
