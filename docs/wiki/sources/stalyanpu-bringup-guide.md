---
title: "Kaynak: StalyaNPU Board Bring-up (M8, M9)"
type: source
source_file: "ip/stalyanpu/docs/bringup-guide.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, bringup, board, ti375-devkit, hard-soc, ddr, performance]
---

# Kaynak: StalyaNPU Board Bring-up (M8, M9)

## Özet
[[stalyanpu]]'nun [[ti375-devkit]] üzerinde sert SoC ([[efx-sapphire-hpsoc-slb]]) ile
doğrulanmasını anlatır. İlk bölüm uygulanan akıştır (DDR imajı, derleme, bitstream, OpenOCD,
koşum, günlük, CSR durumu), board bulguları, T1..T5 test programı ve M8'den M9'a adım adım
performans tablosu (4,6 → 24,6 → 28,1 → **43,9 fps**). Bugünkü sürüm iki M9 bölümü ekler:
port pinlerinin zamanlaması ve DDR yolu Faz 2 (512-bit `axi_target0` + [[snpu-axi-up512]]).
Alt bölümler M0'daki plan notlarıdır (yazılım yeri, bileşenler, sıra, Linux yer tutucu).

## Temel Çıkarımlar
- [[yolov8s]] 640×384 tam kare, 66 descriptor, board'da bit bit doğru: **5,69 M çevrim/kare = 43,9 fps**, MAC %85 (4,87 M alt sınır); hedef 30 fps aşıldı.
- CSR yolu: sert SoC AXI-A `0xE800_0000` → `EfxSapphireHpSoc_slb` köprüsü → `io_apbSlave_0` `0xE810_0000`; NPU CSR `0xE810_4000`; kesme PLIC 9.
- Paylaşımlı yolda (sert SoC `io_ddrMasters_0` köprüsü) kare süresi etkin bant genişliğine (~1,8 GB/s) bağlıydı; A2 örtüşmesi sayaçları değiştirmedi.
- Dedicated port 512-bit: arayüz tasarımcısı x32 LPDDR4x'te 256-bit AXI'yi reddeder; NPU 256-bit kalır, genişletici araya girer.
- Arayüz tasarımcısının `npu_ddr_*` için ürettiği set_input/output_delay değerleri `constraints.sdc`'ye elle eklenmelidir; kısıtsız build'ler yerleşime göre asılı kaldı ([[ddr-port-pin-constraints]]).

## Detaylı Notlar
**Uygulanan akış.** Araçlar `sw/baremetal/npu_test/` altında; `build.py` xpack
`riscv-none-elf-gcc` 15'i doğrudan çağırır. Adımlar: `stalyanpu.board.ddrimage` (DDR imajı ve
`testset.h`), `build.py` (ELF, DDR 0x1000), `board.py program` (Efinity FTDI programlayıcı),
`board.py openocd`, `board.py run` (telnet 4444, `load_image` ≈ 220 KB/s), `board.py dumplog`
(RAM günlüğü), `board.py npu` (CSR ve DBG çözümü). Bu akış [[board-bringup-flow]] kavramının
çekirdeğidir; board araçları [[stalyanpu-toolchain]]'in parçasıdır.

**Board bulguları (M8).** Boot RAM boş (`OCR_FILE_PATH` boş): hart `mtvec=0` fault
döngüsünde, `board.py run` önce OCR'a `j .` yazar. UART yumuşak SoC'ta olduğundan test
programı RAM günlüğüne yazar. Paylaşımlı DDR portu kilidi: `rd_dma` `rready`'yi düşük tutunca
port yazmayı kabul etmiyordu; çözüm kanal başına 64 beat FIFO, kredi tabanlı ihraç
([[shared-dram-arbitration]]). Yazma yolu: kelime başına 32 B işlem kare süresinin %76'sını
yiyordu; `snpu_wr_dma` burst'lere birleştirir. Test programı T1..T5 (kimlik, blob başlığı, tek
koşum CRC, N kare döngüsü, PLIC kesmesi; [[hard-soc-fabric-interrupt-path]]).

**Performans ölçümleri.** CSR sayaçları ([[descriptor-isa]]): `cycles`, `fill`, `run_idle`,
`mac`, `wr_wait`.

| Adım | çevrim/kare | fps | fill | run_idle | wr_wait |
|---|---:|---:|---:|---:|---:|
| İlk koşum (32 B yazma, cache 0) | 53,2 M | 4,6 | 8,3 M | 39,5 M | 40,5 M |
| Cache 1111, burst birleştirme, 1 KB okuma | 12,9 M | 19,4 | 3,6 M | 4,2 M | 4,0 M |
| Plane-major boşaltma (M8 son) | 10,2 M | 24,6 | 3,6 M | 1,5 M | 0,7 M |
| Döşeme çift tamponu + kapanış (M9) | 8,89 M | 28,1 | 1,04 M | 2,8 M | 1,7 M |
| + A2 epilog örtüşmesi | 8,89 M | 28,1 | 1,04 M | 2,8 M | 1,7 M |
| **Dedicated 512-bit port** | **5,69 M** | **43,9** | 0,30 M | 0,37 M | 0,79 M |

Belgedeki tam tablo M8 ara adımlarını da (7,7; 12,1; 19,6 fps) verir. Çift tamponda `fill`
3,6 M'den 1,04 M'e indi ama DDR yarışması `run_idle` ve `wr_wait`'e taşındı (slack
+0,013 ns). A2 sayaçları hiç değiştirmedi: 63,8 MB/kare ÷ 35,6 ms ≈ 1,8 GB/s etkin bant
genişliği sınırdı. Dedicated portta MAC %85, giriş dolumu %5, koşumda boş %6, yazma bekleme
0,81 M; adaylar stem im2col ve yazma beklemesi ([[analytic-performance-model]]).

**Port pinlerinin zamanlaması.** Arayüz tasarımcısı `outflow/ti375_oob.pt.sdc` içinde
`npu_ddr_*` için `set_input_delay`/`set_output_delay` üretir (giriş max 2,625 ns, çıkış max
2,31 ns); bunlar `constraints.sdc`'ye elle eklenmelidir. Eklenmeden iki build (biri +0,088 ns
"kapalı") ilk dolumda asılı kaldı, üçüncüsü (−0,110) çalıştı. Kısıtlar eklenince ihlaller
port sınırındaki birleşimsel yollarda çıktı: `npu_ddr_rready` −1,58 ns, sonra `arlen`,
`arready`/`wready`, `arstn`. Genişletici artık port yönünde tamamen kayıtlı (AR 2'lik kuyruk,
okuma 4'lük beat FIFO'su ve kayıtlı `rready`, W 2'lik çıkış kuyruğu, B tutma register'ı);
`arstn` SDC'de `set_false_path`; wide burst'ler 64 B hizalı beat'ten başlar
([[fpga-timing-closure]]).

**DDR yolu Faz 2.** [[lpddr4x-controller]] `axi_target0` portu; `ti375_oob.peri.xml` içinde
`is_axi_enable="true"`, `is_axi_width_256="false"`, pin adları `npu_ddr_*`, `ACLK_0` doğrudan
`io_ddrMasters_0_clk` saat ağı; `efx_run -f interface` şablon üretir. `snpu_axi_up512` 32
baytlık kelimeleri 64 baytlık beat'lere çevirir: kelime `A[5]` şeridine biner, tek kalan
yarılar strobe ile maskelenir, burst geometrisi kuyrukta. Yan bant: `ARAPCMD/AWAPCMD` 0,
`AWALLSTRB` 0 (aksi halde yazma 16 beat sınırı), `AWCOBUF` 0, `AWCACHE` 1111, ID'ler 0,
`ARSTN = ~npu_rst`; Titanium DDR DRAM Block User Guide v2.8 (ASIZE 6 için ALEN ≤ 63 →
`WR_SLOT_WORDS=64`). MDNN yuvası boşta ([[axi-interconnect-topology]]). Sim: `tb_axi_up512`
ve `tb_*_up512` sistem testleri (`MEM_DW=512`).

**M0 plan notları.** "Bileşenler" bölümü CSR'ı hâlâ M7 hâliyle, yumuşak SoC
([[efx-sapphire-fcu]]) APB slave 0 üst yarısında (`0xF810_4000`, alt yarı [[gdma]]) anlatır
ve sert SoC'tan sürüş için `io_apbSlave_0`'ın etkinleştirilmesini "M8 kararı" olarak yazar.
Karar uygulanmıştır: "Uygulanan akış" bölümündeki `0xE810_4000` yolu HEAD'in gerçek yoludur,
plan notu güncellenmemiştir ([[accelerator-control-plane-apb]], [[dual-soc-architecture]]).
Linux bölümü yer tutucudur.

> ❓ **Belirsiz:** Yumuşak SoC APB penceresinin M8 sonrası fiziksel olarak sökülüp
> sökülmediği belgede yazmaz.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[ti375-devkit]], [[efx-sapphire-hpsoc-slb]], [[yolov8s]], [[stalyanpu-toolchain]], [[snpu-axi-up512]], [[lpddr4x-controller]], [[efx-sapphire-fcu]], [[gdma]]
- İlgili kavramlar: [[board-bringup-flow]], [[ddr-port-pin-constraints]], [[shared-dram-arbitration]], [[hard-soc-fabric-interrupt-path]], [[descriptor-isa]], [[analytic-performance-model]], [[fpga-timing-closure]], [[axi-interconnect-topology]], [[accelerator-control-plane-apb]], [[dual-soc-architecture]]
- Destekleyen kaynaklar: [[stalyanpu-readme]], [[stalyanpu-isa-descriptor]], [[stalyanpu-synthesis-guide]], [[stalyanpu-perf-plan]], [[stalyanpu-architecture]]

## Alıntılar
- "Arayüz tasarımcısı x32 LPDDR4x'te 256-bit AXI'yi kabul etmez ("AXI Data Width 256 is not supported"), port 512-bittir" (satır 120-122)
- "Eklenmeden iki build (biri +0,088 ns "kapalı") ilk dolumda asılı kaldı, üçüncüsü (−0,110) çalıştı: kısıtsız pinlerde davranış yerleşime bağlıydı." (satır 69-70)
