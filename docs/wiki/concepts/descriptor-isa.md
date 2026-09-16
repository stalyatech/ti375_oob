---
title: "Descriptor Tabanlı ISA"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 6
tags: [isa, descriptor, csr, crc32, blob, sequencer, dbg]
---

# Descriptor Tabanlı ISA

## Tanım
[[stalyanpu]]'nun programlama modeli: CPU, her biri bir katmanı tanımlayan 128 baytlık
descriptor'ları DDR'a ardışık yazar; donanım sequencer'ı (`snpu_seq`) listeyi sırayla
yürütür, döşeme döngülerini kendisi çevirir ve kare bitince tek kesme üretir. Descriptor'lar
CRC32 ile korunur, CSR haritası 128 baytlık APB penceresidir, tüm program tek bir blob
(`frame.bin`) olarak bağlanır.

## Detaylı Açıklama
**Descriptor.** 32 × u32, little endian: opcode/flags/version; giriş ve çıkış boyutları;
gerçek IC/OC; kaynak 0 ve kaynak 1 (base, plane_stride, row_stride, plane sayıları); ağırlık
tabanı ve `w_bytes_per_oct`; param tabanı (OC başına `{bias i32, mult u16, shift u8,
zp_pre i8}`); LUT tabanı; çıkış ve residual üçlüleri; dört sıfır noktası; residual yeniden
ölçekleri; döşeme geometrisi (`tile_rows`, `tile_px`, `n_tiles`, `ring_rows`); dolgu; `k` ve
`stride`; `tag`; son kelime ilk 31 kelimenin zlib CRC32'si. Sequencer CRC'yi bit-seri hesaplar
(992 çevrim).

**Opcode ve bayraklar.** NOP, CONV, MAXPOOL5, COPY, BARRIER, END. Bayraklar: SILU, RESIDUAL,
IRQ, LAST, UPS0/UPS1 (okuyucu ×2 büyütme), TWO_SRC (iki kaynaklı giriş), L0_MODE (stem
im2col-27), WAIT_PREV (önceki yazmaları bekle), DEBUG_DUMP (descriptor başına kesme).

**Tensör düzeni.** NC32HW `[C/32][H][W][32]`; her 32 kanallık plane ardışık, tabanı 64 bayt
hizalı. Concat üretici plan ofsetiyle, Split tüketici plan alt aralığıyla, Upsample okuyucu
moduyla sıfır kopyadır. 32'ye bölünmeyen kanal ofsetleri ön yüzde reddedilir ve CPU kesim
noktası olur; [[yolov8s]]'te hepsi 32'nin katıdır.

**CSR haritası.** ID (`0x534E5055`), VERSION, GEOMETRY (`n_chain`, `chain_len`,
`log2(p_max)`, `ibuf_kb`), CTRL (start, abort, soft reset), STATUS (busy, hata kodu
`[15:8]`, descriptor indeksi `[31:16]`), DESC_BASE, DESC_COUNT, IRQ_STATUS (W1C: done, desc
done, error, timeout), IRQ_MASK, sayaçlar CYCLE_CNT / fill / run_idle / mac / wr_wait,
DESC_DONE, TAG, DBG0..DBG6. Hata kodları: 1 opcode, 2 CRC, 3 sürüm, 4 AXI okuma, 5 AXI
yazma, 6 zaman aşımı, 7 geometri. Hata durumunda liste durur; `CTRL.abort` veya soft
reset ile çıkılır. Sayaçlar [[board-bringup-flow]] ölçümlerinde ve
[[analytic-performance-model]] kalibrasyonunda kullanılır.

**DBG yazmaçları (M9 düzeni, 2026-09-15).** Üç kanallı okuma DMA'sıyla DBG0/DBG1 yeniden
düzenlendi:
- DBG0 (0x40): `[31:20]` kanal 2, `[19:16]` kanal 1, `[15:12]` kanal 0 outstanding burst;
  `[11:9]` active, `[8:6]` issue_done, `[5:3]` warm (kanal 2..0); `[2:0]` sıra FIFO yazma
  işaretçisi; sequencer durumu, motor/maxpool meşgul ve yazma DMA boşta bitleri.
- DBG1 (0x44): bekleyen yazma yanıtı, yükleyiciler boşta, kanal 0..2 `cmd_valid`/
  `cmd_ready`/`d_valid`/`d_ready`, AXI ar/r/aw/w/b el sıkışmaları, `rd_busy`, çıkış
  valid/ready, okuma ve yazma hatası.
- DBG2..DBG5: yazma AW bekleme, AW sonrası W bekleme, biten yazma burst'ü, gönderilen beat.
- **DBG6 (0x58)**: `snpu_top`'un `dbg_ext_i` giriş sözcüğü; board'da [[snpu-axi-up512]]
  genişleticisinin durumu (tutulan beat, okuma kuyruğu boş, sıradaki kelimenin şeridi,
  burst'te teslim edilen kelime, port `RLAST` sayısı ile biten burst farkı, kuyruk
  işaretçileri). `board.py npu` DBG0/DBG1'i yeni düzene, DBG6'yı bu alanlara göre çözer.

**Hata 7 (geometri) genişletildi.** M9'dan itibaren bir döşemenin giriş ayak izi ibuf'un
yarısını aşarsa sequencer dolum komutunu vermeden bu kodla durur; döşeme çift tamponu
diğer yarıyı sonraki döşeme için kullandığından bu sınır zorunludur. Derleyici
(`tiler.py`) aynı sınırı uygular, `emit.py` doğrular ([[stalyanpu-toolchain]]).

**CSR erişim yolu.** Pencere APB `PADDR[14]=1` üst yarısıdır (alt yarı [[gdma]]). M7'de
yumuşak SoC [[efx-sapphire-fcu]] APB slave 0 (`0xF810_4000`, CDC köprüsü) idi; M8'den
itibaren ve HEAD'de sert SoC [[efx-sapphire-hpsoc-slb]] AXI-A üzerinden `0xE810_4000`.
[[stalyanpu-synthesis-guide]] M7 tablosu eski yolu anlatır ve güncel değildir
([[stalyanpu]]). Kesme her iki durumda sert SoC PLIC 9'a gider.

**Blob ve yerleşim.** `frame.bin`: 4 KB başlık (15 × u32: magic, version, base, size,
desc_off, desc_count, param_off, param_size, scratch_base, scratch_size, input_off,
input_bytes, n_outputs, outputs_off, crc32) + descriptor tablosu + parametre bölgesi, her
bölüm 4 KB hizalı; çıkış tablosu (offset, h, w, c, scale_q16, zp, name_off). `backend/alloc.py`
yaşam süresi tabanlı first-fit; C2f deseninde split kaynağı concat tamponuna yerleşir.
Tek doğru kaynak `backend/isa.py`; `stalyanpu_isa.h` ve `snpu_pkg.vh` aynı değerleri taşır
([[stalyanpu-toolchain]]).

**Doğrulama.** `interp.py` aynı blob'u yürütüp `QRunner` ile bit bit karşılaştırılır
(`compile --check`); RTL'de N1/N2 demo ağı ve Y1 66 YOLOv8s descriptor'ı aynı yolla
doğrulanır.

## Örnekler
- YOLOv8s 640×384: 66 descriptor, 52 tampon, scratch 11,6 MB, blob 11,3 MB.
- Neck'teki Resize + skip concat'i: tüketici CONV `TWO_SRC` + `UPS0` ile P5'i büyüterek, P4'ü doğrudan okur; COPY gerekmez.
- Board T3 testi: tek koşum sonrası bölge CRC'leri `testset.h` ile karşılaştırılır; T5 PLIC 9 kesmesini doğrular.

## İlişkili Kavramlar
- [[dsp-chain-systolic-array]]: descriptor'ın tarif ettiği döşeme/oct/icg/tap döngüsü
- [[multi-instance-npu]]: mutlak adresler yüzünden her örnek kendi DDR bölgelerine ayrı derlenir
- [[int8-quantization-flow]]: param bloğu ve epilog aritmetiği
- [[board-bringup-flow]]: CSR sayaçları ve T1..T5 testleri
- [[analytic-performance-model]]: sayaçlarla kalibrasyon
- [[axi-interconnect-topology]]: CSR ve veri düzlemi bağlantıları
- Varlıklar: [[snpu-axi-up512]] (DBG6'nın kaynağı)

## Kaynaklar
- [[stalyanpu-isa-descriptor]]: tam alan, opcode, CSR ve blob tanımı, DBG0/DBG1/DBG6 bit alanları, hata 7 genişletmesi
- [[stalyanpu-architecture]]: sequencer ve DMA akışı, kontrol satırı
- [[stalyanpu-toolchain-guide]]: `isa.py`, emitter, yorumlayıcı, `compile --check`
- [[stalyanpu-verification-guide]]: descriptor testleri, kırpılmış descriptor yöntemi
- [[stalyanpu-bringup-guide]]: CSR sayaçlarıyla ölçüm, DBG çözümü
- [[stalyanpu-readme]]: derleyici arka ucu durum satırı
