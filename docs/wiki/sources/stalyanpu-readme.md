---
title: "Kaynak: StalyaNPU README (durum ve kilometre taşları)"
type: source
source_file: "ip/stalyanpu/docs/README.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, npu, dnn, yolov8s, milestones, status]
---

# Kaynak: StalyaNPU README (durum ve kilometre taşları)

## Özet
[[stalyanpu]] alt deposunun iki giriş belgesi: `docs/README.md` (durum bandı, belge dizini,
hızlı komutlar, kilometre taşı tablosu) ve depo kökündeki kısa `README.md` (tek paragraf
tanım ve dizin tablosu). Kök README hızlandırıcıyı "1024 DSP48 DUAL, 2048 MAC/çevrim
@ 250 MHz" olarak tanımlar ve board sonucunu doğrudan verir: [[yolov8s]] 640×384 için
**43,9 fps**, dedicated 512-bit DDR portu ile, bit bit doğru. Üst seviye bağlantı, APB
köprüsü, DDR portu ve board projesi `ti375_oob` üst deposunda kalır; alt depo yalnız
`rtl/`, `py/`, `sw/`, `sim/`, `syn/` ve `docs/` taşır.

## Temel Çıkarımlar
- Hedef: YOLOv8s, 1080p kaynaktan 640×384 letterbox, 30 fps, INT8, [[ti375c529]]; gerek 8,6 GMAC/kare, yani 258 GMAC/s sürekli.
- M0..M8 tamam; M9 satırı **43,9 fps** (5,69 M çevrim/kare, MAC payı %85) bildirir, hedef aşılmıştır.
- INT8 mAP50-95 düşüşü 0,78 puan (kapı 2,0); 66 descriptor'lık tam ağ derleyici arka ucunda bit bit.
- Board zinciri: M8 24,6 fps (paylaşımlı port) → M9 28,1 fps (döşeme çift tamponu, zamanlama kapanışı) → 43,9 fps (dedicated port + [[snpu-axi-up512]]).
- M9 kapısı: ≥ 30 fps, slack ≥ 0, iki koşumda aynı CRC; üçü de sağlandı.

## Detaylı Notlar
**Hedef ve gerekçe.** Hedef gereksinim, [[dnn-accelerator-options]] karşılaştırmasında
[[openeye]] yerine yeni bir hızlandırıcı yazılmasının nedenidir. Kök README alt depoyu
"INT8 CNN hızlandırıcısı" olarak tanımlar ve dizin tablosunda `syn/` (bağımsız Efinity
sentez projeleri: dizi, motor, top) ile `sw/baremetal/npu_test` bring-up testini de sayar.

**Durum bandı.** `docs/README.md` başındaki bant 2026-09-14 tarihlidir ve M8'i "sürüyor"
diye anlatır: sert SoC'tan sürülen NPU tam kareyi bit bit koşturur, DDR yolu düzeltmeleriyle
4,6'dan 24,6 fps'e çıkılmıştır, kalan iş giriş dolumunun hesapla örtüşmesi, stem L0 modu ve
zamanlama kapanışıdır. Bant M5 sentez sayılarını (dizi 258 MHz, motor 256 MHz, tam `snpu_top`
244 MHz), DSP sütun kısıtını (zincirler 8'lik dört kaskada bölündü, bkz.
[[dsp-chain-systolic-array]]) ve M7 entegrasyonunu (OpenEye ve `gDMA_dnn` söküldü, `snpu_top`
`MDNN=3` yuvasına, CSR yumuşak SoC APB penceresine `0xF810_4000`, kesme PLIC 9, +0,005 ns)
özetler. Bant M9 sonrası güncellenmemiştir; güncel sonuç kilometre taşı tablosunda ve kök
README'dedir.

**Belge dizini ve komutlar.** Sekiz alt belge: karar kaydı ([[stalyanpu-decision-record]]),
mimari ([[stalyanpu-architecture]]), ISA ([[stalyanpu-isa-descriptor]]), araç zinciri
([[stalyanpu-toolchain-guide]]), doğrulama ([[stalyanpu-verification-guide]]), sentez
([[stalyanpu-synthesis-guide]]), bring-up ([[stalyanpu-bringup-guide]]) ve doğruluk raporu
([[stalyanpu-accuracy-report]]). Performans planı (`perf-plan.md`,
[[stalyanpu-perf-plan]]) tabloda geçmez ama M9 satırından referans verilir. Tek venv
(`.venv-stalyanpu`) altında `python -m stalyanpu` komutları: `perf`
([[analytic-performance-model]]), `lower`, `gen-header`, `calibrate`/`eval`
([[int8-quantization-flow]]), `compile`/`golden` ([[descriptor-isa]]); pytest ve
`sim/run_sim.py all -j 3` ([[stalyanpu-toolchain]]).

**Kilometre taşları.**

| M | Kapı | Durum |
|---|------|-------|
| M0 | perf ≥ 30 fps, lowering 0 desteklenmeyen op, DSP TB bit-kesin | tamam (32,9 fps @2,4 GB/s) |
| M1 | INT8 mAP50-95 düşüşü ≤ 2,0 | tamam (44,86 → 44,07, düşüş 0,78) |
| M2 | interp ≡ runner tüm ağ | tamam (66 descriptor) |
| M3 | dizi, acc, ibuf, wfifo, epilog TB'leri | tamam (7/7) |
| M4 | DMA, seq, csr, maxpool5, `snpu_top` descriptor testleri | tamam (4/4) |
| M5 | dizi-tek sentez 250 MHz | tamam (dizi 258, motor 256; top 244 MHz) |
| M6 | YOLOv8s katman-katman sim | katmanlar tamam (66/66 kırpılmış, vendor 5/5) |
| M7 | `ti375_oob_top.v` entegrasyonu | tamam (+0,005 ns, 1217 DSP, 1478 RAM10) |
| M8 | board ≥ 30 fps | tamam (bit bit OK, 24,6 fps paylaşımlı portta) |
| M9 | ≥ 30 fps, slack ≥ 0, iki koşum aynı CRC | **43,9 fps**, 5,69 M çevrim, MAC %85, ALL PASS |

M9 teslimatı dört parçadır: döşeme çift tamponu, epilog örtüşmesi, zamanlama kapanışı ve
dedicated DDR portu. Satır, kapanışın "seed taramasında" olduğunu söyler; bring-up ve sentez
rehberleri son build'in seed 6 ile +0,038 ns'de kapandığını bildirir
([[fpga-timing-closure]]). M8 satırının "≥ 30 fps" kapısı 24,6 fps ile "tamam" işaretlenmiş,
fps kapısı fiilen M9'a devredilmiştir ([[board-bringup-flow]]).

**CSR yolu.** Durum bandındaki M7 cümlesi CSR'ı yumuşak SoC APB penceresinde
(`0xF810_4000`) anlatır; M8 cümlesi ise NPU'nun sert SoC'tan sürüldüğünü söyler. Bu iki
ifade sırayla iki dönemi anlatır: HEAD'de CSR sert SoC ([[efx-sapphire-hpsoc-slb]]) AXI-A
üzerinden `0xE810_4000`'dedir ve [[stalyanpu-bringup-guide]] bunu "uygulanan akış" olarak
verir. README'de artık çelişki değil, güncellenmemiş bir durum bandı vardır.

> ❓ **Belirsiz:** M6 tam ağ simülasyonu (`tb_yolo_net`, 4-6 saat) "M8 öncesi isteğe bağlı"
> bırakılmış ve koşulduğu hiçbir belgede yazmaz; board'daki tam kare bit bit eşleşmesi bu
> boşluğu fiilen kapatır.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[yolov8s]], [[ti375c529]], [[openeye]], [[stalyanpu-toolchain]], [[efx-sapphire-hpsoc-slb]], [[snpu-axi-up512]], [[efx-dsp48]], [[efinity-toolchain]]
- İlgili kavramlar: [[dsp-chain-systolic-array]], [[descriptor-isa]], [[int8-quantization-flow]], [[analytic-performance-model]], [[fpga-timing-closure]], [[board-bringup-flow]]
- Karşılaştırma: [[dnn-accelerator-options]]
- Alt belgeler: [[stalyanpu-decision-record]], [[stalyanpu-architecture]], [[stalyanpu-isa-descriptor]], [[stalyanpu-toolchain-guide]], [[stalyanpu-verification-guide]], [[stalyanpu-synthesis-guide]], [[stalyanpu-bringup-guide]], [[stalyanpu-accuracy-report]], [[stalyanpu-perf-plan]]

## Alıntılar
- "Hedef: YOLOv8s 640×384, 30 fps; board'da 43,9 fps (dedicated 512-bit DDR portu, bit bit doğru)." (`ip/stalyanpu/README.md`, satır 4)
- "M9 ... 43,9 fps (5,69 M çevrim, MAC %85) dedicated 512-bit port + `snpu_axi_up512` ile, ALL PASS, iki koşum aynı CRC" (`docs/README.md`, satır 94)
