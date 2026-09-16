---
title: "Kaynak: StalyaNPU IP Generator (yerel web arayüzü)"
type: source
source_file: "ip/stalyanpu/docs/ip-generator.md"
author: "volvox"
date: 2026-09-15
created: 2026-09-15
updated: 2026-09-16
tags: [stalyanpu, gui, ip-generator, toolchain, perf-model, resources]
---

# Kaynak: StalyaNPU IP Generator (yerel web arayüzü)

## Özet
[[stalyanpu-toolchain]] paketine eklenen yerel web arayüzünü ve `ipgen` komutunu anlatır.
Arayüz `python -m stalyanpu gui` (veya `gui.cmd`, `gui.sh`, `stalyanpu-gui`) ile standart
kütüphanenin HTTP sunucusu üzerinde açılır, ek Python paketi istemez ve yalnız yerel adrese
bağlanır. Solda adımların menüsü vardır, seçilen adım sağda tek başına açılır: 1 hızlandırıcıyı
seç ve fps'i gör (geometri, saat, DDR portu, ağ; [[analytic-performance-model]] ve kaynak
kestirimi), 2 geometriyi Efinity projesine bağla ve bitstream'i kur, 3 modeli bu hızlandırıcı
için hazırla (lower → calibrate → compile, isteğe bağlı golden ve eval), 4 board'da koştur
([[board-bringup-flow]]). 2 ve 3 birbirini beklemez ama aynı geometriyi kullanmak zorundadır;
her sayfa aynı üç rozetle açılır (Accelerator, FPGA, Model) ve menüdeki noktalar aynı durumu
tekrarlar, koşum sürerken yanıp söner. Menünün altında isteğe bağlı bir adım daha vardır:
IP'yi başka bir projeye taşınacak dosya paketi olarak yazmak ve o geometriyi Efinity ile tek
başına ölçmek. Seçilen adımlar tek zincir olarak sırayla koşar; ilerleme çubukları,
başarısız adımın nedeni ve log ilgili adımın yanında görünür. Her bölümde "Reset to defaults"
vardır ve seçili adım adres çubuğunda durur, yani yenileme ve geri tuşu aynı adıma döner.

## Temel Çıkarımlar
- Yalnız INT8; bit genişliği seçeneği yoktur. Geometri kısıtları RTL'den gelir: `N_CHAIN` 16'nın katı (epilog 32 lane), `CHAIN_LEN ∈ {8,16,32}`, `P_MAX` 2'nin kuvveti, `AXI_DW` 128/256; `hwcfg.validate` bunları denetler, `legal_geometries` 12 çifti listeler.
- Perf modeli değişmedi; `perf/adapter.py` indirgenmiş ONNX graf'ından aynı `Layer` tablosunu üretir ve YOLOv8s dışa aktarımında yerleşik tabloyla aynı çevrim sayısını verir (5,671 M).
- Kaynak kestirimi üç gerçek build'e çapalıdır (32×32: 1198 DSP48, 1269 RAM10, 102,9k XLR; 32×16: 686, 1240, 81,0k; 16×16: 430, 1036, 68,8k); dizi, biriktirici ve tamponlar ölçeklenir, epilog ve denetim sabittir. Dizinin DSP başına fabric maliyeti zincir uzunluğuna bağlıdır (32'lik zincir 30,5 XLR/DSP, 16'lık 22,8). Dizi dışındaki 174 DSP48 (epilog 128, sequencer 22, okuma DMA 18, agen 5, maxpool 1) hızlandırıcının sabit maliyetidir.
- Çubuklar iki parçalı: hızlandırıcı ve projenin geri kalanı. İkincisi sabit değil, `project.resource_report()` ile projenin son build raporundan (tasarım toplamı eksi hızlandırıcı örneği) okunur; son build'de 25 DSP48, 366 RAM10, 83,2k XLR. Proje kurulmamışsa gösterilmez.
- Ölçüm çapaları (YOLOv8s 640×384, 250 MHz): 32×32 dedicated portta 43,9 fps (model 44,5), 32×16 dedicated portta 25,2 fps (model 25,1), 16×16 dedicated portta 13,9 fps (model 13,7), 32×32 paylaşımlı portta 28,1 fps (model 28,4); ek yük sabitleri bu karelere birlikte ayarlıdır. Eşleşme geometri + port + bant genişliği + çözünürlük ile yapılır (paylaşımlı portun 2,4 GB/s planlama değeri ölçüm sayılmaz); ölçüm dizi listesinde, rozette, fps notunda ve karşılaştırma tablosunun "fps measured" sütununda görünür, ölçülmemişlerde "estimate only".
- IP paketi: `hwcfg.json`, `stalyanpu_isa.h`, perf/kaynak raporları, `rtl/snpu_params.vh`, `rtl/snpu_top_<ad>.v`, `rtl_files.f`, `sim_args.txt`, `syn/` Efinity projesi (xml, peri.xml, sdc, sentez sarmalayıcısı); isteğe bağlı `efx_run` işi `syn/run_syn.py --project-dir` ile.
- `hwcfg.load()` artık presetin kopyasını döndürür; `calibrate --image-dir` düz klasörden kalibrasyon yapar.

## Detaylı Notlar
**Sunucu ve iş koşucu.** `gui/server.py` rota tablosu, JSON uç noktaları (`/api/info`,
`/api/perf`, `/api/hwcfg/validate`, `/api/generate`, `/api/fs/*`, `/api/jobs*`) ve iş başına
server sent events akışı sağlar. `gui/jobs.py` her adımı alt süreç olarak koşturur
(`sys.executable -m stalyanpu <cmd>` veya `board.py`), satırları toplar, iptalde süreç
ağacını kapatır (Windows `taskkill /T`, POSIX süreç grubu); zincirde bir adım başarısız olunca
kalanlar `skipped` olur; OpenOCD servis yuvasında Start/Stop ile yaşar. İş türleri
`gui/registry.py`'de beyaz listeli argümanlarla tanımlıdır; kabuk kullanılmaz.

**Adım 1.** Geometri açılır listesi (her satırda MAC/çevrim ve DSP), saat, DDR port
presetleri ([[lpddr4x-controller]] dedicated 512-bit portu için 8 GB/s, paylaşımlı
[[shared-dram-arbitration]] yolu için ölçülen 2,0 GB/s); `p_max`, ibuf/wfifo ve model ek
yükleri "Advanced settings" altında; ağ olarak yerleşik [[yolov8s]] tablosu veya 2. adımın
ONNX dosyası. Sağda büyük fps değeri, ölçüm notu, çevrim/GMAC/s/doluluk/DDR kartları,
"fits the device" satırı ve DSP/RAM10/XLR çubukları ([[ti375c529]]); katlanır bölümlerde tüm
geometrilerin fps karşılaştırması, katman grafiği ve tablosu. İsteğe bağlı ölçülmüş
descriptor tablosu (`board.py npu`) grafiğe bindirilir.

**Adım 2 ve Board.** ONNX, kalibrasyon görüntü klasörü (COCO `val2017` ve annotation
verilirse COCO akışı) ve çıktı klasörü; "Prepare model" yolları denetler, 1. adımın yapılandırmasını `hwcfg.json`
olarak yazar ve lower → calibrate → compile zincirini başlatır, onay kutularıyla golden ve
eval eklenir ([[descriptor-isa]], [[int8-quantization-flow]]). Sonuç kutusu descriptor
sayısı, blob ve scratch boyutu, mAP ve dosya bağlantılarını verir. Board bölümü ddrimage,
build, program, OpenOCD, run, dumplog, npu adımlarını seçimli koşturur; `npu` çıktısındaki
`cycles` değerinden ölçülen fps kestirimle yan yana gösterilir ([[ti375-devkit]]).

**Adım 2 (proje bağlama).** Seçilen geometri `ti375_oob` Efinity projesine `rtl/snpu_config.vh`
(SNPU_CFG_* define'ları + GEOMETRY) ve `rtl/snpu_config.json` (uygulanan geometri ve
bitstream'in hangi geometriyle kurulduğu) olarak yazılır; `ti375_oob_top.v` bu dosyayı
`` `include `` eder ve `snpu_top` parametrelerini define'lardan bağlar, proje XML'ine `rtl`
include dizini eklenmiştir ([[hardware-architecture]] üst seviye bağlantısı). Kart ve
`python -m stalyanpu project status` bitstream kaydı projenin geometrisinden farklıysa,
kayıt yoksa bitstream include'dan eskiyse ya da bitstream yoksa "rebuild needed" der;
`mark-built` bitstream'i mevcut geometriye bağlar ve `pgm` akışı bitince arayüz bunu kendisi
çağırır. Ana düğme duruma göre "Apply and rebuild", "Rebuild the bitstream" ya da vurgusuz
"Rebuild anyway" olur ve `map` → `pnr` → `pgm` zincirini koşturur; tek tek aşamalar katlanır
bölümdedir (loglar `syn/logs/run_<flow>.log`). Board'un veri yolu `AXI_DW` 256 ve
`WR_SLOT_WORDS` 64 değerlerini sabitler ([[snpu-axi-up512]]); paylaşımlı port seçiliyse
`apply` hata verir.

**Dışa aktarma bölümü.** Parçalar seçimli; Verilog sarmalayıcı `snpu_top` port listesini korur ve
parametreleri bağlar, GEOMETRY CSR sözcüğü define olarak yazılır; Efinity projesi `syn/top`
şablonundan türetilir, SDC periyodu seçilen saatten hesaplanır ([[fpga-timing-closure]]).
Aynı paket `python -m stalyanpu ipgen --geometry 32x16 --ddr-port dedicated512 --out DIR`
ile üretilir. Üretilen sarmalayıcı davranışsal DSP modeliyle iverilog'da derlenir (test).
"Write files and measure" üretilen projeyi koşturur: `map` gerçek kaynak sayılarını (150 s),
`pnr` dizinin tek başına kapattığı saati (238 s) verir; board bitstream'i üretmez.

**Doğrulama.** pytest 546 → 589 (hwcfg, adaptör, kaynak, rtlparams, ipgen, proje bağlama,
menü/sayfa yapısı, API/SSE/iptal/zincir testleri). Sayfa headless Chrome'da çizildi:
32×32 / 250 MHz / dedicated → model 44,5 fps ve "ölçüm 43,9" notu; 4. adımda 32×16 uygulanınca
kart "rebuild needed"e döndü.
Üretilen include ile `efx_run map` referans build ile birebir aynı sonucu verdi
(LUT4 98 134, DSP48 1223, RAM10 1606), yani parametrelerin define'lara taşınması tasarımı
değiştirmez ([[fpga-timing-closure]] kaynak tablosuyla uyumlu).

**İkinci geometri board'da (2026-09-16).** 32×16 (1024 MAC/çevrim) dizi arayüzün dört
adımıyla uçtan uca kuruldu: geometri projeye uygulandı, `efx_run` map/pnr/pgm ile bitstream
üretildi (686 DSP48, 1240 RAM10, 81,0k XLR), model aynı geometri için hazırlandı ve kitte
koşturuldu. Sonuç **9 916 570 çevrim/kare = 25,2 fps**, MAC payı %92,6 (9,19 M), dolum 0,30 M,
koşumda boş 0,29 M, yazma bekleme 0,76 M; T1..T5 ALL PASS, 66 descriptor bit bit doğru. O
günkü ek yük sabitleriyle model 24,3 fps veriyordu, yani küçük dizide %3,8 karamsardı. Bu,
ölçeklenmenin board'da da çalıştığının ikinci kanıtıdır ([[analytic-performance-model]]
çapaları güncellendi).

**Üçüncü geometri ve modelin yeniden ayarlanması (2026-09-16).** 16×16 (512 MAC/çevrim) dizi
aynı dört adımla kuruldu: bitstream 430 DSP48, 1036 RAM10, 68,8k XLR; koşum **17 919 410
çevrim/kare = 13,9 fps**, MAC payı %96,1 (17,23 M), dolum 0,30 M, koşumda boş 0,25 M, yazma
bekleme 0,66 M, T1..T5 ALL PASS. Üç ölçüm birlikte modelin hangi teriminin kaydığını
gösterdi: dizi terimi (`cyc_mac` eksi `t_pass` payı) üç koşumda da board'un MAC sayacına
eşit, yani sapma tümüyle sabit ek yüklerden geliyordu. `t_pass`, `t_tile` ve `t_op` üç kareye
birlikte oturtulup 40 / 150 / 500 yerine 10 / 200 / 4000 yapıldı; model şimdi 32×32'de
%+1,3, 32×16'da %−0,5, 16×16'da %−1,1 sapıyor. Paylaşımlı 128-bit portun preset bant
genişliği de aynı uyumla 1,8 GB/s'den 2,0 GB/s'ye çıktı, çünkü ek yükler artık ayrı
hesaplanıyor. Kaynak modeli de üçüncü build'e çapalandı; dizi dışı sabit 174 DSP48 üç
build'de de aynı çıktı.

**Geometri uyumu (2026-09-16).** Board'da 64×8 için derlenen blob 32×32 bitstream'iyle
koşturulunca NPU `RUN_WAIT`'te asılı kaldı ve sayaç 0,2 fps gösterdi; bu ölçeklenme değil
uyumsuzluk sorunudur. Eklenen korumalar: `golden.json`/`geometry.json`/`TESTSET_GEOMETRY`
geometri kaydı, `board.py run` GEOMETRY CSR karşılaştırması (`--force` ile geçilir), sayfada
uyarı. `sim/run_sim.py --hwcfg` başka geometrilerde RTL simülasyonunu kurar
([[dsp-chain-systolic-array]] parametreleri `snpu_top` üzerinden). Bu koşumlar bir derleyici
hatası buldu: ağırlık FIFO'su zincir başına 32 baytlık dolum sözcüğü tüketirken paketleyici
zincir uzunluğu 8'de 16 bayt yazıyordu (makine ağırlık bekleyip asılı kalıyordu);
`weightpack.chain_bytes` dolgusu ile düzeltildi, perf modeli aynı kuralı kullanır. Demo ağı
bit bit altın karşılaştırmasıyla geçen geometriler: 16×16, 32×16, 16×32, 16×8, 64×8.

Kaynak ve performans kestirimi board'da 32×32, 32×16 ve 16×16 geometrilerinde
doğrulanmıştır. Diğer geometriler (16×32, 64×8 gibi) aynı formülün projeksiyonudur ve
yalnız RTL simülasyonuyla doğrulanmıştır.

## Bağlantılar
- İlgili varlıklar: [[stalyanpu-toolchain]], [[stalyanpu]], [[yolov8s]], [[ti375c529]], [[ti375-devkit]], [[lpddr4x-controller]], [[efinity-toolchain]]
- İlgili kavramlar: [[analytic-performance-model]], [[board-bringup-flow]], [[descriptor-isa]], [[int8-quantization-flow]], [[dsp-chain-systolic-array]], [[fpga-timing-closure]], [[shared-dram-arbitration]]
- Destekleyen kaynaklar: [[stalyanpu-toolchain-guide]], [[stalyanpu-synthesis-guide]], [[stalyanpu-bringup-guide]], [[stalyanpu-perf-plan]]

## Alıntılar
- "Performans modeli `perf/model.py`'deki formülün kendisidir; arayüz yeni bir formül eklemez." (Hesap yöntemi)
- "Referans geometride rapor sayıları bire bir çıkar (1198 DSP48, 1269 RAM10). Diğer geometrilerde kestirimdir; kesin sayı `efx_run map` ile alınır." (Hesap yöntemi)
