---
title: "StalyaNPU Örnek Başı Sabit DSP Maliyeti: Ortak Havuz mu, Azaltma mı"
type: query
created: 2026-09-16
updated: 2026-09-16
tags: [stalyanpu, dsp48, multi-instance, epilogue, resources, timing]
---

# StalyaNPU Örnek Başı Sabit DSP Maliyeti: Ortak Havuz mu, Azaltma mı

## Soru
[[stalyanpu]] her örnekte diziden bağımsız 174 DSP48 harcıyordu. [[multi-instance-npu]]
sisteminde birden çok örnek bu "overhead" DSP'leri ortak bir havuzdan kullanıp performansı
koruyabilir mi?

## Kısa yanıt
Ortak havuz teknik olarak mümkün ama yalnız epilog için anlamlı ve pahalı. Daha iyi yol,
sabit maliyeti her örneğin içinde azaltmaktı. Bu yapıldı: örnek başı sabit maliyet 174'ten
**74 DSP48**'e indi, sonuç bit bit aynı kaldı, çevrim sayısı %0,2'den az değişti, 32×32 hızlandırıcı 250 MHz'de
kapandı. Bedeli örnek başına +33 RAM10.

## 174 DSP48'in dağılımı (önce)
Epilog 128 (32 lane × [33×17 requant için 2 + iki residual çarpımı için 2]), sequencer 22,
okuma DMA 18, adres üreteci 5, maxpool 1. Kaynak: `ip/stalyanpu/docs/ip-generator.md`,
[[efx-dsp48]].

## Havuz analizi
- **Paylaşılabilir olan yalnız epilog.** Sequencer, DMA ve adres üreteci çarpımları örneğin
  kendi komut akışında, seyrek kullanılır; paylaşmak yerine örnek içinde zaman paylaşımıyla
  neredeyse sıfıra inerler.
- **Epilog meşguliyeti.** [[analytic-performance-model]] ile YOLOv8s 640×384 için epilog
  boşaltma çevrimlerinin kare süresine oranı:

| Geometri | Ortalama | En yoğun katman |
|---|---|---|
| 32×32 | %11,1 | %45,9 |
| 32×16 | %6,2 | %43,5 |
| 16×16 | %2,9 | %23,1 |
| 16×8 | %1,5 | %11,2 |

  `snpu_acc` iki bankalı olduğundan dizi, epilog boşaltırken diğer bankaya yazar. Paylaşılan bir
  epilogda kayıp kabaca diğer örneğin meşguliyeti kadardır; aynı ağ iki örnekte aynı anda
  koşarsa yoğun katmanlar çakışır.
- **Havuzun maliyeti.** Lane'in parametre RAM'i ve tabloları katmana bağlı olduğu için örnek
  başına kalır; paylaşılan yalnız DSP'ler ve boru olur. Örnek kimlikli etiket, boşaltma başına
  hakem, 1024 bitlik banka muxu (banka okuma verisi bugün doğrudan toplayıcıya girer, ek boru
  şart) ve örnekler arası uzun hatlar gerekir. Tam tasarımın slack'i +0,03 ns civarındadır.
  Board'da görülen "örnekler birbirini yavaşlatmıyor" özelliği de bozulur.

## Uygulanan çözüm: örnek içinde azaltma
Ayrıntı `ip/stalyanpu/docs/synthesis-guide.md` "Sabit DSP maliyetinin azaltılması" bölümünde.
- **Epilog:** iki residual çarpımı yerine lane başına iki 256×20 tablo (tablo A etkinleşme veya
  residual etkinleşme terimi, tablo B residual terimi). Tabloları yeni `snpu_ep_table` yazar
  (tek çarpıcı, giriş başına bir çevrim); tablolar yapılandırmayla eşleşmeden boşaltma başlamaz.
  Boru 3 aşama kısaldı. Derleyici residual terimlerinin 20 bite sığdığını denetler; derleyicinin
  ürettiği birim ölçekte terimler ±255 içindedir.
- **Sequencer:** 11 komut adresi çarpımı tek döner çarpıcıda; stride 1/2 dışı kod 7.
- **Okuma DMA:** kanal başına tek çarpıcı çifti. **Adres üreteci:** stride kaydırma, döşeme
  pikseli kaydır-topla. **Maxpool:** koşan satır tabanı.

## Sonuçlar
| Ölçüm | Önce | Sonra |
|---|---|---|
| Dizi dışı DSP48 | 174 | 74 (epilog 65, okuma DMA 6, sequencer 2, agen 1) |
| `snpu_top` 32×32 (map) | 1198 DSP48, 1269 RAM10, 102,9k XLR | 1098 DSP48, 1302 RAM10, 88,4k XLR |
| Epilog XLR | 36,7k | 23,1k |
| `snpu_top` 32×32 pnr | | 255,3 MHz, setup +0,083 ns, hold +0,028 ns |
| `tb_layer_demo3` çevrim | 26 710 | 26 710 |
| Kestirim: tek 32×32 | 44,5 fps | 44,5 fps |
| Kestirim: en iyi iki örnek | 38,7 fps | 46,1 fps (16×32 `axi_target0` + 16×32 `MDNN`) |

Simülasyon: 26/26 PASS (birim, katman, ağ, 256/512-bit varyantlar ve iki örnekli `tb_npu_sys`);
birim olmayan residual ölçeği için iki yeni vaka eklendi (`conv_res_scale`,
`conv_res_silu_scale`). Ağ testlerinde çevrim farkı %0,2'nin altında (`tb_net_demo` 92 251 →
92 322). pytest 627.

> ❓ **Belirsiz:** Değişiklik üst projede (`ti375_oob`) yeniden sentezlenmedi ve board'da
> ölçülmedi. İki örnekli karışımın 46,1 fps değeri kestirimdir; iki örneğin aynı anda paylaşımlı
> `MDNN` yuvası ve dedicated portla koşması board'da denenmedi.

## İlişkili sayfalar
- [[stalyanpu]], [[multi-instance-npu]], [[efx-dsp48]], [[analytic-performance-model]],
  [[fpga-timing-closure]]
