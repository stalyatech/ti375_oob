---
title: "Kaynak: Karar Kaydı (OpenEye yerine StalyaNPU)"
type: source
source_file: "ip/stalyanpu/docs/decision-record.md"
author: "volvox"
date: 2026-08-28
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, openeye, decision, performance, dsp48, ddr]
---

# Kaynak: Karar Kaydı (OpenEye yerine StalyaNPU)

## Özet
2026-08-28 tarihli karar: mevcut [[openeye]] hızlandırıcısı optimize edilmez; yeni dalda
(`stalya-fmu_v2.0-npu`) sıfırdan INT8 CNN hızlandırıcısı [[stalyanpu]] tasarlanır. Belge
hedefi, OpenEye'ın ölçülen sayılarını ve üst sınırını, Ti375C529 cihaz tavanını, DSP48 DUAL
modunun MAC sayımını, StalyaNPU'nun temel kararlarını ve M0 performans modelinin kapı
değerlendirmesini kaydeder. İsim seçiminde "OpenCore" önerisi çakışma nedeniyle elenmiştir.

## Temel Çıkarımlar
- Hedef: [[yolov8s]], 640×384 letterbox, 30 fps, INT8 → 8,58 GMAC/kare, 258 GMAC/s sürekli. Doğal 1920×1088 (73 GMAC/kare) hedeften çıkarıldı.
- OpenEye bugün 96 MAC/çevrim @100 MHz = 9,6 GMAC/s → 0,67 fps; mimari üst sınır ~40 GMAC/s → ~2,8 fps. Hedef üst sınırın >45 katı.
- Cihaz tavanı: 1344 [[efx-dsp48]], DUAL modda DSP başına 2 INT8 MAC; 1024 DSP × 2 × 250 MHz = **512 GMAC/s** teorik tepe.
- DDR: LPDDR4x x32 @1600 MT/s = 6,4 GB/s pinlerde; fabric bugün tek 128-bit @250 MHz porttan (4,0 GB/s, 5 master paylaşır).
- M0 modeli 2,4 GB/s'de 32,9 fps; 30 fps kapısı tutuyor ama "%67 bütçe" marjı sağlanmıyor; tasarım DDR'a bağlı.

## Detaylı Notlar
**OpenEye ölçümleri.** Geometri 2×2 küme × 3×4 PE = 48 PE, `PARALLEL_MACS=2`; 100 MHz
(Fmax 114,6); 114 853 XLR, 1802/2688 RAM10, 152 DSP. Veri yolu tek 64-bit AXIS @100 MHz
(0,8 GB/s), katman başına tam yeniden yükleme; referans katmanda 192 hesap çevrimine karşı
~720 veri yolu çevrimi (DMA'ya 3,7× bağlı). Op desteği Conv, Dense, ReLU/LeakyReLU, 2×2 pool
ile sınırlı; SiLU, Add, Concat, Split, Upsample, SPPF yok. Ölçeklenmiş 8×2 küme = 192 PE
seçeneği bile RAM10'a sığmaz (psum tamponları tek başına 1024 blok). Bilinen upstream
regresyonları vardır. Bu satırlar [[dnn-accelerator-options]] karşılaştırmasının veri
kaynağıdır.

**Cihaz tavanı.** [[ti375c529]] C4: 362 880 XLR, 2688 RAM10, 1344 DSP48, 32 GBUF. OpenEye ve
`gDMA_dnn` çıkınca boş: ~289k XLR, ~2359 RAM10, ~1319 DSP (yumuşak FCU SoC'u 56k XLR /
237 RAM10 / 25 DSP ile kalır). `EFX_DSP48` DUAL modu = 11×10 ve 8×8 iki bağımsız çarpan,
iki 24-bit biriktirici lane, 48-bit CASCIN/CASCOUT iki lane'i birlikte taşır. Bu davranış
`tb_dsp_mac.sv` ve `tb_pe_chain.sv` ile vendor modeline karşı doğrulandı. 640×384 için %50
kullanım yeter; 640×640 için %84 (bu yüzden 640×640 hedefi 20 fps).

**DDR ve port.** Sert DDR denetleyicisinin `axi_target0/1` portları
([[lpddr4x-controller]]) kapalı; 256-bit seçenekli. Paylaşımlı port planlama değeri 2,4 GB/s
([[shared-dram-arbitration]]).

**StalyaNPU kararları.** 32 IC × 64 OC ağırlık-sabit sistolik kaskad dizisi
([[dsp-chain-systolic-array]]), DSP içinde birikim yok, 32-bit RAM10 biriktirici, birleşik
epilog (bias, u16 requant, SiLU LUT, residual), NC32HW ile sıfır kopya Concat/Split/Upsample,
descriptor tabanlı sequencer ([[descriptor-isa]]), kare başına 1 IRQ, kendi AXI4 DMA'ları,
Faz 1'de `MDNN=3` 128-bit yuvası ve `io_ddrMasters_0_clk` (250 MHz).

**M0 performans modeli.** [[analytic-performance-model]] tablosu (t_pass 40, t_tile 150,
t_op 500, stem 8 kanal dolgulu, CPU kuyruğu 4 ms örtüşük):

| Etkin DDR | Çevrim/kare | fps | Kullanım |
|----------:|------------:|----:|---------:|
| 1,6 GB/s | 10,40 M | 24,0 | %40 |
| 2,0 GB/s | 8,65 M | 28,9 | %49 |
| 2,4 GB/s | 7,60 M | 32,9 | %55 |
| 3,2 GB/s | 6,68 M | 37,4 | %63 |
| 4,5 GB/s | 6,12 M | 40,8 | %68 |
| 8,0 GB/s | 5,67 M | 44,1 | %74 |

DDR trafiği 63,8 MB/kare (11,1 MB benzersiz ağırlık). 200 MHz @2,4 GB/s: 29,3 fps.

**Plan düzeltmeleri.** (1) Dedicated 256-bit `axi_target0` portu M9'dan M7'ye çekilir
(model +8 fps). (2) Erken katman füzyonu (L0→L2 aktivasyonları 512 KB ibuf'a sığar) M9'a.
(3) Stem `L0_MODE` Faz 1.5'te kalır. (4) `p_max` 1024 → 2048 seçeneği M5 sentez sonuçlarına
göre. Model kalibrasyonu M6 (sim) ve M8 (donanım sayaçları) kapılarıyla.

> ❓ **Belirsiz:** Dedicated port "M7'ye çekilir" kararı sonraki belgelerde
> gerçekleşmemiştir; M7 paylaşımlı yuvayla bitmiş, port [[stalyanpu-readme]]'de M9'da ve
> [[stalyanpu-bringup-guide]]'da aday listesinde kalmıştır.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[openeye]], [[yolov8s]], [[efx-dsp48]], [[ti375c529]], [[lpddr4x-controller]], [[efx-sapphire-fcu]]
- İlgili kavramlar: [[dsp-chain-systolic-array]], [[descriptor-isa]], [[analytic-performance-model]], [[shared-dram-arbitration]], [[axi-interconnect-topology]]
- Karşılaştırma: [[dnn-accelerator-options]]
- Destekleyen kaynaklar: [[stalyanpu-architecture]], [[stalyanpu-readme]]

## Alıntılar
- "Teorik tepe: 1024 DSP × 2 × 250 MHz = 512 GMAC/s. 640×384 hedefi için %50 kullanım yeter; 640×640 için %84" (satır 50-51)
- "Sonuç: hedef, OpenEye'ın mimari tavanının >45× (bugünkü yapıya göre >380×) üstündedir." (satır 35)
- "30 fps hedefi paylaşımlı port varsayımıyla tutuyor (32,9 fps) ama plandaki '%67 bütçe' marjı sağlanmıyor (bütçenin %91'i)." (satır 83-84)
