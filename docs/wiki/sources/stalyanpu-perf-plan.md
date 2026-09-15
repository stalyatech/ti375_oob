---
title: "Kaynak: StalyaNPU Performans Planı (24,6 → 43,9 fps)"
type: source
source_file: "ip/stalyanpu/docs/perf-plan.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-15
tags: [stalyanpu, performance, plan, m9, ddr]
---

# Kaynak: StalyaNPU Performans Planı (24,6 → 43,9 fps)

## Özet
M8 board ölçümü (10,2 M çevrim/kare, 24,6 fps) ile 30 fps eşiği (≤ 8,3 M çevrim) arasındaki
farkı kapatmak için yazılan plan ve aynı gün içinde eklenen durum notları. Plan üç iş tanımlar:
A giriş dolumunun hesapla örtüşmesi (döşeme çift tamponu), A2 epilog boşaltması ve yazmaların
sonraki döşemeyle örtüşmesi, B stem katmanı için L0 im2col-27 modu; sıra tablosu önce
zamanlama kapanışını, en sona dedicated DDR portunu koyar. Sonuç bölümleri A ve A2'nin
gerçeklendiğini, board'da 28,1 fps'te takılındığını ve dedicated 512-bit port ile
**5,69 M çevrim = 43,9 fps** alındığını bildirir. B yapılmadı; hedef aşıldığı için marj işidir.

## Temel Çıkarımlar
- Ölçüm tabanı: MAC %47 (4,87 M alt sınır), giriş dolumu %35 (3,6 M), koşumda boş %14, yazma bekleme 0,7 M; [[analytic-performance-model]] 2,5 GB/s'de 7,43 M çevrim = 33,6 fps verir.
- A gerçeklendi: `STALL_IBUF` 3,6 M → 1,04 M (kapı ≤ 1,1 M), board 8,89 M çevrim = 28,1 fps; ama `run_idle` 1,5 → 2,8 M ve `wr_wait` 0,7 → 1,7 M, stall paylaşımlı DDR yarışmasına taşındı.
- A2 sim'de kazandırdı, board'da hiç: kare süresi paylaşımlı yolun ~1,8 GB/s etkin bant genişliğine bağlıydı.
- Dedicated `axi_target0` (512-bit) + [[snpu-axi-up512]]: 43,9 fps, MAC %85, ALL PASS, iki koşum aynı CRC.
- Kapı kuralı: her adımdan sonra tam akış slack ≥ 0 ve board'da iki koşumda aynı CRC; negatif slack'li build'ler bozuk sonuç vermişti.

## Detaylı Notlar
**Ölçüm tabanı ve model.** [[stalyanpu-bringup-guide]] tablosunun M8 satırı. Model dolumun
hesapla örtüştüğünü varsayar; ölçümle arasındaki 2,8 M çevrimin büyük kısmı örtüşmeyen dolum
ve L0 katmanıdır ([[yolov8s]] 640×384, 66 descriptor).

**A. Döşeme çift tamponu.** Başlangıçta `snpu_seq.v` döşeme başına sıralıydı (`S_FILL →
S_FILL_WAIT → S_WEIGHTS → S_RUN → S_RUN_WAIT`), `snpu_top.v` ibuf yazma işaretçisini her
dolumda sıfırlıyordu, `cfg_ibuf_base_i` sabit 0'dı; `tiler.py` ayak izini ibuf'un yarısıyla
zaten sınırlıyordu. Plan beş değişiklik sayar: yazma işaretçisine taban register'ı, agen
tabanının koşum başına seq'ten gelmesi, `S_RUN_WAIT` sırasında sonraki döşemenin dolumu,
okuma DMA'sına üçüncü komut kanalı (residual komutlarıyla yarışmaması için) ve `STALL_IBUF`
sayacının ölçüt olması. Beklenen 10,2 → ~7,7 M çevrim (~32 fps). Durum: `snpu_rd_dma` `N_CH=3`
(döner sıralı AR, kanal başına kayıtlı burst boyu), `snpu_seq` ayrı dolum makinesi (`fstate`),
yarıyı aşan dolum hata 7, `emit.py` doğrulaması ([[descriptor-isa]]). Sim: tam paket 17/17
PASS, `tb_net_demo` 120,5 k → 106,5 k, tam geometri 94,9 k → 90,0 k, l0/l4/l26/l30/l65 5/5
([[stalyanpu-verification-guide]]). `syn/top`: +1,3k LUT, +26 RAM10. Tam tasarım reset ağacı
ve maxpool kapanışıyla +0,013 ns; board 28,1 fps, ALL PASS. 30 fps için 0,6 M çevrim açık
kaldı.

**A2. Epilog ve yazma örtüşmesi.** Board profili (`desc_profile_m9_table.txt`) `run_idle`
2,8 M'nin döşeme sınırı başına ~10-13 k dağıldığını gösterdi: L0 stem 64 döşeme → 774 k, L1
16 döşeme → 207 k. `S_RUN_WAIT` her döşemede epilog boşaltması, tüm yazma yanıtları ve sonraki
ağırlık gölgesini seri bekliyordu. Değişiklik: ara döşemelerde `ag_done` ile çıkış,
döşeme etiketli dört girişli `out_base`/residual tabloları, epilog `drain_tile`/`out_tile_nxt`/
`out_adv`, son döşeme tam bekler ([[stalyanpu-architecture]]). Beklenen 2,0-2,5 M çevrim
(≈ 35 fps); gerçekleşen sıfır, çünkü sınır DDR bant genişliğiydi ([[shared-dram-arbitration]]).

**Dedicated port.** Çözüm [[lpddr4x-controller]]'ın doğrudan `axi_target0` portu; x32
LPDDR4x'te port 512-bit olduğundan NPU 256-bit kaldı ve genişletici eklendi (kelime `A[5]`
şeridi, yarım strobe, burst kuyruğu). Hizasız başlangıç adresli wide burst'lerde port
okumayı kesti; hizalı beat'ten başlatılınca 43,9 fps. Kapanış seed taramasıyla ve port pin
kısıtlarıyla tamamlandı (+0,038 ns; [[stalyanpu-synthesis-guide]], [[ddr-port-pin-constraints]]).

**B. L0 modu (yapılmadı).** L0 (3×3 s2, 3→32) 8 kanala dolgulanır; descriptor 0 tek başına
1,8 M çevrim, 1,05 M'si dolum. Plan: giriş 4 bayt/piksel (dolum 1,97 → 0,98 MB), agen'de tap
döngüsü kalkar, 3×3×3 pencere 32 girişli vektör (27 + 5 sıfır), ağırlık `icg=1, tap=1`, perf
modeline `stem_mode`. Beklenen MAC 553 k → ~61 k, descriptor 0 1,8 → ~0,5 M. Doğrulama
`tb_layer_l0` ve doğruluk raporunun tekrarı ([[int8-quantization-flow]]).

**Sıra tablosu.** 1 zamanlama kapanışı, 2 A (~2,5 M), 3 B (~1,3 M), 4 dedicated port (kapı
perf modeli ≥ 40 fps). Tablo portu "256-bit" yazar; A durum paragrafı ve bring-up rehberi
gerçekleşen portun 512-bit olduğunu belirtir, tablo satırı plan hâlinde kalmıştır. Sıra da
fiilen değişti: B atlandı, port öne alındı.

**Modelle karşılaştırma.** Model 2,5 GB/s varsayımıyla 33,6 fps derken board 43,9 fps verdi;
[[stalyanpu-architecture]]'daki hesap sınırı 44 fps'e yaklaşıldı. Dedicated portta etkin
bant genişliği 4 GB/s'nin üstündedir ve modelin `ddr_bw_gbps` kalibrasyonu (bring-up
sırasındaki 5. adım) yeniden yapılmalıdır.

> ❓ **Belirsiz:** Dedicated port sonrası descriptor başına profil yoktur; kalan 0,79 M
> `wr_wait` ve 0,37 M `run_idle`'ın hangi katmanlarda toplandığı ölçülmemiştir. Ağırlık
> tekrar-akışı (~20 MB/kare) "marj işi" olarak anılır ama sayısal hedef yoktur.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu]], [[yolov8s]], [[lpddr4x-controller]], [[snpu-axi-up512]], [[stalyanpu-toolchain]]
- İlgili kavramlar: [[analytic-performance-model]], [[board-bringup-flow]], [[fpga-timing-closure]], [[descriptor-isa]], [[shared-dram-arbitration]], [[ddr-port-pin-constraints]], [[int8-quantization-flow]], [[dsp-chain-systolic-array]]
- Destekleyen kaynaklar: [[stalyanpu-bringup-guide]] (ölçüm tabanı ve sonuç), [[stalyanpu-architecture]] (M9 sequencer tanımı), [[stalyanpu-verification-guide]] (sim sonuçları), [[stalyanpu-synthesis-guide]] (kapanış)

## Alıntılar
- "A2 (epilog/yazma örtüşmesi) board'da hiç kazandırmadı: kare süresi paylaşımlı DDR yolunun etkin bant genişliğine bağlıydı." (satır 70-71)
- "Dedicated 512-bit DDR portu (`axi_target0`, `snpu_axi_up512` genişletici) ile 5,69 M çevrim = 43,9 fps, ALL PASS, MAC %85 ... Hedef aşıldı; B (stem) ve ağırlık replay artık marj işleri." (satır 71-73)
