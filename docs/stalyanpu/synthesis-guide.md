# StalyaNPU Sentez Rehberi (M5)

Bu belge, StalyaNPU'nun Efinity 2025.2 ile tek başına sentezlenmesini anlatır:
proje yapısı, koşum komutları, hedefler ve M5 sırasında bulunan cihaz
kısıtları. Entegrasyon (ti375_oob projesine bağlama) M7 konusudur.

## Proje yapısı

```
syn/stalyanpu/
├── run_syn.py            # koşucu: map / interface / pnr + rapor özeti
├── rtl/
│   ├── snpu_syn_chain.v  # yalnız PE dizisi (yerleşim ve Fmax denemeleri)
│   ├── snpu_syn_conv.v   # konvolüsyon motoru (snpu_conv_unit)
│   └── snpu_syn_top.v    # tam hızlandırıcı (snpu_top)
├── chain/  snpu_chain.xml, snpu_chain.peri.xml, snpu_chain.sdc
├── conv/   snpu_conv.xml,  snpu_conv.peri.xml,  snpu_conv.sdc
└── top/    snpu_top.xml,   snpu_top.peri.xml,   snpu_top.sdc
```

Her dizin bağımsız bir Efinity projesidir; `outflow/`, `work_*` ve
`run_*.log` çıktıları gitignore'dadır.

## Sarmalayıcı yöntemi

Modül portları binlerce bit olduğundan doğrudan pinlere bağlanamaz. Her
sarmalayıcı dört pin kullanır: `clk_in` (125 MHz), `rst_i`, `sin`, `sout`.
Tüm DUT girişleri `sin` ile beslenen uzun bir kaydırma yazmacından sürülür,
tüm çıkışlar kayıtlı bir xor ağacıyla `sout`'a katlanır. Böylece hiçbir
giriş sabit görünmez ve eşleyici tasarımı budayamaz; pin sayısı da 5'te
kalır. PLL: `clk_in` → PLL_BL2 (M=1, N=1, O=4, geri besleme CLKOUT0 böleni
10) → `clk` çıkışı bölen 5 ile 250 MHz. SDC: `create_clock -period 4.0 clk`.

`peri.xml` ve proje XML dosyaları bir kez üretilip depoya kondu; cihaz
bankaları `ti375_oob.peri.xml`'den kopyadır. `gpio_info` bloğunun şema
gereği `global_unused_config` ile bitmesi gerekir.

## Koşum

```bat
.venv-stalyanpu\Scripts\python syn\stalyanpu\run_syn.py conv --flow all
.venv-stalyanpu\Scripts\python syn\stalyanpu\run_syn.py top  --flow map
.venv-stalyanpu\Scripts\python syn\stalyanpu\run_syn.py chain --flow none
```

`--flow map` yalnız sentez, `pnr` arayüz + yerleşim/yolbulma, `all` ikisi,
`none` yalnız mevcut raporları özetler. Raporlar
`syn/stalyanpu/<ad>/outflow/<proje>.{map,place,timing}.rpt` altındadır.

## M5 bulguları

### Ti375 DSP sütun kısıtı

Cihazda 1344 DSP48, 28 sütun × 48 blok olarak dizilidir ve CASCIN/CASCOUT
zinciri sütun dışına çıkamaz. Deney sonuçları (yalnız dizi, `chain`
projesi):

| Deneme | DSP | Sonuç |
|---|---|---|
| 24 zincir × 32 | 768 | yerleşti, 269 MHz |
| 28 zincir × 32 | 896 | yerleşti, 263 MHz |
| 30 zincir × 32 | 960 | placer iç hatası (site yok) |
| 32 zincir × 32 | 1024 | placer iç hatası |
| 64 zincir × 16 | 1024 | placer iç hatası |
| 24 zincir × 43 | 1032 | yerleşti, 256 MHz |
| 128 zincir × 8 | 1024 | yerleşti, 258 MHz |

Yani 32 uzunluklu kaskadlardan en fazla 28 tane yerleşir (sütun başına bir).
Çözüm: `snpu_pe_chain` zinciri `CASC_LEN=8` ile dört fiziksel kaskada böler;
parça toplamları SRL gecikme hatlarıyla hizalanıp iki seviyeli kayıtlı
toplama ağacında birleşir. Zincir gecikmesi CHAIN_LEN+2'den
CHAIN_LEN+2+log2(CHAIN_LEN/CASC_LEN) çevrime çıkar. Bu yapıyla 32×32 dizi
tek başına 258 MHz kapatır (maliyet: 4,6k EFX_ADD, 9,9k SRL8).

### RAM çıkarımı düzeltmeleri

- Epilog parametre ve SiLU tabloları 2 boyutlu dizilerdi; Efinity bunları
  32k+ FF'e açıyordu. Kanal başına mantık `snpu_ep_lane` modülüne taşındı:
  her kanal 16×64 parametre RAM'i ve 256×8 tablo RAM'i tutar, okumalar
  `adv` etkiniyle kayıtlıdır (RAM10'un RE girişine eşlenir). Tablo okuması
  boruya bir aşama ekler.
- `snpu_maxpool5` satır tamponu koşullu okuma yüzünden FF'e açılıyordu
  (166k FF). Tek RAM'e `{slot, sütun}` adresiyle taşındı; satır kalıntısı
  (mod 5) küçük sayaçlarla izlenir, kenar dolgusu okuma verisinin yanına
  kayıtlı bir bayrakla eklenir.
- Residual yeniden ölçekleme tek aşamada çarpan + kaydırıcı taşıyordu
  (kritik yol 6,1 ns). Kanal borusu bölündü: fark (s6), çarpım (s7),
  kaydırma (s8), toplama + doyurma (çıkış). Yuvarlama sabitleri statik
  cfg'den kayıtlı üretilir.
- Requant yolu da bölündü: yuvarlama toplamı (4a), 50-bit kaydırma (4b),
  sıfır noktası + doyurma (4c). Doyurma karşılaştırması bit 49..7 eşitliği
  ile yapılır.
- Adres üreteci satır çarpımını tek çevrimde topluyordu (5,4 ns). Çıkışa
  iki aşamalı boru eklendi: a0 satır/sütun parçaları, a1 satır çarpımı,
  çıkış aşaması toplam. Tüm piksel bayrakları ve latch/sub boruyla taşınır.
  Bu boru döşeme sonu bayrağını da geciktirdiği için S_PASS_WAIT korumasına
  borudaki bekleyen tile_end koşulu eklendi (banka erken değişimi hatası).
- Biriktirici RMW yolu (RAM okuma + 32-bit toplama + RAM yazma tek
  çevrimde) bölündü: toplam s2'de kayıtlanır, yazma bir çevrim sonra iner.
  İlk geçiş seçimi de yazma kademesine taşındı, bayrak yalnız yazma muxunu
  sürer. Piksel tekrarı için alt sınır 3 çevrime çıktı (döşeme ≥ 4 piksel).
- Kanal başına cfg kopyaları: residual çarpan/kaydırma/zp alanları her
  kanalda yerel yazmaca alınır, 32 kanala yayılan cfg ağları yoldan çıkar.
- Sequencer'daki tüm komut adresi çarpımları (dolgu, ağırlık uzunluğu,
  residual, out_base, maxpool uzunluğu, döşeme geometrisi) ya sürekli
  kayıtlı çarpımlara ya da artımlı toplayıcılara dönüştürüldü; satır
  aralığı türetimi üç kısa faza bölündü.
- rd_dma komut toplamı (len*n0*n1*n2) kabulden sonra altı çevrimde, iki
  çevrimde bir çarpımla hesaplanır; zincir adresleri (i+1)*s çarpımları
  yerine seviye başına koşan toplayıcılardan gelir.
- Üst seviye çıkış adresi: plane*out_ps çarpımı out_ps değişince yeniden
  yürüyen 16 girişli bir tabloya, satır terimi koşan toplama dönüştü.
- Taşma bayrağı toplama iki kayıtlı adımda (kaskat başına, sonra zincir).
- Geniş veri yolu yazmaçlarından (acc psum/sum, kanal boru kademeleri)
  reset kaldırıldı; `min-sr-fanout` 64 ile reset sürücüleri çoğaltılır.

### Efinity notları

- `12'(...)` boyut dönüşümü (SystemVerilog) verilog_2k kipinde kabul
  edilmez; GEOMETRY sabiti kaydırma/maskeyle yazıldı.
- `use-logic-for-small-mem` eşiği 8'e çekildi; 4 girişli döşeme kuyruğu
  mantıkta kalır, 16 girişli parametre RAM'leri RAM10'a gider.
- Sarmalayıcı portları arayüzde eksikse pnr sürmez; `pll_locked` tasarım
  portu olarak eklenmelidir (kilit çıkışı çekirdeğe iner).

## M7 entegrasyonu (ti375_oob, 2026-09-10)

Tam tasarım `ti375_oob.xml` ile derlenir (`efx_run ti375_oob --prj -f map|pnr|pgm`).
Bağlantı özeti:

| Konu | Bağlantı |
|---|---|
| Veri düzlemi | `snpu_top` `gAXIM_5to1_switch` `MDNN=3` yuvasında, 128-bit, `io_ddrMasters_0_clk` (250 MHz). Anahtar AXI ID taşımaz (hepsi 0); `snpu_rd_dma` yanıtları ihraç sırasıyla eşler (8 derinlikli sıra FIFO'su) |
| CSR | Yumuşak SoC (`EfxSapphireFCU`) `sp_apbSlave_0` penceresinin üst yarısı: `PADDR[14]=1` NPU, `PADDR[14]=0` gDMA. Yazılım tabanı `0xF810_4000` (APB slave 0 `0xF810_0000` + 0x4000). `rtl/snpu_apb_cdc.v` toggle köprüsü 200 MHz peri saatinden 250 MHz NPU saatine geçirir |
| Sert SoC APB | `io_apbSlave_0` bu yapılandırmada sürücüsüz; sabite bağlı (PREADY=1, veri 0) |
| Kesme | `irq_o` iki FF ile peri saatine geçer, üst seviye `userInterruptI` (sert SoC PLIC 9) |
| Reset | `io_ddrMasters_0_reset` iki FF ile yeniden tamponlanır (`npu_rst`); `min-sr-fanout` 64 |

Zamanlama kapanışı entegrasyonda dört ek düzeltme istedi: agen sınır
karşılaştırması `a1` kademesine alındı, maxpool/motor çıkış seçimi
(`mp_busy_q`) ve biriktirici banka boşta işareti (`bank_free_q`)
kayıtlandı, `snpu_rd_dma` komut toplamı çarpımları (32×16) kayıtlı iki
16×16 yarıya ve bir kaydırmalı toplama bölündü (DSP çıkışından DSP girişine
kayıtsız yol kalmadı). Adımlar: -0,162 → -0,088 (bank_free) → -0,028
(rd_dma) → seed/effort taraması (seed 2: -0,013, seed 3: -0,024, seed 4:
-0,126, **seed 1 effort 3: +0,005**). Proje `placer_effort_level` 3'e
alındı. Değişiklikler motor (`conv_tiles`, `conv_res`) ve ağ (`net` grubu,
4/4) testlerinde PASS ile doğrulandı. CDC raporu
(`outflow/ti375_oob.cdc.rpt`) senkronizer uyarısı vermez.

Sonuçlar (map/pnr, 2026-09-10):

| Ölçüt | Değer |
|---|---|
| LUT4 / FF | 92,4k / 85,7k |
| DSP48 / RAM10 | 1217 / 1478 |
| `io_ddrMasters_0_clk` | 250 MHz, slack **+0,005 ns** (0 negatif yol, seed 1, effort 3) |
| Diğer saatler | pozitif (peri +0,24 ns; sd/rgmii/tse geniş) |
| Bitstream | `outflow/ti375_oob.bit` / `.hex` (`efx_run -f pgm`) |

## Kaynak durumu (map, 2026-09-02)

| Blok | LUT4 | FF | ADD | SRL8 | DSP48 | RAM10 |
|---|---|---|---|---|---|---|
| snpu_conv_unit | 31,8k | 38,2k | 15,9k | 10,5k | 1157 | 1110 |
| snpu_top | 45,7k | 44,8k | 16,8k | 10,5k | 1186 | 1149 |

DSP dağılımı: 1024 dizi + 128 epilog (kanal başına 2 requant + 2 residual)
+ seq/rd_dma/agen çarpımları. RAM10 dağılımı: ibuf 512, acc 410, epilog
prm/lut 160, wfifo 26, maxpool 26. Cihaz payları: DSP %88, RAM10 %43,
XLR %25 dolayında.

## Zamanlama durumu (2026-09-02)

- Dizi tek başına (32×32, CASC_LEN=8): 258 MHz, slack +0,125 ns.
- Motor (`conv`): en iyi koşum **256 MHz, slack +0,101 ns** (kapı 250 MHz
  sağlandı). Ara adımlar: 149 MHz (bölünmemiş epilog) → 195 (residual
  bölme) → 225 (agen adres borusu) → 256 (requant bölme).
- Tam `snpu_top`: 139 MHz'den başlayıp rd_dma, seq, çıkış adresi, acc ve
  reset düzeltmeleriyle **244 MHz (slack -0,105 ns)** bandına geldi.
  Kalan açık tek tek yollarda değil; %88 DSP doluluğunda yerleşim
  gürültüsü koşudan koşuya ±0,3 ns oynatıyor. Kapanış için placer effort
  3 ve gerekirse `efx_run_pnr_sweep` (seed taraması) kullanılacak; nihai
  sayı README durum bandındadır.
