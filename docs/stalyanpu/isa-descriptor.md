# StalyaNPU ISA: descriptor, CSR ve blob formatı

Tek doğru kaynak `ip/stalyanpu/py/stalyanpu/backend/isa.py` dosyasıdır; C başlığı
`ip/stalyanpu/sw/include/stalyanpu_isa.h` oradan üretilir (`python -m stalyanpu gen-header`)
ve `tests/test_isa.py` ikisinin ayrışmadığını denetler. RTL sabitleri `snpu_pkg.vh` içinde
aynı değerleri taşır. Bu sayfa insan okur sürümüdür; ayrıntı çelişirse isa.py geçerlidir.

## Yürütme modeli

- CPU, DDR'a ardışık 128 baytlık descriptor'lar yazar, `DESC_BASE` ve `DESC_COUNT` ile
  `CTRL.start` verir. `snpu_seq` listeyi sırayla yürütür; her descriptor bir katmandır,
  döşeme (tile) döngülerini donanım kendisi çevirir.
- Kare bitince (`LAST` bayraklı descriptor veya `END` opcode) `IRQ_STATUS.done` kalkar ve
  `userInterruptI` (PLIC 9) üzerinden CPU'ya gider. Temizleme W1C.
- `WAIT_PREV` bayrağı, girişi bir önceki descriptor'ın çıktısı olan katmanlarda önceki
  yazmaların tamamlanmasını bekletir. Ağırlık, parametre ve LUT akışları bir sonraki
  descriptor için önceden çekilir.
- Hata (CRC, opcode, sürüm, AXI yanıtı, zaman aşımı) `STATUS[15:8]` koduna yazılır,
  `IRQ_STATUS.error` kalkar, liste durur. `CTRL.abort` veya soft reset ile çıkılır.

## Tensör düzeni: NC32HW

`tensor[cg][y][x][32]` bayt, `cg = ceil(C/32)`. Her kanal grubu (plane) `H×W×32` bayt ve
ardışıktır. Plane tabanı 64 bayt hizalı. Descriptor her kaynak için `base`, `plane_stride`
(`H·W·32`), `row_stride` (`W·32`) ve plane sayısı taşır; böylece:

- **Concat**: üretici `out_base`'i hedef tensörün plane ofsetine yazar (sıfır kopya).
- **Split**: tüketici `src0_base`'i plane alt aralığına alır (sıfır kopya).
- **Upsample ×2**: `UPS0/UPS1` bayrağı ile okuyucu `y>>1` satırını okur, pikseli ikiler.
- **İki kaynaklı giriş** (`TWO_SRC`): src1 plane'leri src0 plane'lerinin ardına eklenir
  (neck'te upsample edilmiş P5 + P4 skip gibi farklı tensörlerden concat).

YOLOv8s'te tüm kanal ofsetleri 32'nin katıdır. Ön yüz (`frontend/patterns.py`) 32'ye
bölünmeyen Concat/Split'i reddeder; bu durum CPU'ya kesim noktası olur.

## Descriptor (32 × u32, little endian)

| Kelime | Alan(lar) | Açıklama |
|-------:|-----------|----------|
| 0 | `opcode[7:0]`, `flags[23:8]`, `version[31:24]` | Opcode ve bayraklar; `version` = ISA_VERSION (1) |
| 1 | `in_h[15:0]`, `in_w[31:16]` | Giriş boyutu |
| 2 | `out_h[15:0]`, `out_w[31:16]` | Çıkış boyutu |
| 3 | `ic[15:0]`, `oc[31:16]` | Gerçek kanal sayıları (dolgu öncesi) |
| 4..6 | `src0_base`, `src0_plane_stride`, `src0_row_stride` | Kaynak 0 |
| 7 | `src0_planes[15:0]`, `src1_planes[31:16]` | Okunacak plane sayıları |
| 8..10 | `src1_base`, `src1_plane_stride`, `src1_row_stride` | Kaynak 1 (`TWO_SRC`) |
| 11 | `w_base` | Paketlenmiş ağırlıklar (tüketim sırasında: `[oct][icg][tap][chain][dsp][2B]`) |
| 12 | `w_bytes_per_oct` | OC döşemesi başına ağırlık baytı |
| 13 | `param_base` | OC başına `{bias i32, mult u16, shift u8, zp_pre i8}` 8 bayt |
| 14 | `lut_base` | 256 baytlık aktivasyon tablosu, SiLU yoksa 0 |
| 15..17 | `out_base`, `out_plane_stride`, `out_row_stride` | Çıkış |
| 18..20 | `res_base`, `res_plane_stride`, `res_row_stride` | Residual (`RESIDUAL`) |
| 21 | `zp_in`, `zp_out`, `zp_res`, `zp_out2` (4 × i8) | Sıfır noktaları |
| 22 | `res_mult_a[15:0]`, `res_shift_a[23:16]` | Residual yolunda aktivasyonun yeniden ölçeği |
| 23 | `res_mult_b[15:0]`, `res_shift_b[23:16]` | Residual tensörünün yeniden ölçeği |
| 24 | `tile_rows[15:0]`, `tile_px[31:16]` | Döşeme başına çıkış satırı ve pikseli |
| 25 | `n_tiles[15:0]`, `ring_rows[31:16]` | Döşeme sayısı, ibuf halkasında tutulan giriş satırı |
| 26 | `pad_t`, `pad_l`, `pad_b`, `pad_r` (4 × u8) | Dolgu (değer `zp_in`) |
| 27 | `k[3:0]`, `stride[7:4]` | Çekirdek (1/3, MAXPOOL5 için 5) ve adım (1/2) |
| 28..29 | ayrılmış (0) | |
| 30 | `tag` | Hata ayıklama etiketi, `TAG` CSR'ında yankılanır |
| 31 | `crc32` | 0..30 kelimelerinin CRC32'si (zlib) |

### Opcode'lar

| Ad | Değer | İşlev |
|----|------:|-------|
| NOP | 0x00 | Atla |
| CONV | 0x01 | Konvolüsyon + epilog (bias, requant, LUT, residual) |
| MAXPOOL5 | 0x02 | 5×5 s1 p2 maksimum havuzlama (SPPF) |
| COPY | 0x03 | Kopya (upsample'lı kaynak → concat hedefi gibi durumlar) |
| BARRIER | 0x04 | Önceki tüm yazmaların bitmesini bekle |
| END | 0xFF | Liste sonu, IRQ |

### Bayraklar (`flags` içindeki bit)

| Bit | Ad | Anlam |
|----:|----|-------|
| 0 | SILU | Aktivasyon tablosunu uygula |
| 1 | RESIDUAL | Aktivasyon sonrası residual tensörünü ekle |
| 2 | IRQ | Bu descriptor bitince kesme üret |
| 3 | LAST | Listenin son descriptor'ı |
| 4 | UPS0 | Kaynak 0 en yakın komşu ×2 büyütülerek okunur |
| 5 | UPS1 | Kaynak 1 için aynı |
| 6 | TWO_SRC | Kaynak 1 kullanılır |
| 7 | L0_MODE | Stem modu: 3×3×3 pencere tek 27'lik vektör (Faz 1.5) |
| 8 | WAIT_PREV | Önceki descriptor'ın yazmaları bitmeden okumaya başlama |
| 9 | DEBUG_DUMP | Descriptor başına done kesmesi (hata ayıklama) |

## Epilog aritmetiği (referans: `refmodel/fixedpoint.py`)

```
s   = acc32 + bias                      (int32, taşma derleyicide denetlenir)
q   = ((s * mult) + 2^(shift-1)) >> shift    mult ∈ [2^15, 2^16), shift ∈ [0, 47], yarım yukarı
q   = sat8(q + zp_pre)                  (zp_pre param bloğundan, OC başına)
y   = LUT[q + 128]                      (SILU bayrağı; tablo çıkışı zp_out ölçeğinde)
out = sat8( ((y-zp_out)·mult_a + 2^(sa-1)) >> sa + ((r-zp_res)·mult_b + 2^(sb-1)) >> sb + zp_out2 )   (RESIDUAL)
```

## CSR haritası (APB, `PADDR[14]=1` penceresi)

| Ofset | Ad | Erişim | Açıklama |
|------:|----|--------|----------|
| 0x00 | ID | RO | 0x534E5055 (`SNPU`) |
| 0x04 | VERSION | RO | donanım sürümü |
| 0x08 | GEOMETRY | RO | `n_chain[7:0]`, `chain_len[15:8]`, `log2(p_max)[19:16]`, `ibuf_kb[31:20]` |
| 0x0C | CTRL | RW | bit0 start (kendini temizler), bit1 abort, bit2 soft reset |
| 0x10 | STATUS | RO | bit0 busy, `[15:8]` hata kodu, `[31:16]` descriptor indeksi |
| 0x14 | DESC_BASE | RW | Descriptor listesi adresi (128 bayt hizalı) |
| 0x18 | DESC_COUNT | RW | Descriptor sayısı |
| 0x1C | IRQ_STATUS | W1C | bit0 done, bit1 desc done, bit2 error, bit3 timeout |
| 0x20 | IRQ_MASK | RW | 1 = ilgili bit kesme üretir |
| 0x24 | CYCLE_CNT | RO | start'tan beri meşgul çevrim |
| 0x28 | STALL_IBUF | RO | dizi giriş verisi bekledi |
| 0x2C | STALL_WGT | RO | dizi ağırlık bekledi |
| 0x30 | STALL_ACC | RO | dizi biriktirici bankı bekledi |
| 0x34 | STALL_WR | RO | epilog yazma yolunu bekledi |
| 0x38 | DESC_DONE | RO | tamamlanan descriptor sayısı |
| 0x3C | TAG | RO | yürüyen descriptor'ın tag'i |

Hata kodları: 0 yok, 1 opcode, 2 CRC, 3 sürüm, 4 AXI okuma, 5 AXI yazma, 6 zaman aşımı,
7 geometri (descriptor donanım geometrisine sığmıyor).

## Ağırlık ve parametre paketleme (`backend/weightpack.py`)

- Ağırlıklar tüketim sırasında: `[oct][icg][tap][chain][dsp][2 bayt]`; oct 64 kanallık çıkış
  döşemesi, icg 32 kanallık giriş grubu, tap `(ky, kx)` satır öncelikli, chain c çıkış kanalları
  `2c` (düşük lane, bayt 0) ve `2c+1` (yüksek lane, bayt 1), dsp i giriş kanalı `icg·32+i`.
  Dolgu kanalları 0. Bir `(oct, icg, tap)` bloğu 2 KB (32 zincir × 32 DSP × 2 bayt).
  `w_bytes_per_oct = n_icg · k² · 2048`.
- Parametre bloğu OC başına 8 bayt: `int32 bias` (giriş zp katlanmış), `uint16 mult`,
  `uint8 shift`, `int8 zp_pre` (requant sıfır noktası). OC, 64'e dolgulanır (dolgu: bias 0,
  mult 2^15, shift 15).
- Aktivasyon tablosu 256 bayt, indeks `kod + 128`.
- Descriptor `zp_out` alanı LUT **sonrası** aktivasyonun sıfır noktasıdır (residual toplama ve
  dolgu kanalları bunu kullanır); requant zp'si param bloğundadır.

## Tampon yerleşimi (`backend/alloc.py`)

- Concat çıkışı tek tampon; CONV/MAXPOOL5 üreticileri kendi plane ofsetine yazar; Split
  çıkışları sırayla concat girişiyse split kaynağı da aynı tampona yerleşir (C2f deseni).
- Split çıkışları kaynak yerleşiminin plane alt aralığıdır; Upsample görünümdür (`UPS0/1`).
- Girişi görünüm olan concat (neck'teki Resize + skip) **sanal**dır: tüketici `TWO_SRC` ile
  iki kaynak okur. İkiden fazla kaynak COPY gerektirir (YOLOv8s'te yok, emitter hata verir).
- Yaşam süresi tabanlı first-fit, 4 KB hizalı; giriş ve çıkış tensörleri scratch başında sabit.
- YOLOv8s 640×384: 66 descriptor, 52 tampon, scratch 11,6 MB, blob 11,3 MB (parametre 11,3 MB).

## Blob (`frame.bin`)

4 KB başlık + descriptor tablosu + parametre bölgesi (ağırlık, bias/mult/shift, LUT), her
bölüm 4 KB hizalı. Başlık alanları `isa.BLOB_HEADER` (15 × u32, ofset 0): magic, version, base, size, desc_off,
desc_count, param_off, param_size, scratch_base, scratch_size, input_off, input_bytes,
n_outputs, outputs_off, crc32 (crc32 kelimesi hariç tüm blob). Çıkış tablosu başlıkta ofset
0x3C'ten başlar, adlar tabloyu izler. Çıkış tablosu girdileri (`isa.OUTPUT_ENTRY`): offset, h, w,
c, scale_q16, zp, name_off. Derleyici blob'u `--base` adresine bağlar; scratch bölgesi
(aktivasyonlar) `--scratch` ile ayrı verilir. Emitter: `backend/emit.py`; yorumlayıcı `backend/interp.py`
aynı blob'u yürütüp `QRunner` ile bit bit karşılaştırılır (`stalyanpu compile --check`).
