# Karar kaydı: OpenEye yerine StalyaNPU

Tarih: 2026-08-28. Karar: mevcut OpenEye hızlandırıcısı optimize edilmez; yeni dalda
(`stalya-fmu_v2.0-npu`) sıfırdan INT8 CNN hızlandırıcısı **StalyaNPU** tasarlanır.
İsim seçimi: "OpenCore" önerisi, Hackintosh OpenCore önyükleyicisi ve OpenCores.org ile
çakıştığı için elendi.

## Hedef

YOLOv8s, 1080p kaynak videodan **640×384 letterbox** çıkarım, **30 fps**, INT8.
Gerek: 8,58 GMAC/kare (perf modeli tablosu; 640×640'ta 14,3 GMAC, Ultralytics'in 28,6 GFLOP
değeriyle uyumlu) → **258 GMAC/s sürekli**. Uzatma: 640×640'ta ≥ 20 fps.

Doğal 1920×1088 çıkarım (73 GMAC/kare, 2,2 TMAC/s) bu cihazın teorik tavanının (aşağıda)
3,7 katı üzerindedir ve hedeften çıkarılmıştır.

## OpenEye ölçümleri (bu depo, 2026-08-27 bitstream'i)

Kaynaklar: `outflow/ti375_oob.place.rpt`, `outflow/ti375_oob-hierarchical_stats.rpt`
(satır 388 `u_openeye`, 435 `OpenEye_Parallel`), `ip/OpenEye/hdl/OpenEye_FPGA.v:104-158`,
`ip/OpenEye/fpga/hdl/open_eye_axi_v1_0.v:8-15`.

| Ölçüt | OpenEye bugün | OpenEye üst sınır | Gerek |
|-------|---------------|-------------------|-------|
| Geometri | 2×2 küme × 3×4 PE = 48 PE, `PARALLEL_MACS=2` | 8×2 küme = 192 PE (`CLUSTER_COLUMNS=2` Python'da sabit, `PARALLEL_MACS` 4 RTL'de yok) | |
| MAC/çevrim | 96 | 384 | ~2048 |
| Saat | 100 MHz (Fmax 114,6) | ~115 MHz | 250 MHz |
| Tepe | 9,6 GMAC/s → **0,67 fps** (sıfır ek yük) | ~40 GMAC/s → ~2,8 fps | 258 GMAC/s |
| Kaynak | 114 853 XLR, **1802/2688 RAM10**, 152 DSP | 4× küme RAM10'a sığmaz (psum tamponları tek başına 1024 blok) | |
| Veri yolu | Tek 64-bit AXIS @100 MHz = 0,8 GB/s; katman başına tam yeniden yükleme | | |
| Ölçülen | Referans katman (8 filtre 3×3, 8×8×4): 192 hesap çevrimine karşı ~720 veri yolu çevrimi, DMA'ya 3,7× bağlı | | |
| Op desteği | Conv, Dense, ReLU/LeakyReLU, 2×2 pool; padding `same` simetrik; `QUANT_AMOUNT=32` → ≤32 filtre/aktarım | | SiLU, Add, Concat, Split, Upsample ×2, SPPF MaxPool k5 s1 |
| Bilinen hatalar | 10×10×8 ve üstü girişte çıktı beat'lerinin yarısı; upstream `d19314a` ve `ff4f99f` regresyonları (bkz. `docs/dnn-integration/upstream-issue.md`) | | |

Sonuç: hedef, OpenEye'ın mimari tavanının **>45× (bugünkü yapıya göre >380×)** üstündedir.
Row-stationary/NoC mimarisi, RAM10 yoğunluğu ve eksik op kümesiyle bu fark kapatılamaz.

## Cihaz tavanı (Ti375C529, C4)

`outflow/ti375_oob.place.rpt`: 362 880 XLR, 2688 RAM10 (10 Kb), **1344 DSP48**, 32 GBUF.
OpenEye ve `gDMA_dnn` çıkınca boş: ~289k XLR, ~2359 RAM10, ~1319 DSP (yumuşak FCU SoC'u
56k XLR / 237 RAM10 / 25 DSP ile kalır).

`EFX_DSP48` (sim modeli `C:\Programs\Efinity\2025.2\sim_models\verilog\efx_dsp48.v`):
**DUAL modu** = 11×10 ve 8×8 iki bağımsız çarpan, iki 24-bit biriktirici lane, 48-bit
CASCIN/CASCOUT iki lane'i birlikte taşır → **DSP başına 2 INT8 MAC**. Bu davranış
`sim/stalyanpu/unit/tb_dsp_mac.sv` ve `tb_pe_chain.sv` ile vendor modeline karşı doğrulandı
(silikon doğrulaması M5 öncesi smoke test).

Teorik tepe: 1024 DSP × 2 × 250 MHz = **512 GMAC/s**. 640×384 hedefi için %50 kullanım
yeter; 640×640 için %84 (bu yüzden 640×640 hedefi 20 fps).

DDR: LPDDR4x x32 @1600 MT/s = 6,4 GB/s pinlerde. Fabric bugün tek 128-bit @250 MHz porttan
(4,0 GB/s, 5 master paylaşır) çıkar. Hard DDR denetleyicisinin `axi_target0/1` portları
(`ti375_oob.peri.xml:531,575`) kapalı; 256-bit seçenekli.

## StalyaNPU kararları

Ayrıntı [architecture.md](architecture.md). Özet: 32 IC × 64 OC ağırlık-sabit sistolik
kaskad dizisi (1024 DSP48 DUAL, 2048 MAC/çevrim @250 MHz), DSP içinde birikim yok
(24-bit lane taşmaz), 32-bit RAM10 biriktirici (1024 px × 64 OC × 2 bank), birleşik epilog
(bias, u16 requant, 256'lık SiLU LUT, residual), NC32HW tensör düzeni ile sıfır kopya
Concat/Split/Upsample, descriptor tabanlı sequencer, kare başına 1 IRQ, kendi AXI4
DMA'ları, Faz 1'de mevcut `MDNN=3` 128-bit yuvası ve `io_ddrMasters_0_clk` (250 MHz).

## M0 performans modeli sonucu ve kapı değerlendirmesi

`python -m stalyanpu perf --hwcfg full2048` (t_pass 40, t_tile 150, t_op 500, stem
baseline 8 kanal dolgulu, CPU kuyruğu 4 ms örtüşük):

| Etkin DDR bant genişliği | Çevrim/kare | Kare süresi | fps | Dizi kullanımı |
|-------------------------:|------------:|------------:|----:|---------------:|
| 1,6 GB/s | 10,40 M | 41,6 ms | 24,0 | %40 |
| 2,0 GB/s | 8,65 M | 34,6 ms | 28,9 | %49 |
| **2,4 GB/s (paylaşımlı port planlama değeri)** | **7,60 M** | **30,4 ms** | **32,9** | **%55** |
| 3,2 GB/s | 6,68 M | 26,7 ms | 37,4 | %63 |
| 4,5 GB/s (dedicated 256-bit port) | 6,12 M | 24,5 ms | 40,8 | %68 |
| 8,0 GB/s (sınırsız) | 5,67 M | 22,7 ms | 44,1 | %74 |

640×640 @4,5 GB/s: 25,3 fps. 200 MHz @2,4 GB/s: 29,3 fps. DDR trafiği 63,8 MB/kare
(11,1 MB benzersiz ağırlık; geri kalanı aktivasyon ve halo/ağırlık yeniden okuması).

**Kapı değerlendirmesi:** 30 fps hedefi paylaşımlı port varsayımıyla tutuyor (32,9 fps)
ama plandaki "%67 bütçe" marjı **sağlanmıyor** (bütçenin %91'i). Model, tasarımı
**DDR'a bağlı** gösteriyor: 2,4 GB/s'de katmanların çoğu (L0/L2 grubu, tüm 1×1'ler, SPPF)
veri yolu sınırında; saf hesap sınırı 44 fps.

Buna bağlı plan düzeltmeleri:
1. Dedicated 256-bit `axi_target0` portu M9'dan **M7 entegrasyonuna** çekilir (model: +8 fps).
2. Erken katman füzyonu (L0→L1→L2 aktivasyonları 512 KB ibuf'a sığar: 96×160×32 = 491 KB)
   M9 optimizasyonu olarak listelenir; L0/L1/L2 grubu 17 MB trafik taşıyor.
3. Stem `L0_MODE` (im2col-27) Faz 1.5'te kalır (L0 tek başına 601 kçevrim, %8).
4. `p_max` 1024 → 2048 seçeneği (halo yeniden okumasını azaltır, +412 RAM10) M5 sentez
   sonuçlarına göre değerlendirilir.

Model kalibrasyonu M6 (sim) ve M8 (donanım sayaçları) kapılarıyla yapılır; sabitler
`hwcfg.py` içindedir.
