---
title: "Hard SoC Fabric Kesme Yolu"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [interrupt, plic, hard-soc, cdc, w1c]
---

# Hard SoC Fabric Kesme Yolu

## Tanım
Fabric'teki bir bloğun kesmesinin Hard SoC PLIC'ine nasıl ulaştığını tanımlayan bulgu: kesme,
[[efx-sapphire-hpsoc-slb]]'nin `userInterrupt*` çıkışlarına değil, üst seviye modülün
`userInterruptA..X` **çıkış portlarına** bağlanır; harf indeksi PLIC ID'dir (A=1 .. L=12).

## Detaylı Açıklama
Kaynak [[dnn-integration-readme]] iki katmanı ayırır:
- `EfxSapphireHpSoc_slb`, Efinity'nin ürettiği yumuşak çevre birimi alt sistemidir, hard SoC'un
  kendisi değildir. Onun `userInterrupt*` **çıkışları** bu alt sistemin kendi IRQ kaynaklarıdır ve
  tasarımda boşta bırakılır (`.userInterruptI ( )`).
- Asıl hard SoC (`ti375_oob.peri.xml` içindeki SOC bloğu `qcrv32_inst1`) üst seviyenin
  `userInterruptA..L` portlarını PLIC girişi olarak tüketir; M..X boştur. Mevcut kullanım bu deseni
  doğrular: `userInterruptF = sd_int`, `G/H = dma_interrupts`.

Yol üç parçadan oluşur:
1. **Kaynak ve latch:** kaynak saat alanında (OpenEye için `io_dnnClk`) tek çevrim olay
   (`dma_o` son beat'i) sticky bir bayrağa (`dnn_done_irq`) yazılır.
2. **CDC ve port:** 2-FF senkronizör bayrağı `io_peripheralClk`'ya taşır;
   `assign userInterruptI = irq_sync[1];` PLIC ID 9'a düşer. BSP'de karşılığı
   `SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT = 9` (`soc.h`).
3. **W1C temizleme:** yazılım hızlandırıcı cfg penceresinde bir register'a (OpenEye: offset 0x3C,
   bit 0) 1 yazar; peri domaininde tek çevrim darbe üretilir; `rtl/pulse_sync.v` (toggle + 3-FF)
   darbeyi kaynak saatine geçirir ve latch'i temizler. Yazma aynı zamanda sıradan cfg register'ına
   düşer, çekirdek bu register'ı kullanmadığından zararsızdır.

Sürücü akışı: PLIC ID'yi enable + priority ile aç, kesme işleyicide W1C register'ına 1 yaz, yeni
descriptor zinciri kur. Alternatif: DMA descriptor durumunu polling ile izlemek.

Aynı yol [[stalyanpu]] entegrasyonunda korunmuştur: `irq_o` iki FF ile peri saatine geçer ve
üst seviye `userInterruptI` (PLIC 9) sürülür; StalyaNPU, OpenEye'ın yuvasını ve kesme hattını
devralmıştır.

## Örnekler
- OpenEye done: `openeye_irq` → `dnn_irq_sync[1]` → `userInterruptI` → PLIC 9, W1C 0x3C.
- StalyaNPU done: `irq_o` → `npu_irq_sync[1]` → `userInterruptI` → PLIC 9.
- SD kart: `sd_int` → `userInterruptF` → PLIC 6 ([[gsdhc]]).
- Ethernet DMA: `dma_interrupts[1:0]` → `userInterruptG/H` → PLIC 7/8 ([[gdma]]).

> ⚠️ **Çelişki:** [[dnn-integration-gui-ip-steps]] DNN kesmesini `userInterruptA` olarak
> planlamıştı; gerçeklenen yol `userInterruptI`'dir. Plan, üst seviye harflerinin PLIC ID'ye
> eşlendiğinin ve A..H'nin dolu olduğunun bilinmediği döneme aittir.

## İlişkili Kavramlar
- [[accelerator-control-plane-apb]]: W1C register'ının bulunduğu cfg penceresi
- [[dual-soc-architecture]]: Hard SoC ve yumuşak SoC ayrımı, PLIC'in hangi tarafta olduğu
- [[file-driven-directed-testbench]]: tam W1C zincirinin `tb_openeye_glue.v` ile doğrulanması

## Kaynaklar
- [[dnn-integration-readme]]: bulgunun kaynağı, DNN yolu ve BSP notu
- [[dnn-integration-gui-ip-steps]]: ilk (yanlış) `userInterruptA` planı
