---
title: "Dosya Güdümlü Directed Testbench"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [verification, simulation, iverilog, golden-model, testbench]
---

# Dosya Güdümlü Directed Testbench

## Tanım
Hızlandırıcı doğrulamasında stimulus ve altın referansın Python tarafında çevrimdışı üretilip
hex dosyalarına yazıldığı, RTL doğrulamasının ise bu dosyaları okuyan saf Icarus Verilog directed
testbench ile yapıldığı yaklaşım. `sim/openeye/` altında [[openeye]] için uygulanmıştır.

## Detaylı Açıklama
Yaklaşım, ağır Python bağımlılığını (TensorFlow) simülasyon döngüsünden ayırır. OpenEye'ın kendi
doğrulama altyapısı `ONLY_FILES=1` modunda çalıştırılır: `gen_stimulus.py` bir Keras katmanı kurar,
`dma_i` kelime akışını ve beklenen `dma_o` beat'lerini üretir, hex'e çevirir. Bu adım yalnız
stimulus yenilenirken TensorFlow ister (Efinity python311, `PYTHONHOME` set edilmeli,
`.pydeps-openeye/` altında `pip install --target`). Sonraki koşumlar yalnız iverilog kullanır.

Bileşenler ([[dnn-integration-readme]]):
| Dosya | İşlev |
|---|---|
| `gen_stimulus.py` | Katman kurulumu, stimulus + golden üretimi; geometri env değişkenleri RTL örneğiyle eşleşir |
| `stim/dma_stim.hex`, `stim/dma_golden.hex` | Regresyon vektörü: Conv 8 filtre, 3x3, 8x8x4 giriş (463 kelime → 256 beat) |
| `tb_openeye_core.v` | DUT `open_eye_mt_v1_0` + `openeye_irq`; tready'ye saygılı AXIS master, LFSR backpressure, altın karşılaştırma, IRQ kontrolleri |
| `tb_openeye_glue.v` | APB köprü + cfg_reg yaz/oku, `openeye_irq` köşe durumları, tam W1C zinciri (`pulse_sync` dahil) |
| `run_core.sh`, `run_glue.sh` | Derle + koş; opsiyonlar dosya adlarından önce gelmeli |

Koşum: `sh sim/openeye/run_core.sh [+BACKPRESSURE] [+STIM=... +GOLD=...]`. `+BACKPRESSURE`
LFSR ile rastgele `tready` düşürerek akış kontrolünü sınar. [[gdma-dnn]] kapsam dışıdır (vendor
RTL); AXIS kontratı testbench'teki BFM ile temsil edilir. Sonuç (2026-08-27): glue PASS, core
serbest akış + backpressure PASS, 256 beat bit bit, IRQ set/sticky/clear dahil.

### Bilinen sınırlar
1. **Dosya sırası karşılaştırması.** Beat'ler dosya sırasıyla karşılaştırılır. Upstream cocotb
   karşılaştırması `make_ref`'in döndürdüğü `output_order` permütasyonunu ve dolgu pozisyonu
   maskesini kullanır. Çıkış pozisyon sayısının donanım dizilimine tam bölünmediği şekillerde
   (örnek: 16 filtre, 7x7 çıkış → filtre başına 7 dolgu pozisyonu; golden 0 yazar, RTL hesaplanmış
   değer basar) testbench yanlış FAIL üretir.
2. **Katman boyutu zarfı.** 10x10x8 ve 12x12x8 girişlerde RTL beklenen beat'lerin tam yarısını
   üretmiştir; mapper'ın transmisyon hesabı `RAM_CELLS=8` / `BUFFER_WIDTH=10` geometrisini
   hesaba katmıyor görünür. Gerçek modeller öncesi bu geometri için katman boyutu zarfı
   çıkarılmalıdır.

Bu nedenle commit edilen regresyon vektörü tam oturan şekildir (64 çıkış pozisyonu donanım
dizilimine tam bölünür). Yaklaşımın tamamlayıcısı, upstream'in kendi cocotb harness'ini çalıştıran
[[upstream-regression-bisect]] yöntemidir; o harness permütasyon ve maske karşılaştırmasını
içerir ama TensorFlow'u her koşumda ister.

## Örnekler
- Tam W1C zinciri: `tb_openeye_glue.v` 0x3C'e 1 yazar, `pulse_sync` üzerinden latch'in
  temizlendiğini gözler ([[hard-soc-fabric-interrupt-path]]).
- Backpressure: `+BACKPRESSURE` ile aynı vektör, 256 beat yine bit bit eşleşir.

## İlişkili Kavramlar
- [[upstream-regression-bisect]]: aynı DUT için cocotb tabanlı alternatif harness
- [[hard-soc-fabric-interrupt-path]]: glue testbench'in doğruladığı zincir
- [[accelerator-control-plane-apb]]: glue testbench'in sürdüğü APB köprüsü

## Kaynaklar
- [[dnn-integration-readme]]: strateji, dosya tablosu, bilinen sınırlar, stimulus yeniden üretimi
- [[openeye-upstream-issue]]: cocotb harness ortamı (karşılaştırma için)
