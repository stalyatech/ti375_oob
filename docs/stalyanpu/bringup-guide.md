# StalyaNPU board bring-up (M8, taslak)

Bu sayfa M0'da karar seviyesinde yazılmıştır; adımlar M7 entegrasyonu ve M8'de dolar.

## Yazılım yeri

`embedded_sw/` gitignore'dadır. Bring-up testi izlenebilir olsun diye
`ip/stalyanpu/sw/baremetal/npu_test/` altında tutulur; makefile
`embedded_sw/efx_hard_soc/software/standalone` BSP'sini `STANDALONE=` ile gösterir
(`application/memTest/makefile` deseni, `-DSMP`). Derleyici xPack `riscv-none-elf-gcc`.

## Bileşenler

- `snpu_hal.{c,h}`: üretilen `stalyanpu_isa.h` register haritası; APB penceresi
  `0x100000 + 0x4000` (OpenEye cfg_reg yuvası); `snpu_start(desc_base, n)`, PLIC 9 enable
  (`plic.h`), W1C temizleme, perf sayaçları, zaman aşımı.
- `snpu_loader.c`: v0 OpenOCD `load_image` ile blob + giriş + altın DDR'a yüklenir; v1
  FatFS/SD (`sdhc/fatFSDemo` deseni).
- `snpu_tail.c`: dequant, DFL softmax + beklenti, box decode, sigmoid, NMS (float, FPU var);
  `refmodel/tail.py` ile aynı altı tensör üzerinde doğrulanır.
- `main.c`: blob CRC ve base denetimi, bir kare koşumu, `mtime` ile süre, altı çıkışın CRC32'si
  (debug derlemede her descriptor'ın), UART'a `PASS/FAIL`, uyuşmayan bölgeyi
  `dump_image` için bırakma.

## Sıra

1. `ID`/`VERSION`/`GEOMETRY` okuma.
2. Tek zincir KAT (bilinen yanıt testi): DSP48 DUAL/kaskad silikon davranışı (risk R1).
   M5 öncesine çekilebilir; ayrı küçük proje.
3. Tek katman (sim L1 vektörü) CRC eşleşmesi.
4. Tam kare CRC eşleşmesi.
5. 100 kare döngüsü: fps, `CYCLE_CNT`, `STALL_*` sayaçları → `hwcfg.ddr_bw_gbps` kalibrasyonu.
6. Kamera/Ethernet giriş yolu (kapsam dışı, ayrı iş).

## DDR yolu

Faz 1: `gAXIM_5to1_switch` `MDNN=3` yuvası (128-bit @ 250 MHz, paylaşımlı). Stall sayaçları
DDR sınırını gösterirse Faz 2: `ti375_oob.peri.xml` `axi_target0` (`is_axi_enable`,
`is_axi_width_256`) etkinleştirilir, `efx_run -f interface` ile yeniden üretilir, `snpu_top`
`AXI_DW=256` ile bağlanır. Efinix yan bant pinleri (`ARAPCMD/AWAPCMD/AWALLSTRB/AWCOBUF`)
için uygulama notu istenir.

## Linux

`ip/stalyanpu/sw/linux/README.md` yer tutucu: UIO veya platform sürücüsü, IRQ 9, blob +
scratch için reserved-memory, ioctl start/wait. Kapsam dışı.
