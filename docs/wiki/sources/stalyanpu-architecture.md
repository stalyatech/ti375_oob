---
title: "Kaynak: StalyaNPU Mimarisi"
type: source
source_file: "ip/stalyanpu/docs/architecture.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, architecture, dsp48, systolic, memory-plan, rtl]
---

# Kaynak: StalyaNPU Mimarisi

## Özet
[[stalyanpu]] hızlandırıcısının mimari kararlarını özet tablo, döngü yapısı, DSP48
sarmalayıcı ve zincir, konvolüsyon motoru, sequencer/DMA akışı, on-chip bellek planı, kaynak
tahmini, M0 performans modeli, RTL modül listesi ve risk listesi başlıklarıyla anlatır.
Bugünkü sürüm M9 eklerini içerir: döşeme çift tamponu, döşeme boşaltma örtüşmesi ve
DDR satırında Faz 2 olarak 512-bit `axi_target0` portu ile [[snpu-axi-up512]]
genişleticisi. Geometri sabitleri `snpu_pkg.vh` ve `hwcfg.py` (`full2048` / `small256`)
aynı değerleri taşır.

## Temel Çıkarımlar
- Dizi: 1024 [[efx-dsp48]] DUAL = 2048 INT8 MAC/çevrim; 32 zincir × 32 DSP, her zincir 4 fiziksel kaskat × 8 DSP; döşeme 32 IC × 64 OC, çevrimde 1 çıkış pikseli ([[dsp-chain-systolic-array]]).
- Ağırlık-sabit sistolik kaskad; birikim DSP'de değil 32-bit RAM10 biriktiricide (`snpu_acc`, 2 bank × 1024 px × 64 OC).
- Tensör düzeni NC32HW; Concat/Split/Upsample sıfır kopya, `TWO_SRC` iki kaynaklı giriş.
- Okuma DMA'sı üç komut kanallı (0 denetim, 1 ağırlık, 2 ibuf dolumu); DDR Faz 1 `MDNN=3` paylaşımlı yuva, Faz 2 (M9) 512-bit dedicated port.
- M9: döşeme `t` koşarken `t+1` ibuf'un diğer yarısına dolar; ara döşemelerde `S_RUN_WAIT` `ag_done` ile çıkar, en çok üç döşeme aynı anda canlı.
- Kaynak tahmini DSP 1120 (%85), RAM10 ≈ 933 (%40), XLR ≈ 77k (%27); M0 modeli 2,4 GB/s'de 32,9 fps, hesap sınırı 44 fps.

## Detaylı Notlar
**Dizi ve veri akışı.** Ağırlık DSP `B_REG`'de tutulur (CE = latch), iact `A` girişinden 32
kademeli çarpıklıkla akar, kısmi toplamlar `CASCIN/CASCOUT` zincirinde ilerler. 32 çarpım
≤ 2^19 olduğundan 24-bit lane taşmaz. 3×3, 1×1 ve stride 2 aynı makinede çalışır, tap
ofsetleri ibuf okuma adresindedir. İlk katman (IC=3) Faz 1'de 8 kanala dolgulanır (%4,7
kullanım); Faz 1.5 `L0_MODE` im2col-27 hâlâ plandır. Zincir gecikmesi
s + CHAIN_LEN + 2 + log2(CHAIN_LEN/CASC_LEN).

**Epilog ve nicemleme.** 32 OC/çevrim: bias → requant (u16 çarpan × 2^-s, yarım yukarı,
doyur, zp) → 256 girişli SiLU LUT → residual Add (iki ölçekli) → int8 paketleme → yazma DMA.
Ağırlık int8 simetrik OC başına, aktivasyon int8 tensör başına asimetrik
([[int8-quantization-flow]]).

**Döngü yapısı.** Derleyici üretir, `snpu_seq` yürütür: döşeme → oct (64 OC) → icg (32 IC)
→ tap → piksel; ağırlık DDR'da tüketim sırasındadır. Pass başına ek yük ≈ 40 çevrim.

**Sequencer ve DMA (M4 + M9).** Descriptor başına fetch → bit-seri CRC32 (992 çevrim) →
param bloğu → LUT → döşeme döngüsü ([[descriptor-isa]]). M9 eki iki başlıktır. *Döşeme çift
tamponu:* `snpu_seq` içindeki dolum makinesi döşeme `t`'yi `t[0]` yarısına doldurur, motor
`S_RUN`'a girer girmez `t+1`'in geometrisini hesaplayıp komutları diğer yarıya verir;
`S_RUN_WAIT` yalnız motoru, residual okumalarını ve yazma DMA'sını bekler, `S_FILL_WAIT`
eksik sözcükleri. Descriptor başına yalnız ilk döşemenin dolumu açıkta kalır ve `STALL_IBUF`
bunu ölçer; `tiler.py` ayak izini ibuf'un yarısıyla sınırlar, `emit.py` doğrular, sequencer
yarıyı aşan komutta hata 7 verir. Dolumun residual/param okumalarıyla yarışmaması için okuma
DMA'sı üç kanallıdır; AR üretimi döner sıralı, burst boyu kanal başına kayıtlı. *Döşeme
boşaltma örtüşmesi:* ara döşemelerde `S_RUN_WAIT` adres üretecinin bitmesiyle (`ag_done_seen`)
ve ağırlık kanalının boşalmasıyla çıkar; epilog boşaltması, residual okumaları ve yazmalar
sonraki döşemenin arkasında sürer. Döşeme başına değişen çıkış bağlamı dört girişli
tablolarda tutulur (`out_base_tab`, `res_row_tab`, `res_rows_tab`); epilog `drain_tile`,
`out_tile_nxt`, `out_adv` bildirir. Biriktirici iki banklı olduğundan aynı anda en çok üç
döşeme canlıdır. Son döşeme ve descriptor sonu tam bekler.

**v1 sınırları.** Belge her sınırın sonraki durumunu da yazar: yazma DMA'sı M8'de burst
birleştirme aldı; sıralı döşemeler M9'da çift tampona geçti; dolum kanal 2'ye ayrıldı; epilog
tam beklemesi ara döşemelerde kaldırıldı.

**DDR ve kontrol.** Faz 1 `gAXIM_5to1_switch` `MDNN=3` yuvası ([[axi-interconnect-topology]],
[[shared-dram-arbitration]]); Faz 2 (M9) [[lpddr4x-controller]] `axi_target0` 512-bit
dedicated port, arada `snpu_axi_up512` genişletici (ayrıntı [[stalyanpu-bringup-guide]]).
Kontrol satırı CSR'ı hâlâ yumuşak SoC APB penceresi `0xF810_4000` ve `snpu_apb_cdc.v`
köprüsüyle anlatır; bu M7 hâlidir. HEAD'de CSR sert SoC AXI-A üzerinden `0xE810_4000`'dedir
([[accelerator-control-plane-apb]]); kesme yolu değişmedi (`userInterruptI`, PLIC 9,
[[hard-soc-fabric-interrupt-path]]). Saat `snpu_clk = io_ddrMasters_0_clk` (250 MHz).

**Bellek planı, kaynak, performans, riskler.** ibuf 16 bank × 1024 × 256 bit (512 KB, 416
RAM10), acc 512 KB (412), wfifo 32 KB, gölge 16k FF; toplam ≈ 933 RAM10. Kaynak tahmini DSP
1120, XLR ≈ 77k. [[analytic-performance-model]] M0 sonucu 7,60 M çevrim = 32,9 fps @2,4 GB/s,
4,5 GB/s ile 40,8 fps, hesap sınırı 44 fps; board'daki 43,9 fps bu hesap sınırına yaklaşır.
Riskler: DSP silikon davranışı, 250 MHz kapanışı ([[fpga-timing-closure]]), DDR bant
genişliği, DSP bütçesi, PTQ mAP, derleyici doğruluğu, iverilog süresi. İlk üçü M8/M9'da
fiilen kapanmıştır.

> ❓ **Belirsiz:** Belgede eskimiş üç ifade vardır: DDR satırındaki "4 outstanding 16-beat
> burst" (M8'de 1 KB burst, 16 outstanding oldu), modül tablosundaki "`snpu_rd_dma` 2 kanal"
> (M9'da 3) ve performans/risk bölümlerindeki "dedicated port M7'ye çekildi" (M9'da
> gerçekleşti). Başka bölümler doğru değeri taşıdığından çelişki değil güncelleme eksiğidir.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[efx-dsp48]], [[yolov8s]], [[lpddr4x-controller]], [[snpu-axi-up512]], [[stalyanpu-toolchain]]
- İlgili kavramlar: [[dsp-chain-systolic-array]], [[descriptor-isa]], [[int8-quantization-flow]], [[analytic-performance-model]], [[fpga-timing-closure]], [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[accelerator-control-plane-apb]], [[hard-soc-fabric-interrupt-path]]
- Destekleyen kaynaklar: [[stalyanpu-decision-record]], [[stalyanpu-isa-descriptor]], [[stalyanpu-synthesis-guide]], [[stalyanpu-bringup-guide]], [[stalyanpu-perf-plan]]

## Alıntılar
- "1024 DSP48 DUAL = 2048 INT8 MAC/çevrim; 32 zincir (`N_CHAIN`) × 32 DSP (`CHAIN_LEN`); her zincir 4 fiziksel kaskat × 8 DSP" (satır 10)
- "Biriktirici iki banklı olduğu için aynı anda en çok üç döşeme canlıdır (t boşalır, t+1 hesaplanır, t+2 doldurulur), dört girişli tablo yeter." (satır 119-121)
