---
title: "Board Bring-up Akışı (M8, M9)"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 4
tags: [bringup, board, ddr, crc, fps, hard-soc, openocd, m9]
---

# Board Bring-up Akışı (M8, M9)

## Tanım
[[stalyanpu]]'nun [[ti375-devkit]] üzerinde sert SoC ([[efx-sapphire-hpsoc-slb]]) ile
doğrulanma yöntemi: derlenmiş YOLOv8s blob'u ve altın bölgeler DDR'a yüklenir, bare-metal
test programı T1..T5 adımlarını koşar, bölge CRC'leri karşılaştırılır ve CSR sayaçlarıyla
fps ölçülür. 2026-09-14 sonucu (M8): tam kare bit bit doğru, 24,6 fps. 2026-09-15 sonucu
(M9): döşeme çift tamponu ile 28,1 fps, dedicated 512-bit DDR portu ile **43,9 fps**; hedef
30 fps aşıldı.

## Detaylı Açıklama
**Adımlar.** (1) `python -m stalyanpu.board.ddrimage <golden_dir> <out_dir>`: `mem.hex` →
`chunk_<addr>.bin` ve `testset.h` (descriptor listesi, bölge CRC'leri). (2) `build.py --set
<out_dir> [--frames N]`: xpack `riscv-none-elf-gcc` 15, BSP `embedded_sw/efx_hard_soc`,
ELF DDR 0x1000'e. (3) `board.py program --hex outflow/ti375_oob.bit`: Efinity FTDI
programlayıcı, JTAG. (4) `board.py openocd`: Efinity OpenOCD, FTDI kanal 1. (5) `board.py
run --set`: telnet 4444, temiz durum, `load_image`, `resume 0x1000`. (6) `board.py dumplog`:
RAM günlüğü. (7) `board.py npu [--desc N] [--reset]`: CSR ve DBG0/DBG1 çözümü
([[descriptor-isa]], [[stalyanpu-toolchain]]).

**Sert SoC yolu.** CSR: AXI-A `0xE800_0000` → `EfxSapphireHpSoc_slb` köprüsü →
`io_apbSlave_0` `0xE810_0000`; NPU CSR üst yarıda `0xE810_4000`. Kesme PLIC 9. Boot RAM
(`OCR_FILE_PATH` boş) sıfır okunduğundan `board.py run` önce OCR'a `j .` yazıp `mtvec`'i
çevirir. UART yumuşak SoC'ta olduğundan çıktı RAM günlüğüne yazılır.
[[stalyanpu-synthesis-guide]] M7 tablosundaki yumuşak SoC APB (`0xF810_4000`) tanımı
eskidir; `ti375_oob_top.v` HEAD sert SoC yolunu belgeler ([[stalyanpu]],
[[dual-soc-architecture]]).

**Programlama sırası (M9 notu).** OpenOCD açıkken bitstream yüklenirse JTAG kaybolur ve
OpenOCD `mpsse_flush` içinde takılır; `board.py program` önce OpenOCD'yi kapatır. Efinity
flow `.bat` sarmalayıcısında `call efx_run` kullanılır.

**Test programı.** T1 kimlik CSR'ları (ID, VERSION, GEOMETRY); T2 DDR'daki blob başlığı
(magic, CRC, base); T3 tek koşum ve bölge CRC'leri; T4 N kare döngüsü (fps, sayaçlar);
T5 PLIC kesmesi.

**DDR yolu bulguları ve düzeltmeleri.**
- Paylaşımlı port kilidi: `rd_dma` tüketici hazır değilken `rready`'yi düşük tutuyordu;
  [[lpddr4x-controller]] portu bekleyen okuma yanıtı tüketilmeden yazmayı kabul etmiyordu,
  residual yolu karşılıklı kilitleniyordu (sim bellek modelinde görünmedi). Çözüm kanal
  başına 64 beat FIFO, kredi tabanlı ihraç, `rready` sabit 1.
- Yazma yolu: kelime başına 32 B AXI işlemi kare süresinin %76'sını beklemeye harcıyordu;
  `snpu_wr_dma` ardışık kelimeleri 256 B (sonra 1 KB, 4 KB) burst'lere birleştirir.
- AXI cache öznitelikleri: `awcache/arcache` 4'b1111; port device modunda tek işlem kabul ediyordu.
- Okuma 1 KB burst, 8 → 16 outstanding; residual boşaltması plane-major (satır başına tek burst).

**Ölçüm dizisi** (CSR 0x24..0x34 sayaçları; MAC alt sınırı 4,87 M çevrim):

| Adım | çevrim/kare | fps |
|---|---:|---:|
| İlk koşum | 53,2 M | 4,6 |
| cache öznitelikleri | 32,1 M | 7,7 |
| yazma burst birleştirme | 20,5 M | 12,1 |
| okuma 1 KB burst, 8 outstanding | 12,9 M | 19,4 |
| yazma 4 KB, okuma 16 outstanding | 12,7 M | 19,6 |
| plane-major boşaltma | 10,2 M | 24,6 |

M8 sonunda kalan dağılım MAC %47, giriş dolumu %35 (etkin 2,5 GB/s, 128-bit paylaşımlı
port, [[shared-dram-arbitration]]), koşumda boş %14. 30 fps için 8,3 M çevrim gerekiyordu;
adaylar giriş dolumunun hesapla örtüşmesi (döşeme çift tamponu), stem L0 im2col modu
(descriptor 0 1,8 M çevrim, 1,05 M'si dolum) ve dedicated DDR portuydu
([[analytic-performance-model]]).

**M9 ölçüm dizisi (2026-09-15).** Tüm satırlar YOLOv8s 640×384, 66 descriptor, tam kare, bit
bit doğru; MAC 4,87 M sabit:

| Adım | çevrim/kare | fps | fill | run_idle | wr_wait |
|---|---:|---:|---:|---:|---:|
| M8 sonu (plane-major) | 10,16 M | 24,6 | 3,6 M | 1,5 M | 0,7 M |
| A: döşeme çift tamponu + zamanlama kapanışı | 8,89 M | 28,1 | 1,04 M | 2,8 M | 1,7 M |
| A2: epilog/yazma örtüşmesi | 8,89 M | 28,1 | aynı | aynı | aynı |
| Dedicated 512-bit DDR portu (`axi_target0` + [[snpu-axi-up512]]) | **5,69 M** | **43,9** | 0,30 M | 0,37 M | 0,79 M |

A'da dolum çevrimleri 3,6 M'den 1,04 M'ye indi ama DDR yarışması `run_idle` ve `wr_wait`'e
taşındı. A2 sim'de kazandırdığı hâlde (demo0 15,3 k → 13,5 k, l4 27,5 k → 24,7 k) board
sayaçlarını hiç değiştirmedi; bu, kare süresinin sert SoC üzerinden geçen paylaşımlı DDR
yolunun (`io_ddrMasters_0` köprüsü) etkin bant genişliğine bağlı olduğunu gösterdi:
63,8 MB/kare ÷ 35,6 ms ≈ 1,8 GB/s. Dedicated port bu bağı kaldırdı; son dağılım MAC %85,
giriş dolumu %5, koşumda boş %6 ([[lpddr4x-controller]]).

**Descriptor profili yöntemi.** `board.py npu --desc N` ile descriptor başına sayaçlar
dökülür (`embedded_sw/logs/desc_profile_m9_table.txt`); A2 öncesi run_idle döşeme sınırı
başına ~11 k çevrimdi (L0 stem 64 döşeme 774 k, L1 16 döşeme 207 k). Bu profil epilog
boşaltmasının hedefini belirledi.

**Determinizm denetimi.** Her adımda aynı bitstream iki kez koşulur ve bölge CRC'leri
birebir eşleşmelidir; M8'de negatif slack'li build'in koşumdan koşuma farklı CRC vermesi bu
denetimi zorunlu kıldı.

**Zamanlama bağı.** -0,58 ns slack'li bir build board'da bozuk sonuç üretti; her build için
CRC doğrulaması zorunludur ([[fpga-timing-closure]]). M9'da `npu_ddr_*` port pinleri
kısıtsızken "+0,088 ile kapalı" bir build ilk dolumda asılı kaldı; kısıtlar `pt.sdc`'den
taşınınca sorun port sınırındaki birleşimsel yollar olarak görünür oldu
([[ddr-port-pin-constraints]]). Son build seed 6, +0,038 ns,
`ip/stalyanpu/.data/build/bits/ti375_oob_hp_ddr4.bit`.

**M0 plan notları (kısmen eskimiş).** Sıra: ID/VERSION/GEOMETRY, tek zincir KAT, tek katman
CRC, tam kare CRC, 100 kare döngüsü, kamera/Ethernet (kapsam dışı). Faz 2 DDR: `axi_target0`
(`is_axi_enable`, `is_axi_width_256`), `AXI_DW=256`, Efinix yan bant pinleri. Linux: UIO
veya platform sürücüsü, IRQ 9, reserved-memory (yer tutucu).

> ❓ **Belirsiz:** Tam kare 66 descriptor bit bit doğru olduğu halde, sıradaki "tek zincir
> KAT" ve "tek katman CRC" adımlarının ayrıca yapılıp yapılmadığı yazmaz. T4 döngüsünde
> kaç kare koşulduğu ve fps'in tek kare mi ortalama mı olduğu belirtilmez.

## Örnekler
- `board.py npu --desc 12` çıktısı: sequencer durumu `[7:3]`, üç kanalın outstanding burst sayıları, AXI ar/r/aw/w/b valid/ready bitleri, yazma AW/W bekleme sayaçları (DBG2/DBG3), genişletici durumu (DBG6).
- Sim-board farkı örneği: AXI bellek modeli kanalları bağımsız işlediği için rd/wr karşılıklı kilidi yalnız board'da göründü; A2 örtüşmesi de sim'de kazandırıp board'da kazandırmadı.

## İlişkili Kavramlar
- [[fpga-timing-closure]]: negatif slack'in board sonuçlarına etkisi
- [[ddr-port-pin-constraints]]: kısıtsız port pinlerinin board'da asılı kalan build üretmesi
- [[analytic-performance-model]]: sayaçlarla kalibrasyon ve 30 fps için gereken çevrim
- [[descriptor-isa]]: CSR sayaçları, DBG yazmaçları, T1..T5'in dokunduğu alanlar
- [[shared-dram-arbitration]], [[axi-interconnect-topology]]: paylaşımlı 128-bit port davranışı ve dedicated porta geçiş
- [[dual-soc-architecture]]: sert SoC'tan sürüş, UART'ın yumuşak SoC'ta kalması
- [[accelerator-control-plane-apb]]: CSR penceresinin sert SoC'a taşınmış hâli
- [[dnn-accelerator-options]]: board sonuçlarının karşılaştırmadaki yeri
- Varlıklar: [[snpu-axi-up512]], [[lpddr4x-controller]], [[yolov8s]]

## Kaynaklar
- [[stalyanpu-bringup-guide]]: uygulanan akış, bulgular, ölçüm tablosu (4,6 → 43,9 fps), dedicated port, plan notları
- [[stalyanpu-perf-plan]]: A/A2/dedicated port adımları ve descriptor profili
- [[stalyanpu-synthesis-guide]]: M8 zamanlama notları ve board'da bozuk build
- [[stalyanpu-readme]]: M8 durum satırı ve kalan işler
