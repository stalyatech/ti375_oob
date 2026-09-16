---
title: "Bir FPGA'da Birden Çok StalyaNPU"
type: concept
created: 2026-09-16
updated: 2026-09-16
source_count: 1
tags: [stalyanpu, multi-instance, system, gui, drc, csr, plic, ddr]
---

# Bir FPGA'da Birden Çok StalyaNPU

## Tanım
[[stalyanpu]] hızlandırıcısının farklı geometrilerde birden çok örneğinin aynı [[ti375c529]]
içine yerleştirilmesi, bağlanması, sentezlenmesi ve board'da birlikte test edilmesi için kurulan
akış. Tek doğru kaynak üst projedeki `rtl/snpu_system.json` sistem tanımıdır; araç üst modülü ve
kısıtları yalnız işaretli bölgelerin içinde yeniden yazar. Ayrıntılı rehber
`ip/stalyanpu/docs/system-integrator.md`.

## Detaylı Açıklama
**Bağlantı modeli.** Her örneğin CSR bloğu, sert SoC `io_apbSlave_0` penceresinin üst yarısında
256 baytlık bir slottadır: slot k için CPU adresi `0xE8104000 + k*0x100` ([[accelerator-control-plane-apb]]).
Tek bir `snpu_apb_cdc` (adres genişliği 14) pencereyi hızlandırıcı saatine taşır, yeni
`snpu_apb_demux` modülü `PADDR[13:8]` ile slotu seçer. Her örnek kendi PLIC hattını kullanır
(I, J, K, L, A..E; F, G, H rezerve) ([[hard-soc-fabric-interrupt-path]]). DDR tarafında her örnek
bir port alır: `axi_target0` dedicated 512 bit ([[snpu-axi-up512]] genişleticisiyle), paylaşımlı
anahtarın `MDNN` veya `MCODEC` yuvası 128 bit ([[shared-dram-arbitration]]). `axi_target1` bu
kartta kullanılamaz: Efinity Interface Designer, sert RISC-V SoC ([[efx-sapphire-hpsoc-slb]]) varken
DDR_0'ın AXI hedef 1'ini açan tasarımı reddeder (kural `ddr_rule_axi_1_qcrv32`) ve Ti375C529'da
tek DDR bloğu vardır. Bu, projenin bir kopyasında Efinity Python API'siyle portu açıp tasarım
denetimini koşturarak bulundu. Araç periferik tasarımı (`ti375_oob.peri.xml`) yazmaz ama okur:
dedicated portun açık olup olmadığı, pin öneki ve saati DRC'de denetlenir (E015, W110).

**Üretim.** Tek örnek `axi_target0`, hat I ve slot 0'da ise bölgeler tek hızlandırıcılı tasarımı
birebir üretir; Efinity map çıktısı sistem öncesi tasarımla aynı çıktı (LUT4 98281, FF 82710,
DSP48 711, RAM10 1606). Diğer durumlarda çoklu biçim yazılır: CDC ve slot çözücü, örnek başına
kayıtlı reset, port türüne göre genişletici veya doğrudan bağlantı, kullanılmayan portlara boşta
bağlama, hat başına kesme senkronizörü. Parametreler örnek önekli makrolarla `rtl/snpu_system.vh`
içindedir (`SNPU_NPU0_N_CHAIN` gibi).

**Tasarım kuralları ve kestirim.** DRC; ad, geometri, port ve hat çakışması, slot, DDR bölge
çakışması, cihaz kapasitesi, elle değiştirilmiş bölge gibi hataları ve kaynak eşiği, paylaşımlı
yuva çekişmesi, ağın tampon ihtiyacı gibi uyarıları üretir. Kaynaklar tek hızlandırıcı modelinden
([[analytic-performance-model]]) örnek başına toplanır. YOLOv8s 640x384 için bir örnek en az
`p_max` 512 ve 256 KB giriş tamponu ister; 64 KB tamponlu yapılandırmanın ilk katmanı
derlenemediği bu çalışmada bulundu.

**Web arayüzü.** [[stalyanpu-ip-generator]]'de sistem tanımı dört adımın tek doğru kaynağıdır;
tek hızlandırıcı bir örnekli tasarımdır. 1 Design: SVG blok diyagramı (sürükle bırak taşıma, AXI
pininden porta ve IRQ pininden PLIC hattına sürükleyerek bağlantı, dolu hedefe bağlanınca atama
değişimi, yakınlaştırma, geri al), özellikler paneli, kaynak ve fps, adres haritası, canlı DRC,
sığan karışım önerisi; seçili örnek için fps (ölçüm varsa ölçüm), katmanlar ve dizi boyutu
karşılaştırması. 2 Models: örnek başına model. 3 FPGA hardware: dosya farkı gösterip uygulama ve
bitstream build. 4 Board: S1..S6 zinciri ve örnek başına ölçülen fps. İlk sürümde bunlar ayrı bir
System sayfasında toplanmıştı ve tek hızlandırıcının Accelerator sayfasıyla çelişiyordu; aynı gün
yeniden düzenlendi.

**Modeller.** Her örneğe bir model atanır. Kalibrasyon ağa ve görüntülere bağlı olduğundan aynı
model bir kez kalibre edilir ([[int8-quantization-flow]]); derleme ise örnek başınadır, çünkü
ağırlık paketi dizinin tüketim sırasını, döşemeler tamponları, descriptor adresleri örneğin DDR
bölgelerini izler ([[descriptor-isa]]). YOLOv8s aynı kalibrasyonla 16x16 için 11,3 MB, 16x8 için
22,4 MB blob verdi; ikisi de referansla bit bit eşleşti. `system models` ve arayüzün Models
sayfası bunu yapar, sonuç `models/models.json` özetine yazılır.

**Board testi.** `stalyanpu.board.sysimage` her örneğin vektörlerini kendi geometrisi ve DDR
bölgeleriyle üretir, `sys_main.c` S1..S6 testlerini koşar: kimlik ve GEOMETRY, blob başlıkları,
CSR yalıtımı, tek tek koşum, birlikte koşum ve örnek başına fps, kendi PLIC hattından kesme
([[board-bringup-flow]]).

## Örnekler
- 16x16 `axi_target0` (hat I, slot 0) + 16x8 `MDNN` (hat J, slot 1, `p_max` 512, 256 KB):
  kestirim DSP48 757, RAM10 2164, npu0 13,7 fps, npu1 6,9 fps; Efinity map DSP48 757, RAM10 2081.
- `tb_npu_sys` simülasyonu: iki farklı geometri tek CSR penceresi arkasında aynı anda koşar,
  iki kesme ve tüm altın bölgeler eşleşir (24 kontrol).
- (2026-09-16 öncesi) Kestirimde tek 32x32 örnek 44,5 fps, en iyi iki örnekli karışım 38,7 fps: örnek başına sabit
  maliyet (174 DSP48, epilog, DMA'lar) yüzünden çoklu örnek toplam iş hacmi için değil, ayrı akış,
  ayrı ağ veya yalıtım ihtiyacı için anlamlıdır.

- Aynı sistemin pnr sonucu: `io_ddrMasters_0_clk` setup +0,032 ns, hold +0,023 ns; XLR 217,6k
  (%60), RAM10 2081 (%77), DSP48 757 (%56). Hiyerarşik rapor: `u_snpu` 430 DSP48 / 1036 RAM10,
  `u_snpu_npu1` 302 DSP48 / 679 RAM10. Bitstream `.data/build/bits/ti375_oob_sys_16x16_16x8.bit`.

- Tek örnekli sistem (16x16, `axi_target0`, hat I, slot 0) arayüzün dört adımıyla baştan sona
  kuruldu (2026-09-16): map DSP48 455, RAM10 1402, LUT4 94 929; pnr `io_ddrMasters_0_clk` setup
  +0,030 ns, hold +0,028 ns; board S1..S6 ALL PASS, 10 kare, 13,9 fps, 17 919 489 çevrim/kare, MAC
  sayacı 17 228 160. Değerler sistem öncesi 16x16 ölçümüyle aynıdır.

- İki örnekli sistem (16x16 `axi_target0` + 16x8 `MDNN`) arayüzle baştan sona kuruldu ve board'da
  koştu (2026-09-16): map DSP48 757, RAM10 2081, LUT4 137 913; pnr setup +0,032 ns, hold +0,023 ns;
  S1..S6 ALL PASS. npu0 13,9 fps (17 922 521 çevrim/kare, MAC 17 228 160), npu1 6,8 fps
  (36 233 415 çevrim/kare, MAC 33 903 360), birlikte 20,8 fps. Kestirim 13,7 + 6,9 = 20,6 fps;
  fark %1 civarında. İki örnek aynı anda koşarken kare süreleri tek başına koşumla aynı kaldı,
  yani örnekler birbirini yavaşlatmadı. İki kesme kendi PLIC hattından (9 ve 10) geldi.

> ❓ **Belirsiz:** İki örnek aynı paylaşımlı anahtar yuvasını (`MDNN` ve `MCODEC`) birlikte
> kullandığında bant genişliği bölünmesi board'da ölçülmedi; o durumdaki fps kestirimdir.

- Sabit maliyet 74 DSP48'e indikten sonra (2026-09-16) kestirimde en iyi iki örnekli karışım
  (16x32 `axi_target0` + 16x32 `MDNN`) 46,1 fps, tek 32x32 örnek 44,5 fps; çoklu örnek toplam iş
  hacminde de öne geçti. Ortak DSP havuzu incelendi ve ertelendi ([[stalyanpu-dsp-overhead-sharing]]).

## İlişkili Kavramlar
- [[accelerator-control-plane-apb]]: CSR penceresinin slotlara bölünmesi
- [[hard-soc-fabric-interrupt-path]]: örnek başına PLIC hattı
- [[shared-dram-arbitration]]: paylaşımlı yuvaların bant genişliği
- [[analytic-performance-model]]: örnek başına fps ve kaynak toplamı
- [[board-bringup-flow]]: tek hızlandırıcılı T1..T5 testlerinin sistem karşılığı S1..S6
- Varlıklar: [[stalyanpu]], [[snpu-axi-up512]], [[lpddr4x-controller]], [[stalyanpu-toolchain]]

## Kaynaklar
- [[stalyanpu-ip-generator]]: sistem tanımı üzerine kurulu dört adımlı arayüz
