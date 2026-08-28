# StalyaNPU mimarisi

RTL öneki `snpu_`, dizin `ip/stalyanpu/rtl/`. Geometri sabitleri `snpu_pkg.vh` ve Python
tarafında `hwcfg.py` (`full2048` / `small256` presetleri) aynı değerleri taşır.

## Özet tablo

| Konu | Karar |
|------|-------|
| Dizi | 1024 DSP48 DUAL = **2048 INT8 MAC/çevrim**; 32 kaskad zinciri (`N_CHAIN`) × 32 DSP (`CHAIN_LEN`). Zincir = 32 giriş kanalı (IC), DSP = 1 IC × 2 çıkış kanalı (OC, lane başına 1). Döşeme: **32 IC × 64 OC, çevrimde 1 çıkış pikseli** |
| Veri akışı | Ağırlık-sabit sistolik kaskad: ağırlık DSP `B_REG`'de (CE = latch), iact `A`'dan 32 kademeli çarpıklıkla (skew) akar, kısmi toplamlar `CASCIN/CASCOUT` zincirinde. DSP içinde birikim yok: 32 çarpım ≤ 2^19, 24-bit lane taşmaz. Tap ve IC-grubu birikimi 32-bit RAM10 biriktiricide |
| Biriktirici | `snpu_acc`: 2 bank × 1024 px × 64 OC × 32 bit (2048-bit geniş RMW, 64 toplayıcı), 412 RAM10. En kötü 4608 terim × 2^14 = 2^26,2 < 2^31. Bank değişince epilog boşaltır |
| 3×3 / 1×1 / stride 2 | Aynı makine: tap ofsetleri ibuf okuma adresinde, im2col yok. Dolgu değeri `zp_in` |
| İlk katman (IC=3) | Faz 1: 8 kanala dolgu (`stem_ic_pad`), %4,7 kullanım, 601 kçevrim. Faz 1.5: `L0_MODE` im2col-27 (3×3×3 pencere tek 32'lik IC vektörü, 16 bank ibuf'tan 6 kelime aynı çevrimde) |
| Epilog | 32 OC/çevrim: bias → requant (u16 çarpan × 2^-s, yarım yukarı, doyur, zp) → 256 girişli SiLU LUT (int8→int8, katman başına yüklenir, çift tamponlu) → residual Add (iki ölçekli) → int8 paketleme → yazma DMA. `n_pass ≥ 2` olduğundan hesap arkasına gizlenir |
| Tensör düzeni | **NC32HW** `[C/32][H][W][32]`. Concat = üretici plan ofseti, Split = tüketici plan alt aralığı, Upsample ×2 = okuyucu modu, iki kaynaklı giriş (`TWO_SRC`) neck concat'leri için. YOLOv8s'te tüm ofsetler 32'nin katı |
| SPPF | `snpu_maxpool5` akış motoru: 4 satır tamponu, 5 sütun pencere, plane başına 1 kelime/çevrim, W ≤ 128 |
| DFL / sigmoid / NMS | Hard RISC-V @1 GHz, < 1 ms (int8 eşik karşılaştırması, yalnız geçen ~200 anchor için softmax) |
| DDR | Kendi AXI4 okuma DMA'sı (3 kanal: ibuf, ağırlık, residual/param/descriptor; 4 outstanding 16-beat burst) + yazma DMA'sı; `AXI_DW` 128/256. Faz 1: `gAXIM_5to1_switch` `MDNN=3` yuvası. Faz 2 (M7): `axi_target0` 256-bit dedicated port |
| Kontrol | DDR'daki 128 B descriptor listesi, `snpu_seq` yürütür; kare başına 1 IRQ (`userInterruptI`, PLIC 9, `rtl/pulse_sync.v`); CSR mevcut APB penceresi `PADDR[14]=1`; perf sayaçları. Bkz. [isa-descriptor.md](isa-descriptor.md) |
| Saat | `snpu_clk = io_ddrMasters_0_clk` (250 MHz, mevcut PLL çıkışı; AXI ile aynı domain). CDC yalnız APB CSR (200 MHz) ve IRQ. 300 MHz dizi saati uzatma |
| Nicemleme | Ağırlık int8 simetrik OC başına; aktivasyon int8 tensör başına asimetrik; zp bias'a katlanır; Concat/Add grupları ölçek birleştirme |

## Döngü yapısı (derleyici üretir, `snpu_seq` yürütür)

```
for tile in çıkış satırı döşemeleri (P = rows·W_out ≤ P_MAX, giriş ayak izi ≤ ibuf/2):
    ibuf halkasında giriş satırları [r_lo, r_hi) hazır (rd DMA, örtüşük)
    for oct in ceil(OC/64):
        for icg in ceil(IC/32):
            for tap in K·K:                       # pass = (icg, tap)
                ağırlık[oct][icg][tap] (2 KB) gölgeden B_REG'e latch (skew ile)
                for p in 0..P-1:                  # çevrimde 1 piksel
                    iact = ibuf[row(p)+ky-pad, col(p)·s+kx-pad, icg]  (dışarısı → zp_in)
                    psum[64] = zincir(iact)
                    acc[bank][p][0..63] (+)= psum   (ilk pass '=')
        bank değiştir; epilog boşaltırken sonraki oct/tile birikir
```

Ağırlık dizilimi DDR'da tüketim sırasındadır (`[oct][icg][tap][chain][dsp][2B]`), okuyucu
düz akış. Pass başına ek yük ≈ 40 çevrim (latch + skew); P=240'ta (P5) %17, P≥960'ta ≤ %4.

## DSP48 sarmalayıcı ve zincir (M0'da yazıldı ve doğrulandı)

`snpu_dsp_mac2.v`: `MODE="DUAL"`, `A={sext11(x), x}`, `B={sext10(w_hi), w_lo}`,
`A_REG=B_REG=P_REG=W_REG=1`, `O_REG=LAST`, `M_SEL="P"`, `N_SEL=CONST0|CASCIN`,
`W_SEL="X"`, `CASCOUT_SEL="W"`, `SIGNED=1`, `RST_SYNC=1`; yalnız `B_REG_USE_CE=1` → `CE`
ağırlık latch'i. `SNPU_SIM_BEHAV` ile davranışsal ikiz. Gecikme: x örneklenen kenar s →
`casc_o` s+2, `o` s+3.

`snpu_skew.v`: üçgen gecikme hattı (lane i, i çevrim). `snpu_wshadow.v`: zincir başına
32 × 16-bit gölge, 256-bit dolum kelimeleri (32 zincir için pass başına 64 çevrim).
`snpu_pe_chain.v`: 32 DSP + gölge + kaskad; çıkış s + CHAIN_LEN + 2. Latch darbesi s
kenarında örneklenen vektörden itibaren tüm zincirde geçerlidir; yeni dolum son DSP
latch'ledikten (s + CHAIN_LEN - 1) sonra başlayabilir.

## Konvolüsyon motoru (M3'te yazıldı ve doğrulandı)

`snpu_conv_unit`: agen → ibuf (1 çevrim) → zp kapısı → dizi → acc → epilog. Kontrol
kuralları (M3'te hata ayıklamayla sabitlendi):

- Dizi yan bandı (valid/first/last/tile_end/p) veriyle aynı gecikmede (CHAIN_LEN+2) taşınır.
- `tile_end` diziden geçerken (`end_pending`) bir sonraki döşeme başlatılmaz; bank ancak
  biriktiricideki `tile_done` sonrası değişir.
- Epilog, bank release'ini son sözcüğü stage 2'ye aldığı kenarda verir (`drain_open`), böylece
  duraklarda `rd_bank` değişimi uçuştaki veriyi bozamaz; RAM okuması epilog duraklarında tutulur.
- Residual sözcüğü gelmeyince hat durur ama tüketilen çıkış sözcüğü tekrar sunulmaz.
- Ağırlık akışı döşeme başına tekrar tüketilir (DMA tekrar okur, perf modeliyle uyumlu).
- Geçiş başına ek yük: agen 3 çevrim + gölge dolumu (N_CHAIN·WORDS_PER_CHAIN çevrim, önceki
  geçişle örtüşür; P küçükse `shadow_ready` bekler).

## On-chip bellek planı

| Tampon | Düzen | Boyut | RAM10 |
|--------|-------|-------|------:|
| `snpu_ibuf` giriş halkası | 16 bank × 1024 × 256 bit, düşük bit interleave; A portu dizi/L0 okuma, B portu DMA yazma | 512 KB | 416 |
| `snpu_acc` | 2 bank × 1024 × 2048 bit | 512 KB | 412 |
| `snpu_wfifo` | 1024 × 256 bit | 32 KB | 26 |
| Gölge ağırlık | 1024 × 16 bit FF | 2 KB | 0 (16k FF) |
| SiLU LUT | 32 lane, çift tablo | 512 B ×2 | 16 |
| OC parametreleri | 512 OC × 8 B, çift tampon | 8 KB | 8 |
| Residual / yazma / okuma FIFO'ları | | 36 KB | 40 |
| `snpu_maxpool5` satır tamponları | 4 × 128 px × 32 B | 16 KB | 13 |
| Descriptor / kontrol | | | 2 |
| **Toplam** | | | **≈ 933** (boşun %40) |

Dizi çevresi register maliyeti ≈ 35k XLR (gölge 16k, skew hattı ×4 kopya 16k, fanout).

## Kaynak tahmini

| Blok | DSP48 | RAM10 | XLR |
|------|------:|------:|----:|
| `snpu_pe_array` (32 × 32 `snpu_dsp_mac2`) | 1024 | 0 | 3k |
| Gölge + skew + fanout kopyaları | 0 | 0 | 35k |
| `snpu_acc` | 0 | 412 | 6k |
| `snpu_ibuf` + agen + ctl | 0 | 416 | 11k |
| `snpu_wfifo` | 0 | 26 | 1,5k |
| `snpu_epilogue` (32 × requant 2 DSP, 32 × resadd 1 DSP, LUT, paketleyici) | 96 | 24 | 7k |
| `snpu_rd_dma` + `snpu_wr_dma` | 0 | 40 | 8k |
| `snpu_maxpool5` | 0 | 13 | 2k |
| `snpu_seq` + `snpu_csr` | 0 | 2 | 3,5k |
| **Toplam** | **1120** | **933** | **≈ 77k** |
| Boş (OpenEye çıkınca) | 1319 | 2359 | 289k |
| Kullanım | %85 | %40 | %27 |

DSP sıkı. Emniyet supapları: residual çarpanları LUT'a (−32 DSP), requant yarı hız (−32 DSP).

## Performans (M0 modeli, 640×384)

Bkz. [decision-record.md](decision-record.md) tablosu. 2,4 GB/s etkin DDR ile 7,60 M
çevrim = 30,4 ms → **32,9 fps** (%55 kullanım); 4,5 GB/s ile 40,8 fps; hesap sınırı 44 fps.
Baskın gruplar: Detect.P3 (%13), L2.c2f (%11), L4.c2f (%8), L0 (%8). DDR'a bağlı katmanlar:
tüm 1×1'ler, L0/L1/L2 (büyük düşük kanallı haritalar), SPPF havuzları.

Kapı yorumu ve plan düzeltmeleri karar kaydındadır: dedicated port M7'ye çekildi, erken
katman füzyonu M9'a eklendi.

## RTL modül listesi ve yapım sırası

| Dosya | Rol | Adım |
|-------|-----|-----:|
| `snpu_pkg.vh` | sabitler | M0 ✔ |
| `snpu_dsp_mac2.v` | DSP48 DUAL sarmalayıcı | M0 ✔ |
| `snpu_skew.v` | üçgen gecikme hattı | M0 ✔ |
| `snpu_wshadow.v` | gölge ağırlık | M0 ✔ |
| `snpu_pe_chain.v` | 32 DSP kaskad zinciri | M0 ✔ |
| `snpu_pe_array.v` | N_CHAIN zincir, paylaşımlı skew hatları (SKEW_COPIES), yan bant gecikme hattı (LAT+1) | M3 ✔ |
| `snpu_acc.v` | 2 bank × P_MAX × N_OC × 32 bit RMW biriktirici; okuma portu dizi/epilog paylaşımlı, epilog okuma-etkin (`ep_re`) | M3 ✔ |
| `snpu_ibuf.v` | IBUF_WORDS × 256 bit basit çift portlu RAM | M3 ✔ |
| `snpu_agen.v` | Döngü yapısı (tile → oct → icg → tap → piksel), zp kapısı, latch, tile kuyruğu; giriş satırları ibuf'ta hazır varsayılır (halka yönetimi M4) | M3 ✔ |
| `snpu_wfifo.v` | Ağırlık FIFO + gölge dolum sıralayıcısı (latch sonrası CHAIN_LEN+1 bekleme) | M3 ✔ |
| `snpu_epilogue.v` | 32 lane: bias, u16 çarpan, yuvarla/kaydır/doyur, LUT, residual, 256-bit paketleme; tek `adv` etkin hattı | M3 ✔ |
| `snpu_conv_unit.v` | Yukarıdakilerin birleşimi; DMA/sequencer/CSR olmadan tam katman motoru | M3 ✔ |
| `snpu_rd_dma.v`, `snpu_wr_dma.v` | AXI4 master'lar | M4 |
| `snpu_seq.v`, `snpu_csr.v`, `snpu_top.v` | sequencer, CSR (APB + CDC), üst seviye | M4 |
| `snpu_maxpool5.v` | SPPF | M4 |
| `ti375_oob_top.v` yaması | OpenEye/gDMA_dnn çıkar, `snpu_top` bağla | M7 |

Her adımın kendi iverilog TB'si vardır; M5'te dizi + acc tek başına Efinity map/pnr kapısı
(250 MHz, ≥ 0,3 ns slack).

## Riskler (sıralı)

1. DSP48 DUAL/kaskad silikon davranışı sim modelinden farklı → tek zincir board smoke testi (M5 öncesi); tüm DSP parametreleri tek dosyada.
2. 250 MHz kapanışı (2048-bit acc RMW, iact fanout, 32'lik zincir yerleşimi) → dizi-tek sentez kapısı, `CHAIN_LEN=16` + fabric toplayıcı yedeği, son çare 200 MHz (model: 29,3 fps @2,4 GB/s).
3. DDR bant genişliği (model DDR'a bağlı) → dedicated port M7'de, erken katman füzyonu, stall sayaçları.
4. DSP bütçesi %85 → emniyet supapları.
5. PTQ mAP düşüşü → M1 kapısı ≤ 2,0; yüzdelik/MSE kalibrasyon; QAT yedeği.
6. Derleyici doğruluğu → aynı Python kodu altın üretir, `interp ≡ runner` kapısı.
7. iverilog süresi → katman-katman paralel, `small256`, Verilator opsiyonel.
