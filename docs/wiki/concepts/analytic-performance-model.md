---
title: "Analitik Performans Modeli"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 7
tags: [performance, cycle-model, ddr-bandwidth, fps, perf, m9]
---

# Analitik Performans Modeli

## Tanım
[[stalyanpu]] için katman başına çevrim sayısını MAC sınırı ile DDR sınırının maksimumu
olarak kestiren, `python -m stalyanpu perf` ile çalıştırılan model. M0'da 30 fps kapısını
denetlemek için yazıldı; M6'da simülasyon çevrimleriyle, M8'de donanım sayaçlarıyla kalibre
edilmesi planlandı.

## Detaylı Açıklama
**Formül.** Katman başına:

```
n_pass   = ceil(IC/n_ic) · k²          n_oct = ceil(OC/n_oc)
cyc_mac  = Σ_t n_oct · n_pass · (P_t + t_pass)
cyc_tile = n_tiles · t_tile + ilk döşemenin açık ibuf dolumu
cyc_ddr  = (giriş + ağırlık·n_tiles + residual + çıkış baytı) / (bant genişliği / saat)
cycles   = max(cyc_mac + cyc_tile, cyc_ddr) + t_op
```

Döşeme seçimi: tam çıkış satırları, `P_t ≤ p_max` (1024), giriş ayak izi (halo dahil)
≤ ibuf/2; `backend/tiler.py` aynı seçimi derleyici için yapar. Varsayılanlar `hwcfg.py`'de:
t_pass 40, t_tile 150, t_op 500, DDR 2,4 GB/s, saat 250 MHz, CPU kuyruğu 4 ms örtüşük.
Katman tablosu `perf/layers.py` yaml yapısından üretilir, ONNX gerekmez
([[stalyanpu-toolchain]]).

**M0 sonucu (YOLOv8s 640×384, `full2048`).**

| Etkin DDR | Çevrim/kare | Kare süresi | fps | Kullanım |
|----------:|------------:|------------:|----:|---------:|
| 1,6 GB/s | 10,40 M | 41,6 ms | 24,0 | %40 |
| 2,0 GB/s | 8,65 M | 34,6 ms | 28,9 | %49 |
| **2,4 GB/s** (paylaşımlı port planlama değeri) | **7,60 M** | **30,4 ms** | **32,9** | %55 |
| 3,2 GB/s | 6,68 M | 26,7 ms | 37,4 | %63 |
| 4,5 GB/s (dedicated 256-bit port) | 6,12 M | 24,5 ms | 40,8 | %68 |
| 8,0 GB/s (sınırsız) | 5,67 M | 22,7 ms | 44,1 | %74 |

Hesap sınırı 44 fps; 200 MHz @2,4 GB/s 29,3 fps; 640×640 @4,5 GB/s 25,3 fps. DDR trafiği
63,8 MB/kare (11,1 MB benzersiz ağırlık, kalanı aktivasyon ve halo/ağırlık yeniden okuması).
Baskın gruplar Detect.P3 (%13), L2.c2f (%11), L4.c2f (%8), L0 (%8). DDR'a bağlı katmanlar:
tüm 1×1'ler, L0/L1/L2, SPPF havuzları.

**Kapı yorumu.** 30 fps paylaşımlı port varsayımıyla tutar (32,9) ama "%67 bütçe" marjı
sağlanmaz (bütçenin %91'i); tasarım **DDR'a bağlıdır**. Bu yüzden dedicated 256-bit
`axi_target0` portu ([[lpddr4x-controller]], [[shared-dram-arbitration]]) öne çekildi,
erken katman füzyonu (L0→L2, 17 MB trafik) ve `p_max` 2048 seçeneği listeye girdi. Port
M9'da gerçeklendi; arayüz tasarımcısı 256-bit'i kabul etmediğinden 512-bit açıldı
(aşağıdaki M9 karşılaştırmasına bak).

**M6 kalibrasyonu (sim).** `sim/perf_compare.py` 66 kırpılmış katman koşumunun
`CYCLE_CNT`'ini modelle karşılaştırır: tümü ardışık modelde RTL %17,9 hızlı, yalnız giriş
dolgusu ardışık modelde %17,6 yavaş; gerçek makine ortada. Kırpılmış koşular DDR payını
abarttığından bu bant tam kare için üst sınırdır.

**M8 kalibrasyonu (board).** CSR sayaçları (`cycles`, `fill`, `run_idle`, `mac`,
`wr_wait`) ile ölçüm: MAC alt sınırı 4,87 M çevrim; DDR yolu düzeltmelerinden sonra
10,2 M çevrim = 24,6 fps; dağılım MAC %47, giriş dolumu %35 (etkin 2,5 GB/s, modelin 2,4
GB/s planlama değerine yakın), koşumda boş %14. 30 fps için 8,3 M çevrim gerekir; adaylar
giriş dolumunun hesapla örtüşmesi, stem L0 modu, dedicated port ([[board-bringup-flow]]).

**M9 karşılaştırması (board, 2026-09-15).** Model 2,5 GB/s ve 250 MHz ile 7,43 M çevrim
= **33,6 fps** verirken board üç adımda şöyle ölçtü: döşeme çift tamponu 8,89 M (28,1
fps), epilog örtüşmesi aynı, dedicated 512-bit DDR portu ([[snpu-axi-up512]],
[[lpddr4x-controller]]) **5,69 M = 43,9 fps**. Sonuçlar modelin iki varsayımını düzeltir:
- M8'de model ile ölçüm arasındaki 2,8 M çevrimlik fark gerçekten örtüşmeyen dolumdan ve
  L0'dan geliyordu; çift tampon dolumu 3,6 M'den 1,04 M'ye indirdi ama paylaşımlı yolda
  kazanç `run_idle`'a kaydı, çünkü kare süresi etkin ~1,8 GB/s ile sınırlıydı (63,8
  MB/kare ÷ 35,6 ms).
- Dedicated portta board modelin üstüne çıktı: 43,9 fps, modelin 8 GB/s "sınırsız"
  satırındaki 44,1 fps'e denk. Yani modelin 2,5 GB/s bant genişliği varsayımı dedicated
  port için artık düşüktür; etkin değer 4 GB/s'nin üzerindedir ve tasarım DDR'a değil
  MAC'e bağlı hâle gelmiştir (MAC %85). Ağırlık tekrar akışı (20 MB/kare) marj işi oldu.

> ❓ **Belirsiz:** `hwcfg.py` DDR varsayılanının (2,4 GB/s) dedicated port için
> güncellenip güncellenmediği ve modelin `first_fill` teriminin çift tamponlu RTL'ye göre
> yeniden kalibre edilip edilmediği belgelerde yazmaz.

## Örnekler
- `python -m stalyanpu perf --hwcfg full2048 --ddr-bw 4.5 --quiet` → dedicated port senaryosu, 40,8 fps.
- `--hwcfg small256` sim için küçük geometri; `--clk 200` yedek saat senaryosu.
- Stem L0: modelde 601 kçevrim (8 kanala dolgu, %4,7 kullanım); board'da descriptor 0 1,8 M çevrim, 1,05 M'si dolum.

## İlişkili Kavramlar
- [[dsp-chain-systolic-array]]: `t_pass` ve `P_t` terimlerinin donanım karşılığı
- [[board-bringup-flow]]: sayaçlarla kalibrasyon ve gerçek fps (24,6 → 28,1 → 43,9)
- [[shared-dram-arbitration]]: 2,4 GB/s planlama değerinin nedeni (paylaşımlı 128-bit port) ve ~1,8 GB/s etkin bulgusu
- [[descriptor-isa]]: CYCLE_CNT ve STALL sayaçları
- [[dnn-accelerator-options]]: OpenEye için aynı hedefin fps karşılığı
- Varlıklar: [[snpu-axi-up512]], [[lpddr4x-controller]] (dedicated portun bant genişliği varsayımını değiştirmesi)

## Kaynaklar
- [[stalyanpu-decision-record]]: M0 tablosu, kapı değerlendirmesi, plan düzeltmeleri
- [[stalyanpu-architecture]]: performans bölümü ve baskın gruplar
- [[stalyanpu-toolchain-guide]]: formül, varsayılanlar, `perf` komutu
- [[stalyanpu-verification-guide]]: M6 `perf_compare` bandı
- [[stalyanpu-bringup-guide]]: board sayaçları, 24,6 ve 43,9 fps
- [[stalyanpu-perf-plan]]: 33,6 fps model kestirimi, A/A2/dedicated port sonuçları
- [[stalyanpu-readme]]: M0 kapısı (32,9 fps, marj ince)
