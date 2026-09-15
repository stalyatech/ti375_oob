---
title: "DSP Zincirli Sistolik Dizi"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 5
tags: [systolic, dsp48, cascade, weight-stationary, int8]
---

# DSP Zincirli Sistolik Dizi

## Tanım
[[stalyanpu]]'nun hesap çekirdeği: 32 zincir × 32 [[efx-dsp48]] DUAL bloğundan oluşan,
ağırlık-sabit (weight-stationary) sistolik kaskad dizisi. Her zincir 32 giriş kanalını
(IC), her DSP bir IC'nin iki çıkış kanalını (OC, lane başına bir) işler; döşeme
**32 IC × 64 OC** olup çevrimde bir çıkış pikseli üretir. Toplam 1024 DSP = 2048 INT8
MAC/çevrim; 250 MHz'de 512 GMAC/s.

## Detaylı Açıklama
**Veri akışı.** Ağırlık DSP'nin `B_REG` yazmacında tutulur (`CE` = latch), iact `A`
girişinden 32 kademeli çarpıklıkla (skew, `snpu_skew.v` üçgen gecikme hattı) akar, kısmi
toplamlar `CASCIN/CASCOUT` zincirinde ilerler. DSP içinde birikim yoktur: 32 çarpım ≤ 2^19
olduğundan 24-bit lane taşmaz. Tap ve IC-grubu birikimi 32-bit RAM10 biriktiricide
(`snpu_acc`, 2 bank × 1024 px × 64 OC, 2048-bit geniş RMW, 64 toplayıcı) yapılır; bank
değişince epilog boşaltır. 3×3, 1×1 ve stride 2 aynı makinede çalışır: tap ofsetleri ibuf
okuma adresine gömülüdür, im2col yoktur; dolgu değeri `zp_in`.

**Zincir ve gölge.** `snpu_wshadow.v` zincir başına 32 × 16-bit gölge ağırlık tutar;
256-bit dolum kelimeleriyle 32 zincir için pass başına 64 çevrim. Latch darbesi s kenarında
örneklenen vektörden itibaren tüm zincirde geçerlidir; yeni dolum son DSP latch'ledikten
sonra başlar. Pass başına ek yük ≈ 40 çevrim; P=240'ta %17, P≥960'ta ≤ %4.

**Fiziksel kaskat bölmesi.** [[ti375c529]]'da DSP kaskadı sütun başına 48 blokla sınırlıdır ve
32 uzunluklu kaskaddan en fazla 28 tane yerleşir (placer iç hatası). Bu yüzden
`snpu_pe_chain` zinciri `CASC_LEN=8` ile dört fiziksel kaskada bölünür; parça toplamları SRL
gecikme hatlarıyla hizalanıp iki seviyeli kayıtlı toplama ağacında birleşir. Zincir gecikmesi
`CHAIN_LEN+2`'den `CHAIN_LEN+2+log2(CHAIN_LEN/CASC_LEN)`'e çıkar; maliyet 4,6k EFX_ADD,
9,9k SRL8. Bu yapıyla dizi tek başına 258 MHz kapatır ([[fpga-timing-closure]]).

**Döngü yapısı.** Derleyici üretir, `snpu_seq` yürütür: döşeme (P = rows·W_out ≤ P_MAX, giriş
ayak izi ≤ ibuf/2) → oct (ceil(OC/64)) → icg (ceil(IC/32)) → tap (K·K) → piksel. Ağırlık
dizilimi DDR'da tüketim sırasındadır ([[descriptor-isa]]).

**Zincir başına kayıtlı reset (M9).** `soft_rst → DSP RST` yolu tam tasarımda en kötü yol
(-0,35 ns) olarak kalıyordu. `snpu_top` `rst_all = rst || soft_rst`'i kayıtlı hâle
getirdi, `snpu_pe_array` her zincire kendi kayıtlı reset kopyasını (`rst_c`) dağıtır; yol
iki kısa parçaya bölündü. Dizi resetten bir çevrim geç çıkar, ilk vektör buna göre
zamanlanır. Bu düzeltme tam tasarımın +0,013 ns ve sonra +0,038 ns ile kapanmasının iki
parçasından biridir ([[fpga-timing-closure]]).

**Kullanım.** İlk katman (IC=3) Faz 1'de 8 kanala dolgulanır (%4,7 kullanım); Faz 1.5
`L0_MODE` im2col-27 ile 3×3×3 pencereyi tek 32'lik IC vektörüne toplar. Tam karede dizi
kullanımı modelde %55 (2,4 GB/s); board'da MAC payı M8'de %47, M9 dedicated DDR portuyla
**%85** (5,69 M çevrimde 4,87 M MAC) ([[analytic-performance-model]]).

**Yedek planlar (gerekmedi).** 250 MHz kapanmazsa `CHAIN_LEN=16` + fabric toplayıcı, son
çare 200 MHz (model 29,3 fps). DSP bütçesi sıkı olduğundan residual çarpanları LUT'a,
requant yarı hıza alınabilir. M9'da 250 MHz kapandığından bu planlar devreye girmedi.

## Örnekler
- 3×3 conv, IC=64, OC=128: icg=2, oct=2, tap=9 → 36 pass; her pass P piksel + ~40 çevrim ek yük.
- U2 `tb_pe_chain` testi: 32'lik nokta çarpım kuyruğu, akış sırasında gölge dolumu ve latch, geçiş sınırı vektörü, uç ağırlıklar; L7 `tb_conv_full` tam 1024 DSP geometrisiyle 3×3 40→96 SiLU.
- Yerleşim deneyleri: 24×32 (768 DSP) 269 MHz, 28×32 263 MHz, 32×32 placer hatası, 128×8 (1024) 258 MHz.

## İlişkili Kavramlar
- [[fpga-timing-closure]]: kaskat bölmesi, yerleşim gürültüsü, zincir başına reset, 250 MHz kapanışı
- [[descriptor-isa]]: döngü parametreleri ve ağırlık paketleme
- [[int8-quantization-flow]]: dizinin düz `Σ int8·int8` hesabı ve epilog aritmetiği
- [[analytic-performance-model]]: pass/tile ek yükleri ve kullanım oranı
- [[dnn-accelerator-options]]: OpenEye'ın row-stationary/NoC mimarisine karşı bu seçim

## Kaynaklar
- [[stalyanpu-architecture]]: özet tablo, döngü yapısı, sarmalayıcı ve zincir, konvolüsyon motoru
- [[stalyanpu-decision-record]]: DSP başına 2 MAC ve 512 GMAC/s tavan
- [[stalyanpu-synthesis-guide]]: sütun kısıtı deneyleri ve `CASC_LEN=8` çözümü
- [[stalyanpu-verification-guide]]: U1/U2/L7 testleri, DUAL semantiği
- [[stalyanpu-readme]]: durum bandındaki kaskat notu
