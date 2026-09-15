---
title: "snpu_axi_up512 (256'dan 512-bit'e AXI Genişletici)"
type: entity
category: product
created: 2026-09-15
updated: 2026-09-15
source_count: 3
tags: [stalyanpu, axi, width-adapter, ddr, lpddr4x, rtl, m9]
---

# snpu_axi_up512 (256'dan 512-bit'e AXI Genişletici)

## Tanım
[[stalyanpu]]'nun 256-bit AXI4 ana portu ile [[lpddr4x-controller]]'ın dedicated 512-bit
`axi_target0` portu arasına giren veri yolu genişletici modülü (`ip/stalyanpu/rtl/snpu_axi_up512.v`,
üst seviyede `u_snpu_up512`). M9'da (2026-09-15) NPU paylaşımlı `gAXIM_5to1_switch`
yuvasından ayrılıp bu port üzerinden DDR'a bağlandığında yazıldı; ölçülen kare süresini
8,89 M'den 5,69 M çevrime (28,1 → **43,9 fps**) indiren değişikliğin donanım parçasıdır.

## Temel Bilgiler
**Neden var.** Efinity arayüz tasarımcısı x32 LPDDR4x'te 256-bit AXI'yi kabul etmez ("AXI
Data Width 256 is not supported"); port yalnız 512-bit açılabilir. NPU tarafı 256-bit
(`AXI_DW=256`) kaldı, çünkü ASIZE 6'da `ALEN ≤ 63` sınırı `WR_SLOT_WORDS=64` ile zaten
karşılanıyordu ve DMA'lara dokunmak gerekmedi.

**Çalışma ilkesi.**
- 32 baytlık NPU kelimeleri 64 baytlık port beat'lerine çevrilir; kelime, adresin `A[5]`
  bitine göre beat'in alt veya üst şeridine biner.
- Burst başında veya sonunda tek başına kalan yarım beat'ler `WSTRB`'nin ilgili 32 baytı
  ile maskelenir; okumada gereksiz yarı atılır.
- Burst geometrisi (başlangıç şeridi, kelime sayısı) bir kuyrukta tutulur; okuma yanıtı
  gelince kuyruktan register'a yüklenip beat'ler kelimelere açılır.
- Wide burst'ler 64 B hizalı beat'ten başlar; 4 KB sınırı geçilmez, adres DRAM bayt
  adresidir.
- Dar AW dar tarafta hemen kabul edilir, çünkü port `AWREADY`'yi `WVALID`'den sonra verir.

**Port yönünde tamamen kayıtlı.** İlk sürümde port sınırında birleşimsel yollar
(`rready` -1,58 ns, `arlen`, `arready`/`wready` girişleri, `arstn`) zamanlamayı bozuyordu
([[ddr-port-pin-constraints]]). Son yapı: AR için 2 girişli kuyruk, okuma tarafında 4'lük
beat FIFO'su ve kayıtlı `rready`, W için 2 girişli çıkış kuyruğu, B için tek tutma
register'ı. `ARSTN = ~npu_rst` çıkışı SDC'de `set_false_path`. Bu haliyle tam tasarım
+0,038 ns ile kapandı ([[fpga-timing-closure]]).

**Yan bant sinyalleri** (`ti375_oob_top.v`, pin öneki `npu_ddr_*`): `ARAPCMD`/`AWAPCMD` 0,
`AWALLSTRB` 0 (aksi hâlde yazma 16 beat ile sınırlanır), `AWCOBUF` 0 ve `AWCACHE` 1111
(yanıt komut ve veri portta alınınca), tüm ID'ler 0. ARADDR 33 bit, ID 6 bit, WSTRB 64 bit.
Referans belge: Titanium DDR DRAM Block User Guide v2.8. Paylaşımlı anahtarın `MDNN`
yuvası boşta bırakıldı ([[axi-interconnect-topology]], [[shared-dram-arbitration]]).

**Gözlemlenebilirlik.** Modülün iç durumu `snpu_top`'un `dbg_ext_i` portundan CSR
**DBG6** (0x58) olarak okunur: tutulan beat, okuma kuyruğu boş, sıradaki kelimenin şeridi,
burst'te teslim edilen kelime sayısı, port `RLAST` sayısı ile biten burst farkı, kuyruk
işaretçileri ([[descriptor-isa]]). `board.py npu` bu kelimeyi çözer
([[stalyanpu-toolchain]]).

**Doğrulama.** Birim testi `tb_axi_up512` (U5): `axi4_mem_model` (512) karşısında 300
rastgele yazma burst'ü (1..64 kelime, rastgele başlangıç şeridi, boşluk ve durak), 300
okuma burst'ü, sonra eş zamanlı okuma/yazma; her kelime yazılımdaki bellek kopyasıyla
karşılaştırılır, 3 tohum PASS. Sistem testleri `tb_*_up512` varyantlarıyla `MEM_DW=512`
parametresinde genişleticiyi araya alır. Bu testler bellek modelinde bir hata ortaya
çıkardı: okuma ve yazma blokları aynı `k` döngü değişkenini paylaştığından eş zamanlı
trafikte yazma beat'leri kırpılıyordu; `kr`/`k` ayrıldı ve beat'ler hizalı bloktan
sunuluyor.

## Kaynaklarda Geçişi
- [[stalyanpu-bringup-guide]]: Faz 2 dedicated port, genişletici ilkesi, yan bant, pin kısıtları ve kayıtlı yapı
- [[stalyanpu-verification-guide]]: U5 `tb_axi_up512`, `MEM_DW` parametresi, bellek modeli düzeltmesi
- [[stalyanpu-isa-descriptor]]: DBG6 bit alanları

## İlişkiler
- [[stalyanpu]]: dar tarafını süren hızlandırıcı
- [[lpddr4x-controller]]: geniş tarafın bağlandığı `axi_target0` portu
- [[ti375-devkit]]: 43,9 fps ölçümünün alındığı kart
- [[stalyanpu-toolchain]]: DBG6 çözümü `board.py`'de
- [[efinity-toolchain]]: portu açan arayüz tasarımcısı ve `efx_run -f interface` şablonu
- Kavramlar: [[ddr-port-pin-constraints]], [[fpga-timing-closure]], [[axi-interconnect-topology]], [[shared-dram-arbitration]], [[descriptor-isa]], [[board-bringup-flow]], [[analytic-performance-model]] (bant genişliği varsayımını değiştiren ölçüm)
- [[dnn-accelerator-options]]: karşılaştırma tablosundaki veri yolu satırı
