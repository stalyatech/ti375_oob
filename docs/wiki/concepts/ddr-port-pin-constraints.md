---
title: "Sert Blok AXI Port Pinlerinin Zamanlama Kısıtları"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [timing, sdc, interface-designer, lpddr4x, hard-block, placement, m9]
---

# Sert Blok AXI Port Pinlerinin Zamanlama Kısıtları

## Tanım
[[efinity-toolchain]] arayüz tasarımcısının sert blok portları (burada
[[lpddr4x-controller]] `axi_target0`) için ürettiği `set_input_delay` /
`set_output_delay` kısıtlarının proje SDC'sine **elle** taşınması gerektiği dersi. Kısıt
taşınmazsa fabric ile sert blok arasındaki yollar analiz dışı kalır, build'in çalışıp
çalışmaması yerleşime bağlı hâle gelir ve raporlanan "pozitif slack" anlamsızlaşır.

## Detaylı Açıklama
**Mekanizma.** Arayüz tasarımcısı `efx_run -f interface` adımında `outflow/<prj>.pt.sdc`
dosyasını üretir. `npu_ddr_*` pinleri için bu dosyada giriş max 2,625 ns, çıkış max
2,31 ns gecikmeler, referans saat `io_ddrMasters_0_clk~CLKOUT~2~464` yazılıdır. Efinity
bu dosyayı kullanıcı `constraints.sdc`'sine kendiliğinden birleştirmez; satırlar elle
kopyalanır.

**Belirti.** Kısıtlar eksikken üç build alındı: ikisi (biri +0,088 ns ile "kapalı"
raporlanan) [[ti375-devkit]] üzerinde ilk ibuf dolumunda asılı kaldı, üçüncüsü (-0,110 ns)
çalıştı. Yani pin yolları zamanlanmadığından davranış build'den build'e yerleşime
bağlıydı ve slack raporu güvenilir değildi.

**Kısıt eklenince.** İhlaller hemen port sınırındaki birleşimsel yollarda çıktı:
`npu_ddr_rready` (kayıt kuyruğu RAM okuması, karşılaştırma, çıkış: -1,58 ns), ardından
`arlen` (toplayıcı çıkışı), `arready`/`wready` girişlerinden NPU DMA mantığına giden
yollar ve `arstn`. Çözüm [[snpu-axi-up512]] genişleticisini port yönünde tamamen kayıtlı
yapmaktı (AR kuyruğu, okuma beat FIFO'su ve kayıtlı `rready`, W çıkış kuyruğu, B tutma
register'ı); reset çıkışı `arstn` SDC'de `set_false_path` olarak işaretlendi. Son build
(seed 6) `io_ddrMasters_0_clk` +0,038 ns, peri +0,240 ns ile kapandı ve board'da iki
koşumda aynı CRC verdi ([[fpga-timing-closure]], [[board-bringup-flow]]).

**Genel kural.** Sert bloğa yeni bir port açıldığında (1) `pt.sdc` çıktısı kontrol edilir,
(2) pin kısıtları proje SDC'sine taşınır, (3) port sınırındaki mantık kayıtlı tutulur,
(4) asenkron reset çıkışları false path yapılır, (5) build yine de board CRC'siyle
doğrulanır. Yerleşim gürültüsünün ±0,3 ns oynattığı %88 DSP dolulukta kısıtsız pin, bir
seed'de çalışan diğerinde asılan build üretebilir.

## Örnekler
- `pt.sdc` satır biçimi: `set_input_delay -clock <ref> -max 2.625 [get_ports npu_ddr_rvalid]`, `set_output_delay -clock <ref> -max 2.31 [get_ports npu_ddr_arvalid]` (referans saat adı arayüz tasarımcısının ürettiği CLKOUT örneğidir).
- Kısıtsız seed taraması (effort 3): seed 1 -0,040, 2 -0,007, 3 -0,110, 4 +0,087, 5 +0,017, 6 +0,088 ns; bu sayılar pin yolları dahil edilmediği için yanıltıcıydı.
- Kısıtlı son build: seed 6, +0,038 ns, LUT4 98,1k, FF 94,1k, DSP48 1223, RAM10 1606, bitstream `ip/stalyanpu/.data/build/bits/ti375_oob_hp_ddr4.bit`.

## İlişkili Kavramlar
- [[fpga-timing-closure]]: bu ders olmadan kapanış raporunun eksik kaldığı süreç
- [[board-bringup-flow]]: asılı kalan build'lerin görüldüğü akış ve zorunlu CRC doğrulaması
- [[axi-interconnect-topology]]: dedicated portun paylaşımlı anahtarın yanına eklenmesi
- Varlıklar: [[snpu-axi-up512]], [[lpddr4x-controller]], [[efinity-toolchain]], [[ti375-devkit]], [[stalyanpu]]

## Kaynaklar
- [[stalyanpu-bringup-guide]]: port pinlerinin zamanlaması, asılı kalan build'ler, kayıtlı genişletici
- [[stalyanpu-synthesis-guide]]: M9 seed taraması (kısıtsız) ve kısıtlı son build sonucu
