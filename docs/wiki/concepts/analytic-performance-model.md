---
title: "Analitik Performans Modeli"
type: concept
created: 2026-09-15
updated: 2026-09-16
source_count: 8
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
t_pass 10, t_tile 200, t_op 4000, DDR 2,4 GB/s, saat 250 MHz, CPU kuyruğu 4 ms örtüşük.
Ek yük sabitleri 2026-09-16'da üç board karesine birlikte oturtuldu (aşağıdaki üçüncü çapa
bölümü); ondan önce 40 / 150 / 500 idi.
Katman tablosu `perf/layers.py` yaml yapısından üretilir, ONNX gerekmez
([[stalyanpu-toolchain]]).

**M0 sonucu (YOLOv8s 640×384, `full2048`).** Tablo o günkü ek yük sabitleriyledir
(t_pass 40, t_tile 150, t_op 500). Yeniden ayarlamadan sonra aynı satırlar 23,6 / 28,4 /
32,4 / 37,3 / 41,1 / 44,5 fps verir; fark her satırda yarım fps'in altındadır.

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

> ❓ **Belirsiz:** Modelin `first_fill` teriminin çift tamponlu RTL'ye göre yeniden
> kalibre edilip kalibre edilmediği belgelerde yazmaz.

**İkinci board çapası: 32×16 (2026-09-16).** 1024 MAC/çevrim dizi (32 zincir × 16 DSP),
dedicated 512-bit portta, YOLOv8s 640×384: ölçülen **9,92 M çevrim = 25,2 fps**, MAC payı
%92,6; o günkü ek yük sabitleriyle model 10,30 M çevrim = 24,3 fps veriyordu, yani %3,8
karamsardı. Küçük dizide kare süresi neredeyse tamamen MAC ile belirlenir, modelin döşeme ve
pass ek yükleri gerçekte biraz daha ucuzdu; bu fark aşağıdaki üçüncü çapa ile kapatıldı.
Kaynak tarafı:
686 DSP48, 1240 RAM10, 81,0k XLR (`snpu_top`), dizi DSP farkı tam olarak 512 blok
([[dsp-chain-systolic-array]] ölçeklemesi doğrulandı).

**Üçüncü board çapası ve ek yüklerin yeniden ayarlanması (2026-09-16).** 512 MAC/çevrim
dizi (16 zincir × 16 DSP), dedicated 512-bit portta, YOLOv8s 640×384: ölçülen **17,92 M
çevrim = 13,9 fps**, sayaç dağılımı `mac` 17 228 160, `fill` 301 527, `run_idle` 248 448,
`wr_wait` 661 982, yani MAC payı %96,1. Üç ölçüm elde olunca modelin hangi teriminin
kaydığı ayrıştırılabildi: `cyc_mac`'in `t_pass` payı çıkarıldığında kalan dizi terimi üç
koşumda da board'un MAC sayacına eşit çıkıyor (4 870 080 / 4 870 000, 9 187 200 / 9 187 200,
17 228 160 / 17 228 160). Fark tümüyle sabit ek yüklerdeydi. `t_pass`, `t_tile` ve `t_op` üç
kareye birlikte oturtuldu ve 40 / 150 / 500 yerine **10 / 200 / 4000** çevrimde karar
kılındı. Yeni sapmalar: 32×32 %+1,3, 32×16 %−0,5, 16×16 %−1,1. Üçü ortak bir uyum olduğu
için tek bir sabit kendi başına o etkinin ölçümü sayılmaz. Aynı uyum paylaşımlı 128-bit
portun etkin bant genişliğini de yeniden verdi: ek yükler ayrı hesaplandığında port 2,0 GB/s
gibi davranıyor (28,1 fps ölçümüne karşı model 28,4), eski ~1,8 GB/s değeri kare süresinin
tamamını bant genişliğine yıkmaktan geliyordu. Kaynak tarafı: 430 DSP48, 1036 RAM10, 68,8k
XLR (`snpu_top`); dizi dışı sabit maliyet üç build'de de tam 174 DSP48. 2026-09-16'da bu sabit
74 DSP48'e indi; kaynak modeli yeni 32×32 build'ine (1098 DSP48, 1302 RAM10, 88,4k XLR)
çapalandı, eski build'ler `RTL_MULTIPLIERS_DELTA` farkıyla karşılaştırılır
([[stalyanpu-dsp-overhead-sharing]]).

**IP Generator eklemeleri (2026-09-15, 09-16 güncellendi).** `hwcfg.py` DDR varsayılanı 2,4 GB/s kalır, ama
`DDR_PORTS` presetleri ölçülen değerleri taşır: `dedicated512` 8 GB/s (board 43,9 fps,
model 44,5), `shared128` 2,0 GB/s, `shared128_plan` 2,4 GB/s. Katman tablosu artık ONNX'ten
de üretilir (`perf/adapter.py`; YOLOv8s için yerleşik tabloyla aynı 5,671 M çevrim), rapor
JSON olarak alınır (`perf --json`), `perf/resources.py` hiyerarşik sentez raporuna çapalı
kaynak kestirimi ve `perf/calibration.py` ölçüm notunu verir. Web arayüzü bunları geometri
başına anlık gösterir ([[stalyanpu-ip-generator]]). Ölçüm 32×32, 32×16, 16×16 ve 16×8
geometrileriyle sınırlıdır; diğerleri aynı formülün projeksiyonudur.

**Dördüncü board çapası: 16×8 paylaşımlı yuvada (2026-09-16).** İki örnekli sistemin
([[multi-instance-npu]]) ikinci örneği: 256 MAC/çevrim, `p_max` 512, 256 KB giriş tamponu,
paylaşımlı anahtarın `MDNN` yuvası (128 bit, 2,0 GB/s). Ölçülen **36,23 M çevrim, 6,87 fps**
(duvar saati 145 569 µs/kare), MAC sayacı 33 903 360, MAC payı %93,6. Model 6,86 fps ve
36,43 M çevrim verir; dizi terimi sayaçla birebir eşit. Bu kare ayarda kullanılmadı ve model
onu %1 içinde bulduğu için ek yük sabitleri değiştirilmedi. Çapa tampon boyutunu da taşır ve
yalnız aynı tamponlu yapılandırmayla eşleşir. Kaynak tarafı: 302 DSP48, 679 RAM10, 64,8k XLR;
8'lik zincirin DSP başına fabric maliyeti 17,2 XLR ölçüldü (önceden 16'lık zincirin 22,8 değeri
varsayılıyordu), kestirim 302 / 706 / 65,7k.

## Örnekler
- `python -m stalyanpu perf --hwcfg full2048 --ddr-bw 4.5 --quiet` → dedicated port senaryosu, 40,8 fps.
- `--hwcfg small256` sim için küçük geometri; `--clk 200` yedek saat senaryosu.
- Stem L0: modelde 601 kçevrim (8 kanala dolgu, %4,7 kullanım); board'da descriptor 0 1,8 M çevrim, 1,05 M'si dolum.

## İlişkili Kavramlar
- [[dsp-chain-systolic-array]]: `t_pass` ve `P_t` terimlerinin donanım karşılığı
- [[board-bringup-flow]]: sayaçlarla kalibrasyon ve gerçek fps (24,6 → 28,1 → 43,9)
- [[shared-dram-arbitration]]: 2,4 GB/s planlama değerinin nedeni (paylaşımlı 128-bit port), kare süresinden türetilen ~1,8 GB/s ve ek yükler ayrıştırıldıktan sonra kalan 2,0 GB/s
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
- [[stalyanpu-ip-generator]]: ONNX adaptörü, DDR port presetleri, kaynak kestirimi, web arayüzü
