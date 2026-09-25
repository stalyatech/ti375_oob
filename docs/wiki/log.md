# Wiki Günlüğü

## [2026-07-03] ingest | docs/help FMU mimari yardım sayfaları
- Kaynak: `docs/help/` (System Overview, Hardware Architecture, Software Architecture, Change Analysis, FMU Notes) — kök `CLAUDE.md` şemasına göre özümsendi.
- Oluşturulan kaynak sayfaları: [[system-overview]], [[hardware-architecture]], [[software-architecture]], [[change-analysis]], [[fmu-notes]]
- Oluşturulan varlık sayfaları: [[ti375c529]], [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]], [[vexriscv]], [[gtse-mac]], [[gdma]], [[gsdhc]], [[rtl8211f-phy]], [[nuttx]], [[lpddr4x-controller]], [[efinity-toolchain]]
- Oluşturulan kavram sayfaları: [[flight-management-unit]], [[dual-soc-architecture]], [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[ethernet-datapath]], [[boot-flow]], [[oob-to-fmu-transformation]]
- Oluşturulan karşılaştırma sayfaları: [[fcu-vs-hpsoc]]
- Oluşturulan/güncellenen çekirdek sayfalar: [[overview]], [[index]], `log.md`
- İşaretlenen sorunlar: [[gsdhc]] içinde `MHSDC` index yazım hatası (⚠️); belirsizlikler [[overview]] ve [[fmu-notes]] içinde (❓ MAC/IP sağlama, boot varyantı, bağlanmamış tutkal RTL).
- Not: Toplu (batch) ingest; çapraz referanslar tüm yeni sayfalar arasında iki yönlü kurulmuştur.

## [2026-09-15] ingest | OpenEye entegrasyonu ve StalyaNPU belgeleri (toplu)
- Kaynaklar: `docs/dnn-integration/` (README, gui-ip-steps, upstream-issue) ve `ip/stalyanpu/docs/` (9 belge + perf-plan). Kök `CLAUDE.md` şemasına göre iki paralel ajanla özümsendi; çapraz referanslar ve mevcut sayfa güncellemeleri elle birleştirildi.
- Oluşturulan kaynak sayfaları: [[dnn-integration-readme]], [[dnn-integration-gui-ip-steps]], [[openeye-upstream-issue]], [[stalyanpu-readme]], [[stalyanpu-architecture]], [[stalyanpu-isa-descriptor]], [[stalyanpu-decision-record]], [[stalyanpu-synthesis-guide]], [[stalyanpu-verification-guide]], [[stalyanpu-toolchain-guide]], [[stalyanpu-bringup-guide]], [[stalyanpu-accuracy-report]], [[stalyanpu-perf-plan]]
- Oluşturulan varlık sayfaları: [[openeye]], [[learning-chips-lab]], [[gdma-dnn]], [[stalyanpu]], [[yolov8s]], [[efx-dsp48]], [[stalyanpu-toolchain]], [[ti375-devkit]]
- Oluşturulan kavram sayfaları: [[hard-soc-fabric-interrupt-path]], [[accelerator-control-plane-apb]], [[file-driven-directed-testbench]], [[upstream-regression-bisect]], [[dsp-chain-systolic-array]], [[descriptor-isa]], [[int8-quantization-flow]], [[analytic-performance-model]], [[fpga-timing-closure]], [[board-bringup-flow]]
- Oluşturulan karşılaştırma: [[dnn-accelerator-options]]
- Güncellenen sayfalar: [[ti375c529]], [[efx-sapphire-hpsoc-slb]], [[efx-sapphire-fcu]], [[gdma]], [[lpddr4x-controller]], [[efinity-toolchain]], [[axi-interconnect-topology]], [[shared-dram-arbitration]], [[dual-soc-architecture]], [[overview]], [[index]]
- Tespit edilen çelişkiler: NPU CSR yolu yumuşak SoC (M7 belgeleri) ↔ sert SoC (M8 bring-up); `ti375_oob_top.v` HEAD sert SoC'u doğruluyor, sentez rehberi tablosu eski. DNN IRQ `userInterruptA` (gui-ip-steps) ↔ `userInterruptI` (README). 4'e 1 ↔ 5'e 1 anahtar (5'e 1 gerçeklenen). Zamanlama: M7 "+0,005 ns kapandı" ↔ M8 tam tasarım −0,2..−0,6 ns. Dedicated 256-bit DDR portu M7 ↔ M9. Perf modeli 7,6 M ↔ board 10,2 M çevrim.
- Belirsizlikler: OpenEye 2x2/64-bit yolunun `3531eb3`'te bile düşmesinin kök nedeni; upstream issue'nun açılıp açılmadığı; `hwcfg.py` sabitlerinin board ölçümüyle kalibre edilip edilmediği.

## [2026-09-15] update | StalyaNPU perf planı A adımı gerçeklendi
- Güncellenen sayfalar: [[stalyanpu-perf-plan]] (durum bölümü: 3 kanallı DMA, dolum makinesi, sim 17/17, sentez A/B)
- Kaynak dosyalar: `ip/stalyanpu/docs/perf-plan.md`, `verification-guide.md`, `synthesis-guide.md`, `architecture.md`, `isa-descriptor.md` (aynı gün güncellendi; kaynak sayfaları bir sonraki özümsemede yenilenecek)
- Belirsizlik: board'da gizlenecek dolum payı ölçülmedi

## [2026-09-15] update | StalyaNPU 43,9 fps: dedicated DDR portu
- Güncellenen sayfalar: [[stalyanpu-perf-plan]] (sonuç bölümü), [[overview]] (durum)
- Bulgular: A2 örtüşmesi board'da kazandırmadı (DDR bant genişliği sınırı ~1,8 GB/s); dedicated 512-bit port + `snpu_axi_up512` ile 5,69 M çevrim = 43,9 fps; hizasız wide burst'te port asılıyor
- Kaynak dosyalar aynı gün güncellendi (`bringup-guide.md`, `perf-plan.md`, `architecture.md`, `isa-descriptor.md`, `verification-guide.md`, `synthesis-guide.md`); kaynak sayfaları bir sonraki özümsemede yenilenecek

## [2026-09-15] ingest | StalyaNPU belgelerinin yeniden özümsenmesi (M9 sonucu)
- Yeniden yazılan kaynak sayfaları: [[stalyanpu-readme]], [[stalyanpu-architecture]], [[stalyanpu-isa-descriptor]], [[stalyanpu-verification-guide]], [[stalyanpu-synthesis-guide]], [[stalyanpu-bringup-guide]], [[stalyanpu-perf-plan]]
- Oluşturulan sayfalar: [[snpu-axi-up512]] (varlık), [[ddr-port-pin-constraints]] (kavram)
- Güncellenen sayfalar: [[stalyanpu]], [[lpddr4x-controller]], [[ti375-devkit]], [[stalyanpu-toolchain]], [[efinity-toolchain]], [[efx-sapphire-fcu]], [[yolov8s]], [[gdma]], [[gdma-dnn]], [[fpga-timing-closure]], [[board-bringup-flow]], [[analytic-performance-model]], [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[descriptor-isa]], [[dsp-chain-systolic-array]], [[dual-soc-architecture]], [[accelerator-control-plane-apb]], [[dnn-accelerator-options]], [[overview]], [[index]]
- Çözülen çelişkiler: NPU CSR yolu (HEAD sert SoC; sentez rehberi M7 tablosu eski), zamanlama (tam tasarım +0,038 ns, board doğrulandı), dedicated port (M9'da gerçeklendi, 512-bit; 256-bit x32 LPDDR4x'te desteklenmiyor)
- Kalan belirsizlikler: `hwcfg.py` DDR bant genişliği varsayımının yeniden kalibrasyonu; dedicated port sonrası descriptor profili; `tb_yolo_net` tam ağ koşumu; yumuşak SoC APB penceresinin fiziksel olarak kaldırılıp kaldırılmadığı

## [2026-09-15] ingest | StalyaNPU IP Generator (web arayüzü ve ipgen)
- Kaynak: `ip/stalyanpu/docs/ip-generator.md` (aynı gün yazıldı; `toolchain-guide.md` komut tablosu ve README güncellendi)
- Oluşturulan sayfalar: [[stalyanpu-ip-generator]]
- Güncellenen sayfalar: [[stalyanpu-toolchain]] (komutlar, GUI ve kütüphane eklemeleri), [[analytic-performance-model]] (ONNX adaptörü, DDR port presetleri, kaynak kestirimi), [[overview]], [[index]]
- Çözülen belirsizlik: `hwcfg.py` DDR varsayılanı 2,4 GB/s kaldı; ölçülen değerler `DDR_PORTS` presetlerinde (dedicated512 8 GB/s, shared128 1,8 GB/s)
- Kalan belirsizlik: kaynak ve performans kestirimi yalnız 32×32 geometride ölçümle doğrulanmış; diğer geometrilerde `efx_run map` sonucu yok

## [2026-09-16] update | IP Generator: Efinity projesine bağlama ve yeniden sentez bildirimi
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (4. adım, doğrulama), [[stalyanpu]] (geometri bağlama), [[index]]
- Kaynak değişiklikleri: `ti375_oob_top.v` `snpu_top` parametrelerini `rtl/snpu_config.vh` define'larından bağlar, `ti375_oob.xml` içine `rtl` include dizini, yeni `py/stalyanpu/project.py` ve `stalyanpu project status|apply|mark-built`, arayüzde 4. adım
- Doğrulama: üretilen include ile `efx_run map` referans build ile birebir aynı (LUT4 98 134, DSP48 1223, RAM10 1606); pytest 578
- Not: board veri yolu AXI_DW 256 ve WR_SLOT_WORDS 64 değerlerini sabitler; paylaşımlı port seçimi `apply` tarafından reddedilir

## [2026-09-16] update | IP Generator akış sırası yeniden düzenlendi
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (yeni adım sırası, rozetler, ölçüm bölümü), [[index]]
- Değişiklik: sayfa 1 hızlandırıcı, 2 FPGA donanımı (proje bağlama + sentez), 3 model, 4 board sırasına geçti; IP paketi dışa aktarma en alta isteğe bağlı bölüm oldu, Efinity ölçüm eylemi dosya listesinden çıkarılıp kendi düğmesine taşındı
- Eklenen: sayfa başında Accelerator/FPGA/Model uyum rozetleri, duruma göre değişen ana düğme metni, tek tek sentez aşamaları katlanır bölümde

## [2026-09-16] update | 32x16 dizisi board'da: 25,2 fps, model çapaları güncellendi
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (ikinci board çapası, kaynak tablosu), [[analytic-performance-model]] (32×16 çapası)
- Ölçüm: 32 zincir × 16 DSP (1024 MAC/çevrim), dedicated 512-bit port, YOLOv8s 640×384, 9 916 570 çevrim/kare = 25,2 fps, MAC %92,6, T1..T5 ALL PASS; model 24,3 fps (%3,8 karamsar)
- Kaynak (snpu_top): 686 DSP48, 1240 RAM10, 81,0k XLR; kestirim DSP'de bire bir, XLR'de %2,8 yüksek
- Kod: `perf/calibration.py` çapaları geometriye göre eşleştirir, `perf/resources.py` dizi fabric maliyetini zincir uzunluğuna göre ayırır; arayüzde DDR bağlantısı port adıyla gösterilir

## [2026-09-16] update | Kaynak çubukları projenin kendi raporundan, ölçüm başlıkta
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (kaynak çubukları, ölçüm gösterimi), `ip/stalyanpu/docs/ip-generator.md`
- Değişiklik: 1. adımdaki kaynak çubukları iki parçalı (hızlandırıcı + projenin geri kalanı); ikinci parça `project.resource_report()` ile `outflow/ti375_oob-hierarchical_stats.rpt` raporundan okunur, araçta sabit tutulmaz
- Ölçülmüş yapılandırmada büyük sayı artık ölçümün kendisi ("measured on the board"), model çıktısı notta ve "Model estimate" kutularında; dizi listesindeki ölçüm etiketi kaldırıldı
- Dizi dışındaki 174 DSP48'in hızlandırıcının sabit maliyeti olduğu belgelendi (epilog 128, sequencer 22, rd_dma 18, agen 5, maxpool 1)

## [2026-09-16] update | 16x16 dizisi board'da 13,9 fps, model ek yükleri yeniden ayarlandı
- Güncellenen sayfalar: [[analytic-performance-model]] (üçüncü çapa ve yeni sabitler), [[stalyanpu-ip-generator]] (üçüncü geometri), [[stalyanpu]] (ölçüm listesi)
- Ölçüm: 16 zincir × 16 DSP (512 MAC/çevrim), dedicated 512-bit port, YOLOv8s 640×384, 17 919 410 çevrim/kare = 13,9 fps, MAC %96,1, T1..T5 ALL PASS
- Bulgu: modelin dizi terimi üç koşumda da board'un MAC sayacına eşit, sapma tümüyle sabit ek yüklerdeydi
- Kod: `t_pass` 40→10, `t_tile` 150→200, `t_op` 500→4000; `shared128` preseti 1,8→2,0 GB/s; sapmalar %+1,3 / %−0,5 / %−1,1 / %+0,9
- Kaynak (snpu_top): 430 DSP48, 1036 RAM10, 68,8k XLR; üçüncü build kaynak modeline çapa olarak eklendi

## [2026-09-16] update | Arayüz tek sayfadan sol menülü adım sayfalarına geçti
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (yerleşim), `ip/stalyanpu/docs/ip-generator.md`
- Değişiklik: adımlar artık soldaki menüden seçilen ayrı sayfalar; aşağı kaydırma gerekmiyor, board ve export adımları katlanır bölüm olmaktan çıktı
- Her sayfa Accelerator/FPGA/Model rozetleriyle açılıyor; menüdeki noktalar aynı durumu tekrarlıyor ve koşum sürerken yanıp sönüyor
- Seçili adım adres çubuğunda (`#accelerator`, `#fpga`, `#model`, `#board`, `#export`) ve kaydedilen durumda tutuluyor

## [2026-09-16] lint | Ek yük sabitleri sonrası eskiyen sayıların taranması
- Güncellenen sayfalar: [[analytic-performance-model]], [[stalyanpu-ip-generator]], [[stalyanpu-decision-record]], [[stalyanpu-toolchain]]
- Bulunan sorunlar: 1 yanlış iddia (hwcfg varsayılanları hâlâ 40/150/500 yazıyordu), 2 eski projeksiyon tablosu, 2 eski test sayısı
- Düzeltilen: varsayılanlar 10/200/4000 oldu, M0 tablolarına yeniden ayarlama notu eklendi, doğrulama notu 589 test ve model 44,5 fps oldu
- Kontrol: 62 sayfa, kırık bağlantı yok, yetim sayfa yok
- Kaynak dosyalar aynı gün güncellendi: `ip/stalyanpu/docs/toolchain-guide.md`, `decision-record.md`

## [2026-09-16] query | StalyaNPU patent teknik açıklama belgesi
- Yanıt kaydedildi: [[stalyanpu-patent-disclosure]]
- Üretilen dosyalar: `ip/stalyanpu/docs/patent/stalyanpu-technical-disclosure.docx`, `ip/stalyanpu/docs/patent/figures/` (12 SVG + 12 PNG)
- Güncellenen sayfalar: [[stalyanpu]] (ilişkilere belge bağlantısı); `ip/stalyanpu/docs/README.md` belge tablosuna satır eklendi
- Ham kaynakla doğrulama: okuma DMA kanal ataması (0 denetim, 1 ağırlık, 2 dolum) ve sert SoC CSR yolu RTL ile teyit edildi; yeni çelişki bulunmadı

## [2026-09-16] update | Bir FPGA'da birden çok StalyaNPU: sistem tanımı ve System sayfası
- Oluşturulan sayfalar: [[multi-instance-npu]]
- Güncellenen sayfalar: [[stalyanpu]] (ilişki), [[stalyanpu-ip-generator]] (bağlantı)
- Kaynak dosya: `ip/stalyanpu/docs/system-integrator.md` (yeni)
- Bulgu: YOLOv8s 640x384 bir örnekte en az p_max 512 ve 256 KB giriş tamponu ister; 64 KB ile ilk katman derlenemedi
- Ölçüm: tek örnekli sistemin map çıktısı sistem öncesiyle aynı; 16x16 + 16x8 sisteminde map DSP48 757 (kestirim 757), RAM10 2081 (kestirim 2164)
- Build: 16x16 + 16x8 sistemi pnr ve pgm PASS, 250 MHz setup +0,032 ns, hold +0,023 ns; wiki sayfasına eklendi

## [2026-09-16] update | Çok örnekli sistemde örnek başına model, kalibrasyon ve derleme
- Güncellenen sayfalar: [[multi-instance-npu]] (modeller bölümü, [[int8-quantization-flow]] ve [[descriptor-isa]] bağlantıları)
- Kaynak dosya: `ip/stalyanpu/docs/system-integrator.md` (Modeller bölümü, E014, W109)
- Ölçüm: YOLOv8s tek kalibrasyon, 16x16 blob 11,3 MB, 16x8 blob 22,4 MB, ikisi `interp == runner` OK

## [2026-09-16] update | IP generator arayüzü sistem tanımı etrafında yeniden düzenlendi
- Güncellenen sayfalar: [[stalyanpu-ip-generator]] (özet, düzen notu, eski adım paragrafları için çelişki işareti), [[multi-instance-npu]] (web arayüzü, modeller, bağlantı)
- Kaynak dosyalar: `ip/stalyanpu/docs/ip-generator.md` (baştan yazılan adım bölümleri), `system-integrator.md` (web arayüzü bölümü), `docs/README.md`
- Değişiklik: menü 1 Design, 2 Models, 3 FPGA hardware, 4 Board; Accelerator sayfası seçili örneğin sekmelerine taşındı, rozetler Design/Models/FPGA/Board
- Tespit edilen çelişki: eski Accelerator sayfası diyagramdan bağımsız DDR bant genişliği kullanıyordu; kestirim artık örneğin bağlı olduğu porttan geliyor

## [2026-09-16] update | IP generator: model aşamaları, menü noktaları, FPGA karşılaştırması
- Güncellenen kaynak dosya: `ip/stalyanpu/docs/ip-generator.md` (Models zinciri, rozet notu, FPGA paneli)
- Değişiklik: model hazırlama tek satır yerine model başına Lower/Calibrate, örnek başına Compile ve Summary satırlarıyla koşuyor (`system models --step`)
- Değişiklik: FPGA paneli taslak ile projeyi örnek örnek karşılaştırıyor; tek örnekli taslakta projenin iki örneği "removed in the design" olarak görünüyor
- Değişiklik: Models noktası ilk açılışta turuncu, Board noktası koşulmamışken gri

## [2026-09-16] update | Tek örnekli sistem arayüzle board'da doğrulandı
- Güncellenen sayfalar: [[multi-instance-npu]] (örnekler, belirsizlik notu daraltıldı)
- Ölçüm: 16x16 tek örnek, map DSP48 455 / RAM10 1402, pnr setup +0,030 ns, board S1..S6 ALL PASS, 13,9 fps (17 919 489 çevrim/kare)
- Bitstream kopyası: `ip/stalyanpu/.data/build/bits/ti375_oob_sys_16x16_single.bit`

## [2026-09-16] update | İki örnekli sistem board'da doğrulandı
- Güncellenen sayfalar: [[multi-instance-npu]] (örnekler, belirsizlik notu paylaşımlı yuva çekişmesine daraltıldı)
- Ölçüm: 16x16 axi_target0 + 16x8 MDNN, S1..S6 ALL PASS; npu0 13,9 fps, npu1 6,8 fps, birlikte 20,8 fps (kestirim 20,6)
- Build: map DSP48 757 / RAM10 2081, pnr setup +0,032 ns, hold +0,023 ns; bitstream `ip/stalyanpu/.data/build/bits/ti375_oob_sys_16x16_16x8_gui.bit`
- Bulgu: pythonw altında `system models` alt süreç çıktısı iş loguna düşmüyordu; çıktı artık boru üzerinden aktarılıyor. Referans denetimi örnek başına yaklaşık 2 s sürüyor

## [2026-09-16] update | S3 axi_target1 incelemesi ve S4 kalibrasyon çapaları
- Güncellenen sayfalar: [[multi-instance-npu]] (axi_target1 kullanılamaz, peri.xml denetimi), [[analytic-performance-model]] (dördüncü çapa 16×8 paylaşımlı), [[efx-sapphire-hpsoc-slb]] (AXI hedef 1 ilişkisi)
- Kaynak dosyalar: `ip/stalyanpu/docs/system-integrator.md`, `ip-generator.md`, `decision-record.md`
- Bulgu: Efinity kuralı `ddr_rule_axi_1_qcrv32` sert SoC varken DDR_0 AXI hedef 1'i reddeder; planın S3 adımı (ikinci dedicated port) bu kartta yapılamaz
- Ölçüm: 16×8 MDNN 36,23 M çevrim, 6,87 fps, model 6,86; 8'lik zincir 17,2 XLR/DSP

## [2026-09-16] lint | Commit öncesi wiki güncelliği
- Güncellenen sayfalar: [[overview]] (10. madde: çok örnekli sistem, board sonuçları, axi_target1 kısıtı; açık sorular), [[stalyanpu-ip-generator]] (model aşamaları, FPGA karşılaştırması, board doğrulaması)
- Kontrol: kırık wiki bağlantısı yok

## [2026-09-16] query | Örnek başı sabit DSP maliyeti: ortak havuz analizi ve azaltma
- Yanıt kaydedildi: [[stalyanpu-dsp-overhead-sharing]]
- Güncellenen sayfalar: [[efx-dsp48]] (residual supabı uygulandı), [[stalyanpu]], [[multi-instance-npu]] (iki örnekli karışım 46,1 fps kestirimi), [[analytic-performance-model]] (yeni kaynak çapası)
- Kaynak dosyalar: `ip/stalyanpu/docs/synthesis-guide.md`, `ip-generator.md`, `system-integrator.md`, `isa-descriptor.md`
- Ölçüm: `syn/top` 32×32 map 1098 DSP48 / 1302 RAM10 / 88,4k XLR (önce 1198 / 1269 / 102,9k), pnr 255,3 MHz, setup +0,083 ns; dizi dışı sabit 174 → 74 DSP48
- Doğrulama: sim 26/26 PASS, pytest 627; üst proje build'i ve board testi yapılmadı

## [2026-09-17] update | Patent teknik açıklama belgesi sürüm 1.1
- Güncellenen sayfalar: [[stalyanpu-patent-disclosure]], index
- Kaynak dosyalar: `ip/stalyanpu/docs/patent/stalyanpu-technical-disclosure.docx`, `figures/fig01, fig02, fig08, fig12` (güncellendi), `figures/fig13-cnn-primer` (yeni, renkli)
- İçerik: çoklu örnek sistemi (6.1, 6.15, 7.6), tablo tabanlı epilog (6.7), sabit DSP maliyeti 174 → 74, buluş grubu E, Ek A

## [2026-09-24] ingest | StalyaVPU karar kaydı
- Oluşturulan sayfalar: [[stalyavpu-decision-record]], [[stalyavpu]]
- Güncellenen sayfalar: [[overview]] (11. madde, açık sorular), [[stalyanpu]], [[lpddr4x-controller]], [[gsdhc]], [[multi-instance-npu]], [[axi-interconnect-topology]] (güncel yuva dağılımı), [[shared-dram-arbitration]] (codec yükü), index
- Kaynak dosyalar: `ip/stalyavpu/docs/decision-record.md`, `architecture.md`, `performance-targets.md`
- Eski iddia düzeltildi: [[axi-interconnect-topology]] ve [[shared-dram-arbitration]] yuva 4'ü boş `MCODEC` olarak anlatıyordu; HEAD'de `MEMMC` (eMMC), `MDNN` npu1
- Ölçüm: 2026-09-24 build'i RAM10 2305/2688, DSP48 813/1344, XLR 220 760/362 880; npu0 `p_max` 512 + `ibuf` 256 KB model 24,9 fps
- Test seti: 11 üretilmiş akış (1080p 7,3/18,3/38,8 Mbps), conformance 98/176 akış kapsamda (interlaced 66, FMO 4, Extended 6, monokrom 2 dışarıda); [[stalyavpu]] durum satırı

## [2026-09-24] update | StalyaVPU V1: H.264 referans modeli
- Güncellenen sayfalar: [[stalyavpu]] (V1 durumu)
- Kaynak dosyalar: `ip/stalyavpu/docs/architecture.md` (descriptor, referans model), `performance-targets.md` (model tahmini), `verification-guide.md`
- Ölçüm: conformance 98/98 bit bit (13 996 kare), üretilmiş küçük akışlar 8/8; perf modeli 1080p 20 Mbps ortalama 213 çevrim/MB, 40 Mbps 344, I resminde 846 (CABAC sınırlı)
- Bulgu: FFmpeg'in 4x4 normAdjust tablosunun sütun sırası standarttan farklı (çift-çift, karışık, tek-tek); ilk uyumsuzluğun kaynağı buydu

## [2026-09-25] update | StalyaVPU V2: RTL ön uç
- Güncellenen sayfalar: [[stalyavpu]] (V2 durumu)
- Kaynak dosyalar: `ip/stalyavpu/docs/frontend.md`
- Ölçüm: tb_bsr, tb_cabac (1 014 826 bin), tb_cavlc (35 338 blok), tb_syn (52 slice, 9306 MB), tb_top (12 resim) modelle aynı; sentez 166,9 MHz, 18,9k XLR, 25 RAM10, 1 DSP
- Bulgu: Efinity 2025.2 eşleyicisi küçük dizilere kısmen değişken adresli yazımda çöküyor; diziler düz vektöre çevrildi
