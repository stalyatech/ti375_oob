# StalyaNPU board bring-up (M8)

Bu sayfanın ilk bölümü 2026-09-14'te board üzerinde uygulanan akışı anlatır; alt
bölümler M0'daki plan notlarıdır.

## Uygulanan akış (Titanium Ti375C529 Development Kit, sert SoC)

Araçlar `ip/stalyanpu/sw/baremetal/npu_test/` altındadır. GNU make gerekmez;
`build.py` xpack `riscv-none-elf-gcc` 15'i doğrudan çağırır (BSP: `embedded_sw/efx_hard_soc`).

| Adım | Komut | Not |
|---|---|---|
| DDR imajı | `python -m stalyanpu.board.ddrimage <golden_dir> <out_dir>` | `mem.hex` → `chunk_<addr>.bin`, `testset.h` (descriptor listesi, bölge CRC'leri) |
| Derleme | `python build.py --set <out_dir> [--frames N]` | `build/npu_test.elf`, DDR 0x1000'e yüklenir |
| Bitstream | `python board.py program --hex outflow/ti375_oob.bit` | Efinity FTDI programlayıcı, JTAG, `.bit` ister |
| Debug sunucusu | `python board.py openocd` | Efinity'nin kendi OpenOCD'si (`debugger/openocd`), BSP `ftdi_ti.cfg` + `debug_ti.cfg`, FTDI kanal 1 |
| Koşum | `python board.py run --set <out_dir>` | telnet 4444: temiz durum, `load_image` (≈220 KB/s), ELF, `resume 0x1000` |
| Sonuç | `python board.py dumplog` | RAM günlüğünü (`log_buf`) okur; PASS/FAIL satırları, sayaçlar |
| Durum | `python board.py npu [--desc N] [--reset]` | CSR ve DBG0/DBG1 çözümü (sequencer durumu, DMA sayaçları, AXI el sıkışmaları) |

Board bulguları ve çözümleri:

- **Boot RAM boş.** `ti375_oob.peri.xml` içinde `OCR_FILE_PATH` boş olduğundan sert SoC'un
  16 KB çip içi RAM'i (0xF900_0000) sıfır okunur; resetten sonra hart `mtvec=0` fault
  döngüsündedir. Bu durumdan `resume` edilince ilk fetch her adreste instruction access
  fault verir. `board.py run` önce OCR'a bir `j .` yazıp `mtvec`'i oraya çevirir, hart'ı
  kısa süre orada koşturur ("temiz durum"), sonra programı yükler.
- **UART.** `sys_uart_0` üst seviyede yumuşak SoC'a bağlıdır; sert SoC'un UART'ı fabric'te
  boştadır. Test programı çıktısını RAM günlüğüne yazar, `dumplog` OpenOCD ile okur.
  FTDI arayüzleri: A/B JTAG (libusb), C = COM11, D = COM10.
- **CSR yolu.** Sert SoC AXI-A (0xE800_0000) → `EfxSapphireHpSoc_slb` köprüsü →
  `io_apbSlave_0` (0xE810_0000). NPU CSR üst yarıda: **0xE810_4000**. Kesme PLIC 9.
- **Paylaşımlı DDR portu kilidi.** `rd_dma` tüketici hazır değilken `rready`'yi düşük
  tutuyordu; board'daki port bekleyen okuma yanıtı tüketilmeden yazmayı kabul etmiyor,
  residual yolu karşılıklı kilitleniyordu (sim bellek modeli kanalları bağımsız işlediği
  için görünmedi). Çözüm: kanal başına 64 beat FIFO ve kredi tabanlı ihraç, `rready` sabit 1.
- **Yazma yolu.** Kelime başına bir 32 B AXI işlemi board'da çok yavaştı (kare süresinin
  %76'sı yazma beklemesi). `snpu_wr_dma` artık ardışık kelimeleri 256 B burst'lere
  birleştirir (4 açık yuva, boşta sayacı ile kapanış).

Test programı (`src/main.c`): T1 kimlik CSR'ları, T2 DDR'daki blob başlığı, T3 tek koşum
ve bölge CRC'leri, T4 N kare döngüsü (fps, sayaçlar), T5 PLIC kesmesi.

### Performans ölçümleri (YOLOv8s 640×384, tam kare, 66 descriptor, hepsi bit bit doğru)

Sayaçlar (CSR 0x24..0x34): `cycles` meşgul çevrim, `fill` giriş dolum fazları (dizi boş),
`run_idle` koşum fazında diziye vektör girmeyen çevrim, `mac` diziye vektör giren çevrim,
`wr_wait` çıkış kelimesinin yazma yolunda beklediği çevrim. MAC alt sınırı 4,87 M çevrimdir.

| Adım | çevrim/kare | fps | fill | run_idle | wr_wait | Not |
|---|---:|---:|---:|---:|---:|---|
| İlk koşum | 53,2 M | 4,6 | 8,3 M | 39,5 M | 40,5 M | kelime başına 32 B yazma, AXI cache 0 |
| awcache/arcache 4'b1111 | 32,1 M | 7,7 | 8,3 M | 18,8 M | 19,4 M | port device modunda tek işlem kabul ediyordu |
| Yazma burst birleştirme (8 kelime) | 20,5 M | 12,1 | 8,3 M | 7,1 M | 7,3 M | tahliye kuralı düzeltilince burst 7,8 kelime |
| Okuma 1 KB burst, 8 outstanding; yazma 1 KB | 12,9 M | 19,4 | 3,6 M | 4,2 M | 4,0 M | fill 8,3 → 3,6 M |
| Yazma 4 KB, okuma 16 outstanding | 12,7 M | 19,6 | 3,6 M | 4,1 M | 2,3 M | |
| Plane-major boşaltma | **10,2 M** | **24,6** | 3,6 M | 1,5 M | 0,7 M | residual satır başına tek burst, 16 plane'li katmanlar birleşiyor |

Kalan dağılım: MAC %47, giriş dolumu %35 (2,5 GB/s etkin, 128-bit paylaşımlı port),
koşumda boş %14. 30 fps için 8,3 M çevrim gerekir; adaylar: giriş dolumunun hesapla
örtüşmesi (döşeme çift tamponu), stem için L0 im2col modu (descriptor 0 tek başına 1,8 M
çevrim, 1,05 M'si dolum), 256-bit dedicated DDR portu.


## Yazılım yeri

`embedded_sw/` gitignore'dadır. Bring-up testi izlenebilir olsun diye
`ip/stalyanpu/sw/baremetal/npu_test/` altında tutulur; makefile
`embedded_sw/efx_hard_soc/software/standalone` BSP'sini `STANDALONE=` ile gösterir
(`application/memTest/makefile` deseni, `-DSMP`). Derleyici xPack `riscv-none-elf-gcc`.

## Bileşenler

- `snpu_hal.{c,h}`: üretilen `stalyanpu_isa.h` register haritası; CSR penceresi M7'de
  yumuşak SoC (`EfxSapphireFCU`) APB slave 0'ın üst yarısına bağlandı: taban
  `0xF810_4000` (`IO_APB_SLAVE_0_INPUT` + 0x4000; alt yarı gDMA). Sert SoC `io_apbSlave_0`
  bu yapılandırmada sürücüsüz. Kesme sert SoC PLIC 9'a gider; bu yüzden v0 testte
  CSR yumuşak SoC'tan sürülür, tamamlanma `STATUS`/`IRQ_STATUS` yoklamasıyla izlenir.
  Sert SoC'tan sürüş için `io_apbSlave_0` peri.xml'de etkinleştirilmelidir (M8 kararı).
  `snpu_start(desc_base, n)`, W1C temizleme, perf sayaçları, zaman aşımı.
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
