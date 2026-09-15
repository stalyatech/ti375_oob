---
title: "EfxSapphireFCU (Yazılım SoC)"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-15
source_count: 7
tags: [soc, riscv, sapphire, fcu, application-processor]
---

# EfxSapphireFCU (Yazılım SoC)

## Tanım
Tasarımın **uçuş uygulama işlemcisi** olan yazılım (soft) Efinix Sapphire SoC'u. "FCU" =
Flight Control Unit. [[ti375c529]] fabric'i üzerinde sentezlenir.

## Temel Bilgiler
Dört çekirdekli [[vexriscv]] **RV32IMAFDC** (çift-hassasiyet FPU + MMU + Supervisor), 200 MHz,
8 KB 2-yollu I/D önbellek. Tüm kart çevre birimlerini sürer (3× UART/SPI/I2C, GPIO) ve
Ethernet/SD/DMA veri düzleminin ana yöneticisidir. DRAM'e 128-bit `io_ddrA` master'ı (veri
düzleminde `MFCU` portu) ile, çevre birimlerine 32-bit `axiA` master'ı (kontrol düzlemi) ile
erişir; [[gdma]]'yı APB3 üzerinden kontrol eder. [[nuttx]]'i SPI flash'tan başlatır. FMU
dönüşümüyle `Linux=true`, `LDSize` 1020K ve 128-bit AXI master'a geçmiş, custom-instruction
hızlandırıcısı kaldırılmıştır ([[oob-to-fmu-transformation]]).

### DNN hızlandırıcı denetimi (2026-08/09)
- Bu SoC'un gDMA'yı APB ile sürme deseni, sert SoC tarafında [[openeye]]/[[gdma-dnn]] için birebir kopyalandı ([[accelerator-control-plane-apb]]).
- M7'de [[stalyanpu]] CSR'ı `sp_apbSlave_0` penceresinin üst yarısına bağlandı (`PADDR[14]=1` NPU `0xF810_4000`, `PADDR[14]=0` [[gdma]]; `rtl/snpu_apb_cdc.v` 200 → 250 MHz köprüsü).
- M8'den itibaren (HEAD, 2026-09-15 doğrulaması dahil) NPU CSR köprüsü sert SoC [[efx-sapphire-hpsoc-slb]] `io_apbSlave_0` penceresindedir; bu SoC'taki üst yarı ayrılmış kalır (her zaman hazır, sıfır okur). [[stalyanpu-synthesis-guide]] M7 tablosu ve [[stalyanpu-architecture]] kontrol satırı hâlâ eski bağlantıyı anlatır ve eskidir; güncel kaynak [[stalyanpu-bringup-guide]] ve `ti375_oob_top.v`'dir.
- `sys_uart_0` bu SoC'a bağlı olduğundan sert SoC bring-up testi çıktısını RAM günlüğüne yazar.

## Kaynaklarda Geçişi
- [[system-overview]]: çift-SoC ayrımı tablosu
- [[hardware-architecture]]: arayüz/bağlantı tablosu
- [[software-architecture]]: bellek haritası ve uygulama envanteri
- [[change-analysis]]: FMU konfigürasyon değişiklikleri

- [[stalyanpu-synthesis-guide]]: M7 CSR penceresi
- [[stalyanpu-bringup-guide]]: UART ve M8 kararı
- [[stalyanpu-architecture]]: entegrasyon notu

## İlişkiler
- [[efx-sapphire-hpsoc-slb]]: karşılaştırma [[fcu-vs-hpsoc]]
- [[vexriscv]]: çekirdek mimarisi
- [[nuttx]]: üzerinde koşan RTOS
- [[gtse-mac]], [[gdma]], [[gsdhc]]: sürdüğü veri-düzlemi çevre birimleri
- [[lpddr4x-controller]]: `MFCU` portu üzerinden paylaşımlı DRAM ([[shared-dram-arbitration]])
- [[stalyanpu]]: M7'de CSR'ını sürdüğü hızlandırıcı (M8'den itibaren sert SoC sürer)
- [[accelerator-control-plane-apb]]: APB pencere bölme deseni
