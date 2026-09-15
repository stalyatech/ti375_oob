---
title: "Titanium Ti375C529 Development Kit"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [ti375, devkit, board, ftdi, jtag, bringup, m9]
---

# Titanium Ti375C529 Development Kit

## Tanım
Efinix'in [[ti375c529]] FPGA'ini taşıyan geliştirme kartı. [[stalyanpu]] M8 board
bring-up'ı bu kart üzerinde, sert SoC ([[efx-sapphire-hpsoc-slb]]) tarafından sürülerek
yapılmıştır.

## Temel Bilgiler
**Hata ayıklama ve programlama.** Kart üzerindeki FTDI köprüsünün dört arayüzü vardır: A/B
JTAG (libusb; Efinity FTDI programlayıcı `.bit` ile, Efinity'nin kendi OpenOCD'si
`ftdi_ti.cfg` + `debug_ti.cfg` ile FTDI kanal 1'den RISC-V debug), C = COM11, D = COM10
(UART). `board.py program`, `board.py openocd` (telnet 4444) ve `board.py run`
(`load_image` ≈ 220 KB/s, `resume 0x1000`) bu yolları kullanır ([[board-bringup-flow]],
[[stalyanpu-toolchain]]).

**Bring-up'ta görülen kart/yapılandırma davranışları.**
- Sert SoC'un 16 KB çip içi RAM'i (0xF900_0000) `OCR_FILE_PATH` boş olduğundan sıfır okunur;
  reset sonrası hart `mtvec=0` fault döngüsündedir. `board.py run` OCR'a `j .` yazıp
  `mtvec`'i oraya çevirerek "temiz durum" oluşturur.
- `sys_uart_0` yumuşak SoC'a ([[efx-sapphire-fcu]]) bağlı; sert SoC UART'ı fabric'te boşta.
  Test çıktısı RAM günlüğüne (`log_buf`) yazılır, `dumplog` OpenOCD ile okur.
- Sert SoC CSR yolu: AXI-A `0xE800_0000` → `EfxSapphireHpSoc_slb` köprüsü → `io_apbSlave_0`
  `0xE810_0000`; NPU CSR `0xE810_4000`; kesme PLIC 9.
- Paylaşımlı DDR portu, bekleyen okuma yanıtı tüketilmeden yazmayı kabul etmiyor; sim bellek
  modelinde görünmeyen bu davranış rd_dma FIFO düzeltmesini gerektirdi
  ([[lpddr4x-controller]], [[shared-dram-arbitration]]).
- Negatif slack'li (-0,58 ns) bir build board'da bozuk sonuç üretti; her build için board
  doğrulaması zorunlu ([[fpga-timing-closure]]).

**M9 eklemeleri (2026-09-15).**
- OpenOCD, programlama sırasında açıksa JTAG'i kaybedip takılıyor (`mpsse_flush`); bitstream
  yüklemeden önce OpenOCD kapatılır, sonra yeniden açılır. Efinity flow `.bat`
  sarmalayıcısında `call efx_run` kullanılmalıdır, yoksa akış ilk çağrıda sona erer.
- NPU artık [[lpddr4x-controller]]'ın dedicated 512-bit `axi_target0` portunda; kart
  üzerinde [[snpu-axi-up512]] genişleticisinin durumu CSR DBG6 (0x58) ile okunur ve
  `board.py npu` bunu çözer. `npu_ddr_*` port pinleri kısıtsızken build'ler ilk dolumda
  asılı kaldı ([[ddr-port-pin-constraints]]).
- Son bitstream `ip/stalyanpu/.data/build/bits/ti375_oob_hp_ddr4.bit` (seed 6, +0,038 ns).

**Ölçüm.** YOLOv8s 640×384 tam kare bit bit doğru: M8 sonu 24,6 fps (10,16 M çevrim/kare
@250 MHz); M9 döşeme çift tamponu 28,1 fps (8,89 M); dedicated 512-bit DDR portu
**43,9 fps** (5,69 M, MAC %85). Her adımda iki koşum aynı CRC'yi verdi.

## Kaynaklarda Geçişi
- [[stalyanpu-bringup-guide]]: uygulanan akış, FTDI arayüzleri, boot RAM, UART, CSR yolu, DDR kilidi, OpenOCD sırası, M9 ölçümleri
- [[stalyanpu-readme]]: M8 durum satırı ("Ti375C529 kitinde ... bit bit doğru")

## İlişkiler
- [[ti375c529]]: kart üzerindeki FPGA
- [[stalyanpu]]: kart üzerinde doğrulanan hızlandırıcı
- [[efx-sapphire-hpsoc-slb]]: bring-up'ta NPU'yu süren sert SoC
- [[efx-sapphire-fcu]]: UART'ın bağlı olduğu yumuşak SoC
- [[lpddr4x-controller]]: kart üzerindeki DRAM ve NPU'nun dedicated portu
- [[snpu-axi-up512]]: DBG6 ile izlenen genişletici
- [[stalyanpu-toolchain]]: `board.py` ve `ddrimage` araçları
- [[efinity-toolchain]]: programlayıcı ve OpenOCD
- [[board-bringup-flow]]: kart üzerindeki doğrulama akışı
- [[ddr-port-pin-constraints]]: kısıtsız port pinlerinin kartta asılı kalan build'lere yol açması
