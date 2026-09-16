---
title: "Genel Bakış"
type: overview
created: 2026-07-03
updated: 2026-09-15
tags: [overview, fmu, ti375, dnn, stalyanpu]
---

# Genel Bakış

## Kapsam ve amaç

Bu wiki, Efinix Titanium **Ti375C529** FPGA'i üzerinde geliştirilen ve bir **Uçuş Yönetim
Birimi (Flight Management Unit, FMU)** olarak kullanılacak `ti375_oob` tasarımının bilgi
tabanıdır. Kaynaklar, `docs/help/` mimari yardım sayfaları, `docs/dnn-integration/` OpenEye notları ve
`ip/stalyanpu/docs/` StalyaNPU belgeleridir; her biri
`sources/` altında özetlenmiş, teknik bileşenler `entities/`, mimari fikirler `concepts/`
sayfalarına ayrıştırılmıştır.

## Ana temalar

1. **Çift-SoC mimarisi.** Tek FPGA üzerinde iki RISC-V Sapphire SoC bulunur:
   [[efx-sapphire-fcu]] (yazılım SoC, uçuş uygulama işlemcisi) ve
   [[efx-sapphire-hpsoc-slb]] (donanım blok, ev-işleri/konfigürasyon/hata ayıklama). Bkz.
   [[dual-soc-architecture]].
2. **Paylaşımlı DRAM.** Her iki SoC, [[gdma]] ve [[gsdhc]], tek bir sertleştirilmiş
   [[lpddr4x-controller]] denetleyicisini bir AXI anahtarı üzerinden paylaşır (2026-07'de
   3'e 1, 2026-08'den itibaren NPU yuvasıyla 5'e 1). Bkz. [[shared-dram-arbitration]] ve
   [[axi-interconnect-topology]].
3. **Veri düzlemi yazılım SoC'unda.** Gigabit Ethernet ([[gtse-mac]] + [[rtl8211f-phy]]),
   dağınık-toplama DMA ([[gdma]]) ve SD depolama ([[gsdhc]]) yazılım SoC'una taşınmıştır. Bkz.
   [[ethernet-datapath]].
4. **NuttX uçuş yazılımı.** Uçuş uygulaması, PX4 sınıfı uçuş denetleyicilerinde kullanılan
   [[nuttx]] gerçek zamanlı işletim sistemini SPI flash'tan başlatır. Bkz. [[boot-flow]].
5. **OOB'den FMU'ya dönüşüm.** Stok "kutudan çıktığı gibi" (OOB) demosu, kademeli olarak FMU
   platformuna dönüştürülmektedir. Bkz. [[oob-to-fmu-transformation]].

## DNN hızlandırıcı hattı (2026-08/09)

6. **OpenEye denemesi (durduruldu).** Eyeriss tarzı [[openeye]] çekirdeği, [[gdma-dnn]] ve
   5'e 1 DDR anahtarı ile sert SoC'a bağlandı, altın modelle bit bit doğrulandı ve timing
   kapandı; ama tepe 96 MAC/çevrim @100 MHz (~19 GOPS) hedefin çok altındaydı ve upstream
   `main` [[upstream-regression-bisect]] ile fonksiyonel olarak bozuk bulundu. Kalıcı
   kazanımlar: [[hard-soc-fabric-interrupt-path]], [[accelerator-control-plane-apb]],
   [[file-driven-directed-testbench]]. Karar: [[dnn-accelerator-options]].
7. **StalyaNPU.** Sıfırdan tasarlanan INT8 hızlandırıcı [[stalyanpu]]: 1024 [[efx-dsp48]]
   bloğundan 2048 MAC/çevrim @250 MHz (tepe 512 GMAC/s, ~1 TOPS), [[dsp-chain-systolic-array]]
   dizisi, [[descriptor-isa]] ile sürülür, [[stalyanpu-toolchain]] ONNX'ten descriptor
   blob'u üretir ([[int8-quantization-flow]], COCO mAP kaybı 0,78). Hedef [[yolov8s]]
   640×384 @30 fps.
8. **Durum (2026-09-15).** Board'da ([[ti375-devkit]], sert SoC'tan) tam kare bit bit doğru,
   **24,6 fps** paylaşımlı portta; 2026-09-15 akşamı dedicated 512-bit DDR portu ile **43,9 fps**
   (bit bit doğru, iki koşum aynı CRC, hedef aşıldı; bkz. [[stalyanpu-perf-plan]]). Yol:
   zamanlama kapanışı (reset ağacı, maxpool) → döşeme çift tamponu → epilog örtüşmesi (board'da
   kazandırmadı, DDR sınırı) → dedicated port (asıl kaldıraç; 512-bit port ile NPU arasında
   [[snpu-axi-up512]] genişletici, port pinlerinin kısıtlanma dersi [[ddr-port-pin-constraints]]). Negatif slack'li build'lerin
   bozuk sonuç üretebildiği görüldü ([[fpga-timing-closure]]); son build'in kapanışı seed
   taramasında. Tabanı [[board-bringup-flow]] ölçümleri ve [[analytic-performance-model]].
9. **IP Generator (2026-09-15).** [[stalyanpu-toolchain]] yerel bir web arayüzü kazandı
   ([[stalyanpu-ip-generator]]): dizi geometrisi, saat ve DDR portu seçilir, perf modeli ve
   kaynak kestirimi anında hesaplanır, ONNX'ten blob'a akış ve board adımları seçimli zincir
   olarak koşar, seçilen geometri için IP paketi (hwcfg, ISA başlığı, Verilog sarmalayıcı,
   Efinity projesi) üretilir. Yalnız INT8.

## Gelişen sonuçlar

- Uçuş-kritik yazılım [[efx-sapphire-fcu]] üzerinde yoğunlaşır; [[efx-sapphire-hpsoc-slb]] bir
  ev-işleri/ön-yükleme cephesidir. Ayrım [[fcu-vs-hpsoc]] sayfasında karşılaştırılmıştır.
- Toolchain ([[efinity-toolchain]]) 2025.2'ye, Sapphire IP 3.3.0'a, Ethernet MAC 7.0'a
  yükseltilmiştir.

## Bilinen boşluklar ve açık sorular

> ❓ **Belirsiz:** `ti375_oob_top.v:666` içindeki `MHSDC` index yazım hatası (bkz.
> [[gsdhc]], [[fmu-notes]]) sentez sırasında sessizce çözülüyorsa SD okuma yolu şüphelidir;
> elaboration log ile doğrulanmalıdır.

- `MAC_SOURCE_ADDRESS` ve statik IP henüz sağlanmamıştır (placeholder).
- `rtl/` altındaki tutkal RTL dosyaları ve `gAXIS_1to3_switch` henüz üst modüle bağlanmamıştır.
- FMU için kanonik NuttX boot varyantı (`hp`/`x2`/`x3`) netleştirilmelidir.
- NPU CSR yolunun belgelerdeki iki hali (yumuşak SoC M7, sert SoC M8): HEAD sert SoC;
  [[stalyanpu-synthesis-guide]] tablosu güncellenmeli.
- Determinizm (iki koşumda aynı CRC) 2026-09-15'te kanıtlandı; dedicated port build'inin
  zamanlama kapanışı (seed taraması) bekleniyor.
- Dedicated DDR portu M9'da gerçeklendi (M7 belgesindeki planlama eski); port 512-bit,
  256-bit seçeneği x32 LPDDR4x'te yok.
- OpenEye 2x2/64-bit yolunun upstream'de neden çalışmadığı izole edilmedi; upstream issue
  açılmadı ([[openeye-upstream-issue]]).

Kaynak sayfaları için [[index]] dosyasına, işlem geçmişi için `log.md` dosyasına bakın.
