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
