# Wiki Dizini

Son güncelleme: 2026-09-16

Bu wiki, `docs/help/` FMU mimari yardım sayfalarının, `docs/dnn-integration/` OpenEye
entegrasyon notlarının ve `ip/stalyanpu/docs/` StalyaNPU belgelerinin [[overview|genel bakış]],
kaynak, varlık, kavram ve karşılaştırma sayfalarına ayrıştırılmış halidir. Şema: kök
`CLAUDE.md`.

## Kaynaklar
- [[system-overview]] — Cihaz, toolchain, çift-SoC konsepti, blok diyagramı (2026-07-03) [overview, soc]
- [[hardware-architecture]] — RTL entegrasyonu, AXI anahtarlar, TSE/DMA/SD, tutkal RTL (2026-07-03) [hardware, rtl]
- [[software-architecture]] — Sapphire BSP'leri, bellek haritaları, önyükleme, NuttX, uygulamalar (2026-07-03) [software, bsp]
- [[change-analysis]] — OOB → FMU dönüşümü, commit + çalışma-ağacı değişiklikleri (2026-07-03) [change-log]
- [[fmu-notes]] — Mevcut durum gözlemleri ve işaretlenen sorunlar (2026-07-03) [fmu, issues]
- [[dnn-integration-readme]] — OpenEye DNN + codec entegrasyon devri, gerçeklenen son durum ve durdurma notu (volvox, 2026-08-28) [dnn, openeye, interrupt, historical]
- [[dnn-integration-gui-ip-steps]] — Efinity GUI'de üretilen 3 DNN IP'sinin parametreleri; tarihsel, adımlar tamamlandı (volvox, 2026-08-27) [dnn, efinity, ip-generation, historical]
- [[openeye-upstream-issue]] — OpenEye upstream main'in bozukluğunu bildiren issue taslağı ve bisect zinciri (volvox, 2026-08-27) [openeye, bisect, cocotb]
- [[stalyanpu-readme]] — StalyaNPU giriş belgesi, kilometre taşları M0..M9, board'da 43,9 fps durumu (volvox, 2026-09-15) [stalyanpu, milestones]
- [[stalyanpu-architecture]] — Dizi, veri akışı, döşeme çift tamponu ve boşaltma örtüşmesi, 3 kanallı DMA, bellek planı (volvox, 2026-09-15) [stalyanpu, architecture, dsp48]
- [[stalyanpu-isa-descriptor]] — 128 B descriptor, opcode/bayraklar, CSR haritası (DBG0/DBG1/DBG6), blob formatı (volvox, 2026-09-15) [stalyanpu, isa, csr]
- [[stalyanpu-decision-record]] — OpenEye ölçümleri, cihaz tavanı, StalyaNPU kararı, M0 perf tablosu (volvox, 2026-08-28) [stalyanpu, openeye, decision]
- [[stalyanpu-synthesis-guide]] — Efinity sentez projeleri, DSP sütun kısıtı, M7..M9 zamanlama kapanışı, dedicated port build'i (volvox, 2026-09-15) [stalyanpu, synthesis, timing]
- [[stalyanpu-verification-guide]] — Sim ağacı, test listesi U1..U5/L/N/Y, çift tampon çevrim tablosu, DSP48 DUAL semantiği (volvox, 2026-09-15) [stalyanpu, verification]
- [[stalyanpu-toolchain-guide]] — py/stalyanpu paketi, komutlar, nicemleme semantiği, perf formülü (volvox, 2026-09-14) [stalyanpu, toolchain, python]
- [[stalyanpu-bringup-guide]] — Ti375C529 kitinde sert SoC bring-up, 4,6 → 43,9 fps ölçüm tablosu, dedicated DDR portu ve pin kısıtları (volvox, 2026-09-15) [stalyanpu, bringup, board]
- [[stalyanpu-accuracy-report]] — INT8 PTQ kalibrasyon taraması, COCO mAP 44,86 → 44,07 (volvox, 2026-08-28) [stalyanpu, quantization, coco]
- [[stalyanpu-perf-plan]] — 24,6 → 30 fps planı ve sonucu: çift tampon, A2, zamanlama, dedicated DDR portu ile 43,9 fps; L0 modu marj işi (volvox, 2026-09-15) [stalyanpu, performance, plan]
- [[stalyanpu-ip-generator]] — Yerel web arayüzü (sol menüden seçilen adım sayfaları), `ipgen` ve `project`: geometri/saat/DDR seçimiyle fps ve kaynak kestirimi, model hazırlama, IP paketi, Efinity projesine bağlama ve yeniden sentez bildirimi, board adımları (volvox, 2026-09-16) [stalyanpu, gui, ip-generator]

## Varlıklar
- [[ti375c529]] — Efinix Titanium FPGA (product) [source_count: 5]
- [[efx-sapphire-fcu]] — Yazılım Sapphire SoC, uçuş uygulama işlemcisi (product) [source_count: 7]
- [[efx-sapphire-hpsoc-slb]] — Donanım blok SoC, ev-işleri cephesi (product) [source_count: 6]
- [[vexriscv]] — RISC-V yazılım çekirdeği (product) [source_count: 1]
- [[gtse-mac]] — Üç Hızlı Ethernet MAC IP (product) [source_count: 3]
- [[gdma]] — Dağınık-toplama DMA IP (product) [source_count: 5]
- [[gsdhc]] — SD-host denetleyicisi (product) [source_count: 2]
- [[rtl8211f-phy]] — Gigabit Ethernet PHY (product) [source_count: 2]
- [[nuttx]] — Uçuş RTOS'u (product) [source_count: 2]
- [[lpddr4x-controller]] — Sertleştirilmiş DRAM denetleyicisi (product) [source_count: 5]
- [[efinity-toolchain]] — Efinix araç zinciri (product) [source_count: 6]
- [[openeye]] — Eyeriss tarzı row-stationary DNN hızlandırıcısı, 2x2 cluster, ~19 GOPS; durduruldu 2026-08-28 (product) [source_count: 3]
- [[learning-chips-lab]] — OpenEye upstream deposunun sahibi, SHL-2.1 lisansı (organization) [source_count: 2]
- [[gdma-dnn]] — OpenEye stream'leri için efx_dma 6.4.2 örneği, 64-bit AXIS / 128-bit DDR; OpenEye ile kaldırıldı (product) [source_count: 2]
- [[stalyanpu]] — Sıfırdan tasarlanan INT8 CNN hızlandırıcısı, 2048 MAC/çevrim @250 MHz (product) [source_count: 10]
- [[yolov8s]] — Hedef tespit modeli, 640×384 letterbox, INT8, 8,58 GMAC/kare (product) [source_count: 8]
- [[efx-dsp48]] — Titanium DSP48 DUAL bloğu, DSP başına 2 INT8 MAC (product) [source_count: 5]
- [[stalyanpu-toolchain]] — py/stalyanpu: lowering, nicemleme, altın model, perf modeli, board araçları, web arayüzü ve `ipgen` (product) [source_count: 7]
- [[ti375-devkit]] — Titanium Ti375C529 Development Kit, FT4232H JTAG/UART, bring-up board'u (product) [source_count: 2]
- [[snpu-axi-up512]] — 256→512 bit AXI genişletici, NPU ile LPDDR4x `axi_target0` portu arasında (product) [source_count: 3]

## Kavramlar
- [[flight-management-unit]] — Uçuş Yönetim Birimi rolü [source_count: 3]
- [[dual-soc-architecture]] — Çift-SoC mimarisi [source_count: 5]
- [[shared-dram-arbitration]] — Paylaşımlı DRAM arbitrasyonu [source_count: 6]
- [[axi-interconnect-topology]] — İki katmanlı AXI anahtar topolojisi [source_count: 6]
- [[ethernet-datapath]] — Ethernet TX/RX veri yolu [source_count: 2]
- [[boot-flow]] — Önyükleme akışı [source_count: 1]
- [[oob-to-fmu-transformation]] — OOB → FMU dönüşümü [source_count: 2]
- [[hard-soc-fabric-interrupt-path]] — Fabric kesmelerinin üst seviye userInterruptA..X portlarıyla Hard SoC PLIC'ine ulaşması, W1C ve pulse_sync CDC [source_count: 2]
- [[accelerator-control-plane-apb]] — PADDR[14] ile bölünen APB3 penceresi, apb3_2_axi4_lite köprüsü ve adres aliaslama [source_count: 2]
- [[file-driven-directed-testbench]] — Python ONLY_FILES stimulus/golden + iverilog directed bench yaklaşımı ve bilinen sınırları [source_count: 2]
- [[upstream-regression-bisect]] — Yalın worktree'ler ve upstream cocotb harness ile regresyon bisect yöntemi; OpenEye bulguları [source_count: 2]
- [[dsp-chain-systolic-array]] — 32 zincir × 32 DSP ağırlık-sabit sistolik dizi, 32 IC × 64 OC döşeme [source_count: 5]
- [[descriptor-isa]] — Descriptor listesi, CRC32, CSR haritası, blob, hata kodları [source_count: 6]
- [[int8-quantization-flow]] — PTQ hattı: OC başına ölçek, u16 requant, SiLU LUT, bit-kesin referans [source_count: 5]
- [[analytic-performance-model]] — Çevrim modeli, DDR sınırı, fps projeksiyonları, ONNX adaptörü, kaynak kestirimi ve üç board çapasına ayarlanmış ek yükler [source_count: 8]
- [[fpga-timing-closure]] — 250 MHz kapanış süreci, kaskat bölme, seed taraması, negatif slack riski [source_count: 4]
- [[board-bringup-flow]] — DDR imajı, sert SoC CSR yolu, T1..T5 testleri, fps sayaçları, 24,6 fps [source_count: 4]
- [[ddr-port-pin-constraints]] — Sert blok AXI port pinlerinin gecikme kısıtları: şablondan proje SDC'sine kopyalanmalı, aksi halde yerleşime bağlı davranış [source_count: 2]

## Karşılaştırmalar
- [[fcu-vs-hpsoc]] — Yazılım SoC ile donanım blok SoC'un karşılaştırması
- [[dnn-accelerator-options]] — OpenEye 2×2, ölçeklenmiş OpenEye ve StalyaNPU tam dizi: MAC/çevrim, tepe, fps, kaynak, karar

## Sorgular
- (henüz yok)
