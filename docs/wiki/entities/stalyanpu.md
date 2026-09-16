---
title: "StalyaNPU"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-16
source_count: 10
tags: [stalyanpu, npu, dnn, accelerator, int8, dsp48, rtl]
---

# StalyaNPU

## Tanım
Proje içinde sıfırdan tasarlanan INT8 konvolüsyonel sinir ağı hızlandırıcısı. [[ti375c529]]
üzerinde [[yolov8s]] modelini 640×384 letterbox çözünürlükte 30 fps hedefiyle koşturmak için
2026-08-28'de [[openeye]] yerine geliştirilmesine karar verildi ([[dnn-accelerator-options]]).
RTL öneki `snpu_`, alt depo `ip/stalyanpu`, dal `stalya-fmu_v2.0-npu`.

## Temel Bilgiler
**Hesap çekirdeği.** 1024 [[efx-dsp48]] DUAL bloğu = **2048 INT8 MAC/çevrim**; 250 MHz'de
teorik tepe **512 GMAC/s** (yaklaşık 1,02 TOPS INT8). Dizi 32 zincir × 32 DSP, her zincir
dört fiziksel kaskat × 8 DSP; döşeme 32 IC × 64 OC, çevrimde bir çıkış pikseli
([[dsp-chain-systolic-array]]). Ağırlık-sabit sistolik akış, DSP içinde birikim yok, tap ve
IC-grubu birikimi 32-bit RAM10 biriktiricide (`snpu_acc`, 2 bank × 1024 px × 64 OC). Epilog
bias, u16 requant, 256 girişli SiLU LUT, residual Add ve int8 paketlemeyi 32 OC/çevrim
hızında yapar ([[int8-quantization-flow]]).

**Bellek ve veri yolu.** ibuf 512 KB (16 bank), acc 512 KB, wfifo 32 KB; toplam ≈ 933 RAM10.
Tensör düzeni NC32HW ile Concat/Split/Upsample sıfır kopya. Kendi AXI4 okuma ve yazma
DMA'ları vardır. Okuma DMA'sı (`snpu_rd_dma`, `N_CH=3`) üç komut kanallıdır: kanal 0
denetim (descriptor, param, LUT, residual, maxpool), kanal 1 ağırlık, kanal 2 ibuf dolumu;
kanal başına `snpu_beat_fifo` beat FIFO'su, kayıtlı burst boyu (`nb_q`), döner sıralı AR
ihracı, 3 burst kredi payı. M8'e kadar `gAXIM_5to1_switch` `MDNN=3` 128-bit yuvasından
[[lpddr4x-controller]]'a erişiyordu ([[shared-dram-arbitration]],
[[axi-interconnect-topology]]); M9'dan itibaren 256-bit AXI portu [[snpu-axi-up512]]
genişleticisi üzerinden denetleyicinin dedicated 512-bit `axi_target0` portuna bağlıdır ve
MDNN yuvası boştadır. Saat `io_ddrMasters_0_clk` 250 MHz.

**Kontrol.** DDR'daki 128 baytlık descriptor listesi, CRC32 korumalı, `snpu_seq` yürütür;
CSR (ID, GEOMETRY, CTRL, STATUS, IRQ, perf sayaçları, DBG0..6), kare başına bir kesme
(PLIC 9) ([[descriptor-isa]]). CSR yolu sert SoC [[efx-sapphire-hpsoc-slb]] AXI-A
`0xE800_0000` → `io_apbSlave_0` → `0xE810_4000` (HEAD); M7'deki yumuşak SoC APB tanımı
eskidir (aşağıya bak).

**Döşeme çift tamponu ve boşaltma örtüşmesi (M9).** `snpu_seq` ayrı bir dolum makinesi
(`fstate`) çalıştırır: döşeme t koşarken t+1 ibuf'un diğer yarısına dolar
(`cfg_ibuf_base = tile[0] ? IBUF/2 : 0`); yarıyı aşacak dolum hata 7 (geometri) ile
durdurulur, `emit.py` ayak izini derleme sırasında denetler. Ara döşemelerde `S_RUN_WAIT`
`ag_done` ile çıkar; döşeme başına çıkış bağlamı tablolarda tutulur (`out_base_tab` 4
giriş, residual satır terimi ve satır sayısı tabloları), epilog `drain_tile` /
`out_tile_nxt` / `out_adv` ile hangi döşemeyi boşalttığını bildirir. Biriktirici 2 bank
olduğundan en çok 3 döşeme aynı anda canlıdır; son döşeme ve descriptor sonu tam bekler.

**Geometri bağlama (2026-09-16).** `ti375_oob_top.v` artık `snpu_top` parametrelerini
`rtl/snpu_config.vh` içindeki `SNPU_CFG_*` define'larından alır; bu dosyayı
`python -m stalyanpu project apply` (ya da arayüzün 4. adımı) yazar ve `rtl/snpu_config.json`
bitstream'in hangi geometriyle kurulduğunu kaydeder. Böylece dizi boyutu değiştirmek üst
modüle dokunmadan yapılır ve bitstream eskidiğinde araç uyarır ([[stalyanpu-ip-generator]]).
Board veri yolu `AXI_DW` 256 ve `WR_SLOT_WORDS` 64 değerlerini sabitler.

**Yazılım.** [[stalyanpu-toolchain]] Python paketi ONNX lowering, kalibrasyon, bit-kesin
referans model, descriptor/blob derleme, sim vektörleri, perf modeli
([[analytic-performance-model]]) ve board araçlarını sağlar. YOLOv8s 66 descriptor, blob
11,3 MB, scratch 11,6 MB.

**Durum (2026-09-14, M8 sonu).** M0..M7 tamam. INT8 mAP50-95 düşüşü 0,78 puan. Sentez:
dizi 258 MHz, motor 256 MHz, tam tasarım M7'de +0,005 ns; M8'de build'ler arası -0,2 ile
-0,6 ns arasında oynadı ve kalan en kötü yol -0,35 ns idi ([[fpga-timing-closure]]).
Kaynak: 1217 DSP48, 1478 RAM10 (M7). Board: [[ti375-devkit]] üzerinde tam kare bit bit
doğru, 24,6 fps (hedef 30; MAC alt sınırı 4,87 M çevrim, ölçülen 10,2 M).

**Durum (2026-09-15, M9).** Üç adımda 30 fps hedefi aşıldı; hepsi YOLOv8s 640×384, 66
descriptor, tam kare, bit bit doğru ve iki koşumda aynı CRC ([[board-bringup-flow]]):

| Adım | çevrim/kare | fps |
|---|---:|---:|
| M8 sonu (plane-major) | 10,16 M | 24,6 |
| A: döşeme çift tamponu + zamanlama kapanışı (reset ağacı, maxpool borusu) | 8,89 M | 28,1 |
| A2: epilog/yazma örtüşmesi | 8,89 M | 28,1 |
| Dedicated 512-bit DDR portu (`axi_target0` + [[snpu-axi-up512]]) | **5,69 M** | **43,9** |

Son dağılım MAC %85, giriş dolumu 0,30 M, koşumda boş 0,37 M, yazma bekleme 0,79 M.
Aynı RTL, [[stalyanpu-ip-generator]] ile küçültülüp board'da iki kez daha ölçüldü: 32×16
(1024 MAC/çevrim) 9,92 M çevrim = 25,2 fps, 16×16 (512 MAC/çevrim) 17,92 M çevrim = 13,9 fps,
her ikisinde de T1..T5 ALL PASS. Dizi dışı sabit maliyet üç build'de de 174 DSP48. A2'nin
board'da hiç kazandırmaması kare süresinin paylaşımlı DDR yolunun etkin bant genişliğine
(~1,8 GB/s) bağlı olduğunu gösterdi; dedicated port bu bağı kaldırdı. Tam tasarım
zamanlaması kapalı: +0,038 ns (seed 6, port pinleri kısıtlı), LUT4 98,1k, FF 94,1k, DSP48
1223, RAM10 1606; bitstream `ip/stalyanpu/.data/build/bits/ti375_oob_hp_ddr4.bit`. Sim:
22/22 PASS, yolo alt kümesi 5/5, pytest 546. Kalan işler marj niteliğinde: stem L0 im2col
modu ve ağırlık tekrar akışının (20 MB/kare) azaltılması.

**CSR yolu.** M7 entegrasyonunda CSR yumuşak SoC [[efx-sapphire-fcu]] APB slave 0 üst
yarısında (`0xF810_4000`, `snpu_apb_cdc.v` köprüsü) idi; M8 ile birlikte NPU sert SoC
[[efx-sapphire-hpsoc-slb]] tarafından AXI-A `0xE800_0000` → `io_apbSlave_0`
`0xE810_0000` → `0xE810_4000` yoluyla sürülür ve `ti375_oob_top.v` HEAD bu bağlantıyı
açıkça belgeler. [[stalyanpu-synthesis-guide]] M7 tablosu ve [[stalyanpu-architecture]]
kontrol satırı hâlâ eski yolu anlatır; bu tablolar **eskidir**, güncel kaynak
[[stalyanpu-bringup-guide]] ve üst seviye RTL'dir ([[dual-soc-architecture]]).

## Kaynaklarda Geçişi
- [[stalyanpu-readme]]: hedef, belge dizini, kilometre taşı tablosu, durum bandı
- [[stalyanpu-architecture]]: dizi, veri akışı, bellek planı, kaynak ve performans tahmini, riskler
- [[stalyanpu-isa-descriptor]]: descriptor, CSR haritası, blob formatı
- [[stalyanpu-decision-record]]: OpenEye ölçümleri, cihaz tavanı, karar, M0 perf tablosu
- [[stalyanpu-synthesis-guide]]: Efinity sentez projeleri, DSP sütun kısıtı, M7 entegrasyonu, M8 zamanlama notları
- [[stalyanpu-verification-guide]]: sim ağacı, test listesi, DSP48 DUAL doğrulanan davranış
- [[stalyanpu-toolchain-guide]]: Python paketi, nicemleme semantiği, perf modeli
- [[stalyanpu-bringup-guide]]: board akışı, bulgular, 4,6 → 24,6 → 43,9 fps ölçümleri, dedicated port
- [[stalyanpu-accuracy-report]]: INT8 PTQ mAP sonuçları
- [[stalyanpu-perf-plan]]: M9 planı (A, A2, dedicated port) ve sonuçları

## İlişkiler
- [[openeye]]: yerini aldığı hızlandırıcı; karşılaştırma [[dnn-accelerator-options]]
- [[yolov8s]]: hedef model
- [[efx-dsp48]]: dizinin yapı taşı
- [[stalyanpu-toolchain]]: derleyici, referans model ve board araçları
- [[ti375c529]], [[ti375-devkit]]: hedef cihaz ve bring-up board'u
- [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]]: eski (M7) ve güncel CSR yolu
- [[lpddr4x-controller]]: dedicated 512-bit `axi_target0` portu
- [[snpu-axi-up512]]: 256-bit NPU portunu 512-bit DDR portuna bağlayan genişletici
- [[gdma]]: APB penceresini paylaştığı IP
- [[gdma-dnn]]: `MDNN` yuvasını devraldığı önceki DMA
- [[accelerator-control-plane-apb]]: CSR penceresinin bölme deseni
- [[efinity-toolchain]]: sentez ve programlama aracı
- [[stalyanpu-patent-disclosure]]: patent başvurusu için teknik açıklama belgesi ve çizimler
- Kavramlar: [[dsp-chain-systolic-array]], [[descriptor-isa]], [[int8-quantization-flow]], [[analytic-performance-model]], [[fpga-timing-closure]], [[ddr-port-pin-constraints]], [[board-bringup-flow]], [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[dual-soc-architecture]]
