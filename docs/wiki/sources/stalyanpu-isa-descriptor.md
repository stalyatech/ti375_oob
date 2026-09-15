---
title: "Kaynak: StalyaNPU ISA (descriptor, CSR, blob)"
type: source
source_file: "ip/stalyanpu/docs/isa-descriptor.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, isa, descriptor, csr, blob, nc32hw]
---

# Kaynak: StalyaNPU ISA (descriptor, CSR, blob)

## Özet
[[stalyanpu]] komut kümesinin insan okur sürümü. Tek doğru kaynak
`py/stalyanpu/backend/isa.py`'dir; C başlığı `sw/include/stalyanpu_isa.h` oradan üretilir ve
`tests/test_isa.py` ikisinin ayrışmadığını denetler. Belge yürütme modelini, NC32HW tensör
düzenini, 128 baytlık descriptor formatını, opcode ve bayrakları, epilog aritmetiğini, CSR
haritasını, ağırlık/parametre paketlemeyi, tampon yerleşimini ve `frame.bin` blob başlığını
tanımlar. Bugünkü sürümde CSR sayaçları board'daki adlarıyla (fill, run_idle, mac, wr_wait)
etiketlenmiş, DBG0/DBG1 üç kanallı okuma DMA'sına göre yeniden düzenlenmiş, DBG6 (çevre
mantığı sözcüğü) ve hata kodu 7'nin M9 anlamı eklenmiştir.

## Temel Çıkarımlar
- CPU ardışık 128 B descriptor'ları DDR'a yazar, `DESC_BASE`/`DESC_COUNT` ile `CTRL.start` verir; her descriptor bir katmandır, döşeme döngüsü donanımda ([[descriptor-isa]]).
- Descriptor'ın 31. kelimesi ilk 31 kelimenin zlib CRC32'sidir; hata kodu `STATUS[15:8]`'e yazılır ve liste durur.
- NC32HW (`[C/32][H][W][32]`) ile Concat, Split ve Upsample ×2 sıfır kopyadır; `TWO_SRC` iki tensörden okur.
- Sayaçlar: 0x28 fill, 0x2C run_idle, 0x30 mac, 0x34 wr_wait; board ölçüm tablolarının sütunları bunlardır.
- DBG6 (0x58) `snpu_top`'un `dbg_ext_i` portunu okur; board'da [[snpu-axi-up512]] genişleticisinin durumudur.
- Hata 7 (geometri): M9'dan itibaren bir döşemenin giriş ayak izi ibuf'un yarısını aşarsa sequencer dolum komutu vermeden durur.

## Detaylı Notlar
**Yürütme modeli.** Kare bitince (`LAST` bayrağı veya `END`) `IRQ_STATUS.done` kalkar ve
`userInterruptI` (PLIC 9) üzerinden CPU'ya gider ([[hard-soc-fabric-interrupt-path]]);
temizleme W1C. `WAIT_PREV` bir önceki descriptor'ın yazmalarını bekletir; ağırlık, parametre
ve LUT akışları sonraki descriptor için önceden çekilir. Hata (CRC, opcode, sürüm, AXI yanıtı,
zaman aşımı) `IRQ_STATUS.error` ile bildirilir; `CTRL.abort` veya soft reset ile çıkılır.

**Tensör düzeni.** Her kanal grubu (plane) `H×W×32` bayt ve ardışıktır; plane tabanı 64 bayt
hizalı. Descriptor kaynak başına `base`, `plane_stride`, `row_stride` ve plane sayısı taşır.
Ön yüz (`frontend/patterns.py`) 32'ye bölünmeyen Concat/Split'i reddeder; [[yolov8s]]'te tüm
ofsetler 32'nin katıdır.

**Descriptor alanları.** 32 × u32: opcode/flags/version; giriş ve çıkış boyutları; gerçek
IC/OC; src0 ve src1 üçlüleri ve plane sayıları; `w_base`, `w_bytes_per_oct`; `param_base`
(OC başına `{bias i32, mult u16, shift u8, zp_pre i8}`); `lut_base`; çıkış ve residual
üçlüleri; dört sıfır noktası; `res_mult_a/b`, `res_shift_a/b`; `tile_rows`, `tile_px`,
`n_tiles`, `ring_rows`; dolgu; `k` ve `stride`; `tag`; `crc32`. Opcode'lar NOP, CONV,
MAXPOOL5, COPY, BARRIER, END; bayraklar SILU, RESIDUAL, IRQ, LAST, UPS0/1, TWO_SRC, L0_MODE
(Faz 1.5, RTL'de uygulanmadı), WAIT_PREV, DEBUG_DUMP.

**Epilog aritmetiği.** `s = acc32 + bias`; `q = ((s·mult) + 2^(shift-1)) >> shift`
(mult ∈ [2^15, 2^16), shift ∈ [0, 47]); `q = sat8(q + zp_pre)`; `y = LUT[q + 128]`; residual
yolunda iki ayrı yeniden ölçek ve `zp_out2`. Referans `refmodel/fixedpoint.py`
([[int8-quantization-flow]]).

**CSR haritası.** APB, `PADDR[14]=1` penceresi, 7 bit bayt ofseti, 128 B
([[accelerator-control-plane-apb]]). 0x00 ID (`SNPU`), 0x04 VERSION, 0x08 GEOMETRY, 0x0C CTRL
(start, abort, soft reset), 0x10 STATUS (busy, hata kodu, descriptor indeksi), 0x14/0x18
DESC_BASE/COUNT, 0x1C IRQ_STATUS (W1C: done, desc done, error, timeout), 0x20 IRQ_MASK, 0x24
CYCLE_CNT, 0x28..0x34 dört stall sayacı, 0x38 DESC_DONE, 0x3C TAG. Hata ayıklama: DBG0 üç
kanalın outstanding burst, active, issue_done ve warm bitleri, sıra FIFO işaretçisi,
sequencer durumu, motor/maxpool meşgul, yazma DMA boşta; DBG1 bekleyen yazma yanıtı, üç
kanalın cmd/d valid-ready çiftleri, AXI el sıkışmaları, okuma/yazma hatası; DBG2..DBG5
yazma ölçümleri (AW bekleme, W bekleme, biten burst, beat sayısı); DBG6 genişletici durumu
(tutulan beat, okuma kuyruğu boş, sıradaki kelimenin şeridi, teslim edilen kelime, `RLAST`
sayısı, kuyruk işaretçileri). Bu sayaçlar [[board-bringup-flow]] tablolarının ve
[[analytic-performance-model]] kalibrasyonunun kaynağıdır. Hata kodları: 1 opcode, 2 CRC,
3 sürüm, 4 AXI okuma, 5 AXI yazma, 6 zaman aşımı, 7 geometri.

**Paketleme ve yerleşim.** Ağırlıklar tüketim sırasında `[oct][icg][tap][chain][dsp][2 bayt]`;
bir `(oct, icg, tap)` bloğu 2 KB; `w_bytes_per_oct = n_icg · k² · 2048`. OC 64'e dolgulanır
(bias 0, mult 2^15, shift 15). `backend/alloc.py` yaşam süresi tabanlı first-fit, 4 KB hizalı;
C2f deseninde split kaynağı concat tamponuna yerleşir; neck'teki Resize + skip concat'i
sanaldır (`TWO_SRC`); ikiden fazla kaynak COPY ister (YOLOv8s'te yok). YOLOv8s 640×384: 66
descriptor, 52 tampon, scratch 11,6 MB, blob 11,3 MB.

**Blob.** 4 KB başlık + descriptor tablosu + parametre bölgesi; başlık 15 × u32; çıkış
tablosu 0x3C'ten başlar (`OUTPUT_ENTRY`: offset, h, w, c, scale_q16, zp, name_off). Emitter
`backend/emit.py`, yorumlayıcı `backend/interp.py`; `stalyanpu compile --check` ikisini
`QRunner` ile bit bit karşılaştırır ([[stalyanpu-toolchain]]).

**CSR taban adresi.** Belge yalnız APB penceresi içindeki ofsetleri tanımlar; sistemdeki
taban adresi vermez. HEAD'de pencere sert SoC ([[efx-sapphire-hpsoc-slb]]) `io_apbSlave_0`
üzerinden `0xE810_4000`'dedir ([[stalyanpu-bringup-guide]]); M7'deki yumuşak SoC
`0xF810_4000` tabanı artık kullanılmaz. ISA belgesi bu ayrımı bilerek dışarıda bırakır.

> ❓ **Belirsiz:** DBG6'nın "board'da `snpu_axi_up512`" tanımı genişleticinin bağlı olduğu
> yapılandırmaya özgüdür; paylaşımlı port yapılandırmasında `dbg_ext_i`'nin ne taşıdığı
> belgede yazmaz.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[stalyanpu-toolchain]], [[yolov8s]], [[snpu-axi-up512]], [[efx-sapphire-hpsoc-slb]]
- İlgili kavramlar: [[descriptor-isa]], [[int8-quantization-flow]], [[board-bringup-flow]], [[analytic-performance-model]], [[accelerator-control-plane-apb]], [[hard-soc-fabric-interrupt-path]]
- Destekleyen kaynaklar: [[stalyanpu-architecture]], [[stalyanpu-toolchain-guide]], [[stalyanpu-verification-guide]], [[stalyanpu-bringup-guide]]

## Alıntılar
- "Tek doğru kaynak `py/stalyanpu/backend/isa.py` dosyasıdır ... ayrıntı çelişirse isa.py geçerlidir." (satır 3-6)
- "7 geometri (descriptor donanım geometrisine sığmıyor; M9'dan itibaren bir döşemenin giriş ayak izi ibuf'un yarısını aşarsa sequencer dolum komutu vermeden bu kodla durur)." (satır 129-130)
