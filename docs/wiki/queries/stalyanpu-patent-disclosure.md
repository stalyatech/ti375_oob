---
title: "StalyaNPU Patent Teknik Açıklama Belgesi"
type: query
created: 2026-09-16
updated: 2026-09-17
tags: [stalyanpu, patent, disclosure, docx, figures, multi-instance]
---

# StalyaNPU Patent Teknik Açıklama Belgesi

## Soru
[[stalyanpu]] için patent vekiline verilecek ve teknik personelin mimariyi anlamasını sağlayacak
İngilizce, Word formatında bir teknik açıklama (invention disclosure) belgesi hazırlanması.

## Çıktı
- Belge: `ip/stalyanpu/docs/patent/stalyanpu-technical-disclosure.docx` (sürüm 1.1, 28 sayfa, İngilizce)
- Çizimler: `ip/stalyanpu/docs/patent/figures/fig01..fig12-*.svg` ve aynı adlı 300 dpi eşdeğeri PNG'ler;
  siyah beyaz, referans numaralı (Şekil N için N×100 serisi)
- Renkli illüstrasyon: `fig13-cnn-primer.svg/.png` (Ek A, referans numarasız); README'lerde de
  kullanılmak üzere hazırlandı
- Belge ve çizimler wiki sayfalarından ve ham kaynaklardan (`ip/stalyanpu/docs/*.md`,
  `ti375_oob_top.v`, `snpu_seq.v`, `snpu_rd_dma.v`) derlendi; yeni ölçüm içermez.

## Belgenin yapısı
Amaç, teknik alan, arka plan ve problem ([[openeye]] ölçümleri iç gözlem olarak), çözüm
özeti, şekil listesi, ayrıntılı açıklama (sistem, blok diyagramı, ağ yapısı, döngü yuvası,
DSP hücresi, sistolik zincir, epilog, döşeme çift tamponu, descriptor programı, veri
taşıyıcılar ve genişletici, nicemleme, performans modeli, IP generator, doğrulama), gerçekleme
sonuçları, alternatifler, aday istem kavramları, bilinen sınırlar, kaynak dosyalar ve sözlük.

## Sürüm 1.1 (2026-09-17)
Belge [[multi-instance-npu]] akışına ve [[stalyanpu-dsp-overhead-sharing]] değişikliğine göre
güncellendi:
- Şekil 1 iki örnekli sistem (APB CDC, slot çözücü, örnek başına kesme hattı, dedicated port ve
  paylaşımlı anahtar yuvası, `axi_target1` kullanılamaz), Şekil 2 epilog kutusu, Şekil 8 tablo
  tabanlı epilog (tablo A 860, tablo B 865, tablo yazıcısı 875), Şekil 12 sistem entegratörü.
- Yeni bölümler: 6.15 (örnekler, DRC, işaretli bölgeler, model başına kalibrasyon, sabit maliyet
  174 → 74 DSP48 tablosu, ortak epilog havuzunun neden seçilmediği), 7.6 (iki örnekli board
  ölçümü), Ek A (Şekil 13 renkli CNN ilüstrasyonu).
- Özet beşinci buluş grubunu (E) ve iki örnekli ölçümü taşır; aday istemlere Grup E (E1..E6)
  eklendi; bilinen sınırlar, doğrulama sayıları (sim 26/26, pytest 627), kaynaklar ve sözlük
  güncellendi. Mevcut şekillerin referans numaraları değişmedi.

## Buluş grupları
- **A. Ağırlık-sabit sistolik DSP dizisi:** [[dsp-chain-systolic-array]], [[efx-dsp48]]
- **B. Döşeme çift tamponu ve boşaltma örtüşmesi:** [[stalyanpu-architecture]]
- **C. Descriptor programı, NC32HW sıfır kopya, üç kanallı okuma DMA'sı ve genişletici:**
  [[descriptor-isa]], [[snpu-axi-up512]]
- **D. Araç zinciri, kalibre edilmiş model ve IP generator:** [[int8-quantization-flow]],
  [[analytic-performance-model]], [[stalyanpu-ip-generator]], [[stalyanpu-toolchain]]
- **E. Düşük sabit maliyetli çoklu örnek:** [[multi-instance-npu]], [[stalyanpu-dsp-overhead-sharing]]

## DNN yapısı çizimleri
Şekil 3, [[yolov8s]] 640×384 ağını backbone (30 descriptor), neck (18) ve head (18) olarak,
Upsample ve Concat katmanlarını kopyasız adres modu olarak ve NPU/CPU kesimini gösterir.
Şekil 4, C2f bloğunun tek NC32HW tamponunda split/concat'siz yürütülmesini ve neck'teki
`TWO_SRC` + `UPS0` okumasını gösterir. Şekil 5 bir konvolüsyon katmanının döşeme, oct, icg,
tap, piksel döngülerine ve diziye eşlenmesini anlatır.

## Notlar
- Ölçüm sayıları [[board-bringup-flow]] ve [[stalyanpu-perf-plan]] ile aynıdır: 43,9 fps,
  5,69 M çevrim/kare, mAP50-95 düşüşü 0,78; 32×16 25,2 fps, 16×16 13,9 fps.
- Belge, patent vekilinin ayrıca önceki teknik araştırması yapması gerektiğini belirtir;
  aday istem kavramları istem metni değildir.
- Belgedeki "bilinen sınırlar" bölümü wiki'deki açık noktaları taşır (L0 modu, ağırlık tekrar
  akışı, `first_fill` kalibrasyonunun belirsizliği).
- Üretim betikleri depoya eklenmedi; çizimler SVG olarak düzenlenebilir. Sürüm 1.1'de
  çizimler aynı betiklerle yeniden üretildi; değişmeyen 9 şekil bayt bayt aynı çıktı.
- Şekil 13 bir patent çizimi değildir; renkli ve açıklayıcıdır, bu yüzden numaralı şekil
  dizisinin sonuna, Ek A'ya kondu.

## Kaynaklar
- [[stalyanpu]], [[stalyanpu-architecture]], [[stalyanpu-isa-descriptor]],
  [[stalyanpu-decision-record]], [[stalyanpu-bringup-guide]], [[stalyanpu-accuracy-report]],
  [[dnn-accelerator-options]]
