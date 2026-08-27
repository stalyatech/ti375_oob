# DNN (OpenEye) + H.264/H.265 Codec Pipeline: Entegrasyon Devri

> ✅ **DURUM (2026-08-27): Donanım entegrasyonu + fonksiyonel simülasyon + kesme yolu TAMAM.**
> Tasarım Ti375C529'a sığıyor, route ediliyor ve timing kapanıyor (setup slack:
> io_peripheralClk +0.147 ns, io_ddrMasters_0_clk +0.191 ns, io_dnnClk +1.234 ns; hold temiz;
> CDC raporu uyarısız). OpenEye çekirdeği tam oturan konvolüsyon vektöründe (8 filtre, 8x8x4)
> TensorFlow altın modeliyle bit bit doğrulandı (`sim/openeye/`, bilinen sınırlar aşağıda).
> DNN done kesmesi `userInterruptI` üzerinden
> Hard SoC PLIC'ine bağlı (PLIC ID 9), W1C temizleme cfg penceresi 0x3C'te. Bitstream üretimi
> `efx_run -f pgm` ile yapılır. Kalan işler: donanım üzerinde bring-up ve Linux yazılımı.

Bu klasör, `ti375_oob` FMU platformuna **OpenEye DNN hızlandırıcısı** ve **H.264/H.265 codec
yuvası** eklenmesinin (Hard SoC tarafına) durumunu belgeler.
[`gui-ip-steps.md`](gui-ip-steps.md) tarihseldir: oradaki IP üretim adımları tamamlandı, birebir
GUI değerleri için referans olarak durur.

## Mimari özet

- **Veri düzlemi:** `gDMA_dnn` (efx_dma 6.4.2, CTRL_ASYNC_MODE=1; CH1 MEM→STREAM `dat1_o` →
  OpenEye `dma_i`, CH0 STREAM→MEM `dat0_i` ← OpenEye `dma_o`, 64-bit AXIS, SG mode) DDR'a
  `gAXIM_5to1_switch` üzerinden `MDNN=3` yuvasıyla çıkar. `MCODEC=4` rezerve ve boşta.
- **Kontrol düzlemi:** Hard SoC APB3 peripheral 0 (offset 0x100000, 64 KB), `PADDR[14]` ile
  ikiye bölünür: alt yarı `gDMA_dnn` ctrl, üst yarı `apb3_2_axi4_lite` → OpenEye `cfg_reg`
  (16×32-bit register, adres aliaslanır).
- **Saatler:** OpenEye çekirdeği ve her iki stream ucu `io_dnnClk` (100 MHz, PLL çıkışı 3,
  out_divider 40); `cfg_reg` ve APB köprüsü `io_peripheralClk` (200 MHz); gDMA_dnn veri tarafı
  `io_ddrMasters_0_clk`. CDC'ler gDMA_dnn async kanallarında ve `pulse_sync`/2-FF senkronizörlerde.

## Kesme yolu (2026-08-27'de eklendi)

Önemli bulgu: `EfxSapphireHpSoc_slb` hard SoC değil, Efinity'nin ürettiği yumuşak çevre birimi
alt sistemidir; onun `userInterrupt*` çıkışları kendi IRQ kaynaklarıdır ve bu tasarımda boşta
bırakılır. Asıl hard SoC (`ti375_oob.peri.xml` SOC bloğu `qcrv32_inst1`) üst seviye
`userInterruptA..L` çıkış portlarını PLIC girişleri olarak tüketir; harf → PLIC ID = indeks
(A=1 .. L=12, M..X boş). `userInterruptF=sd_int`, `G/H=dma_interrupts` zaten bu deseni kullanır.

DNN yolu (`ti375_oob_top.v`):
1. `openeye_irq` (io_dnnClk) `dma_o` son beat'inde sticky `dnn_done_irq` üretir.
2. 2-FF senkronizör bunu io_peripheralClk'ya taşır; `assign userInterruptI = dnn_irq_sync[1];`
   → **PLIC ID 9**.
3. Temizleme: OpenEye cfg penceresinde **offset 0x3C**'e bit 0 = 1 yazmak, peri domaininde tek
   çevrim darbe üretir; `rtl/pulse_sync.v` (toggle + 3-FF) bunu io_dnnClk'ya geçirir ve latch'i
   temizler. Yazma ayrıca cfg_reg register 15'e düşer, çekirdek bu registerı kullanmaz.

Yazılım notu: BSP `embedded_sw/efx_hard_soc/bsp/efinix/EfxSapphireSoc/include/soc.h`
`SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT = 9`. Sürücü akışı: PLIC ID 9 enable + priority,
kesme işleyicide 0x3C'e 1 yaz (W1C), yeni descriptor zinciri kur. Polling alternatifi:
gDMA_dnn CH0 descriptor durumunu izlemek.

## Fonksiyonel simülasyon (`sim/openeye/`)

Strateji: OpenEye'ın Python doğrulama altyapısı **ONLY_FILES=1** modunda çevrimdışı stimulus ve
altın referans üretir (TensorFlow yalnız bu adımda); doğrulama saf Icarus Verilog directed
testbench ile yapılır. gDMA_dnn simülasyon kapsamı dışıdır (vendor RTL; AXIS kontratı TB'deki
BFM ile temsil edilir).

| Dosya | İşlev |
|-------|-------|
| `gen_stimulus.py` | Keras katmanı kurar, dma_i kelime akışı + beklenen dma_o beat'lerini üretir, hex'e çevirir |
| `stim/dma_stim.hex`, `stim/dma_golden.hex` | Regresyon vektörü: Conv 8 filtre, 3x3, 8x8x4 giriş (463 kelime → 256 beat) |
| `tb_openeye_core.v` | DUT: `open_eye_mt_v1_0` + `openeye_irq`; tready'ye saygılı AXIS master, LFSR backpressure, altın karşılaştırma, IRQ kontrolleri |
| `tb_openeye_glue.v` | APB köprü + cfg_reg yaz/oku, `openeye_irq` köşe durumları, tam W1C zinciri (`pulse_sync` dahil) |
| `run_core.sh`, `run_glue.sh` | Derle + koş (opsiyonlar dosya adlarından önce gelmeli) |

Koşum:
```
sh sim/openeye/run_glue.sh
sh sim/openeye/run_core.sh [+BACKPRESSURE] [+STIM=... +GOLD=...]
```
Sonuçlar (2026-08-27): glue PASS; core regresyon vektörü serbest akış + backpressure PASS
(256 beat bit bit, IRQ set/sticky/clear dahil).

> ⚠️ Bilinen sınırlar (denemelerle ölçüldü):
> 1. `tb_openeye_core` beat'leri dosya sırasıyla karşılaştırır. Upstream cocotb karşılaştırması
>    `make_ref`'in döndürdüğü `output_order` permütasyonunu ve dolgu pozisyonu maskesini
>    kullanır. Çıkış pozisyon sayısının donanım dizilimine tam bölünmediği şekillerde
>    (örnek: 16 filtre, 7x7 çıkış → filtre başına 7 dolgu pozisyonu, golden 0 yazar, RTL
>    hesaplanmış değer basar) bu TB yanlış FAIL üretir.
> 2. Girişi büyük katmanlarda (denenen: 10x10x8 ve 12x12x8) RTL beklenen beat'lerin tam
>    yarısını üretti; mapper'ın transmisyon hesabı küçük RAM_CELLS=8/BUFFER_WIDTH=10
>    geometrisini hesaba katmıyor görünüyor. Gerçek modeller koşulmadan önce bu geometri
>    için upstream cocotb akışıyla veya donanımda katman boyutu zarfı çıkarılmalı.
> Bu nedenle commit edilen regresyon vektörü tam oturan şekildir (8 filtre, 8x8x4; 64 çıkış
> pozisyonu = donanım dizilimine tam bölünür).

Stimulus yeniden üretimi (TensorFlow gerekir):
```
PYTHONHOME="C:/Programs/Efinity/2025.2/python311" \
PYTHONPATH="<proje>/.pydeps-openeye;<proje>/ip/OpenEye/src" \
"C:/Programs/Efinity/2025.2/python311/bin/python.exe" sim/openeye/gen_stimulus.py
```
`.pydeps-openeye/` dizini `pip install --target=.pydeps-openeye tensorflow pyyaml` ile kurulur
(Efinity python311, PYTHONHOME set edilmeli). Geometri env değişkenleri `gen_stimulus.py`
içinde RTL instantiation ile eşleştirilmiştir; değiştirirken ikisini birlikte güncelle.

## OpenEye submodule yerel yamaları

`ip/OpenEye` (Learning-Chips-Lab/OpenEye, SHL-2.1, pin: `ca5a7dc`) içinde 5 dosya yamalı ve
2 dosya üretilmiştir. Tamamı commit edilmemiş submodule durumudur; yedek:
[`patches/openeye-local-patches.diff`](patches/openeye-local-patches.diff) ve
[`patches/generated/`](patches/generated/). `git submodule update --checkout` bu yamaları siler;
geri almak için diff'i `git -C ip/OpenEye apply` ile uygula ve generated dosyaları kopyala.

| Dosya | Yama |
|-------|------|
| `fpga/hdl/open_eye_axi_v1_0.v` | `QUANT_AMOUNT=32` parametresi eklendi, yinelenen `.BUFFER_WIDTH` kaldırıldı |
| `hdl/OpenEye_FPGA.v` | `USE_INTERNAL_PARAMS` self-define; VERI-1466 stray `temp_var=0` kaldırıldı; `psum_data_i_reg` çoklu sürücü reset'i kaldırıldı |
| `src/open_eye/generator.py` | Port listesi virgül üretimi `",\n".join` ile düzeltildi (Windows text-mode seek kusuru) |
| `src/open_eye/conv_mapper.py` | quantize/offset döngü sınırları sabit 1024 yerine `params.QUANT_AMOUNT` (küçük geometri desteği) |
| `src/open_eye/dense_mapper.py` | Aynı QUANT_AMOUNT ölçekleme yaması |

Üretilen dosyalar: `hdl/dma_storage.v`, `hdl/include/regmap_params.vh`. Reçete (doğru kaynak
`test/cocotb_fpga/regmap.yaml`, 54 register; `hdl/config/regmap.yaml` eskidir):
```
cd ip/OpenEye/test/cocotb_fpga
PYTHONHOME=<efinity>/python311 PYTHONPATH=../../src \
  BRANCHES=1 BUFFER_WIDTH=10 CLUSTER_ROWS=2 CLUSTER_COLUMNS=2 \
  <efinity>/python311/bin/python.exe -m open_eye.generator . ../../hdl/include ../../hdl
```
Bu yamalar upstream'e fork/PR olarak taşınmalıdır (ayrı iş).

## Adres ve IRQ haritası (gerçeklenen)

Hard SoC çevre penceresi offset'leri (`peri_config`: `io_apbSlave_0` @ 0x100000, 64 KB):

| Aygıt | APB alt penceresi | IRQ | DDR yuvası |
|-------|-------------------|-----|------------|
| `gDMA_dnn` ctrl | 0x0000..0x3FFF (PADDR[14]=0) | descriptor polling (ctrl_interrupts bağlı değil) | `MDNN=3` |
| OpenEye `cfg_reg` | 0x4000+ (PADDR[14]=1; 6-bit adres aliaslanır) | `userInterruptI` (PLIC ID 9), W1C: 0x3C bit0 | yok |
| Codec (gelecek) | ayrılmadı (dekod PADDR[14] ile ikili) | `userInterruptJ` önerisi | `MCODEC=4` (boşta) |

Not: codec eklenirken APB dekodu genişletilmeli (şu an 0x8000+ cfg yoluna aliaslanır) ve
`rtl/codec_h26x_stub.v` instantiate edilmelidir (dosya xml'de hazır, kullanılmıyor).
`rtl/openeye_axilite_adapter.v` ölü koddur: Hard SoC fabric AXI master'ı olmadığı için APB
köprüsü tercih edildi; dosya ileride codec kontrolü için xml'de bırakıldı.

## Akış komutları

```
efx_run ti375_oob --prj -f map    # sentez
efx_run ti375_oob --prj -f pnr    # yerleştirme + route + STA
efx_run ti375_oob --prj -f pgm    # bitstream (outflow/ altına .hex)
```
Ortam: `C:\Programs\Efinity\2025.2\bin\setup.bat`. `peri.xml` değişirse önce `-f interface`.

## Doğrulama durumu

- Glue + core testbench'ler: PASS (yukarıda).
- map: PASS, pnr: PASS, STA: tüm slack'ler pozitif, CDC uyarısız (2026-08-27, kesme yolu dahil).
- Donanım bring-up: yapılmadı. Sıra: bitstream yükle, JTAG/UART üzerinden gDMA_dnn descriptor
  kur, vektör 1 stimulus'unu DDR'dan akıt, sonucu DDR'dan oku ve `dma_golden.hex` ile karşılaştır,
  PLIC ID 9 kesmesini doğrula.

## Kaynak riski

OpenEye BRAM-yoğun (RAM10 894/2688, %33). Geometri büyütülürse (`CLUSTER_*`, `RAM_CELLS`,
`BUFFER_WIDTH`) hem RTL parametreleri hem `gen_stimulus.py` geometrisi hem de blok üretimi
birlikte güncellenmeli; BRAM'i izle.
