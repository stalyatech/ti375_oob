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
