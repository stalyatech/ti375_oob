---
title: "AXI Ara-Bağlantı Topolojisi"
type: concept
created: 2026-07-03
updated: 2026-09-24
source_count: 6
tags: [axi, interconnect, concept, rtl, axi-target0]
---

# AXI Ara-Bağlantı Topolojisi

## Tanım
Tasarımın iki katmanlı AXI anahtar yapısı: bir **kontrol düzlemi** (`gAXIS_1to2_switch`) ve bir
**veri düzlemi** (`gAXIM_3to1_switch`).

## Detaylı Açıklama
**Kontrol düzlemi** (`io_peripheralClk`): [[efx-sapphire-fcu]]'nun 32-bit `axiA` master'ı,
`TSE`(0)=[[gtse-mac]] CSR ve `SDHC`(1)=[[gsdhc]] CSR uzaylarına erişir; adres 25-bit'e
pencerelenir. Böylece FCU, MAC ve SD-host'un register master'ıdır.

**Veri düzlemi** (`io_ddrMasters_0_clk`): üç 128-bit master (`MTSE`=[[gdma]], `MSDHC`=[[gsdhc]],
`MFCU`=FCU) tek [[lpddr4x-controller]] slave'i için yarışır ([[shared-dram-arbitration]]).
Port index'leri `ti375_oob_top.v:246-253`'teki localparam'larla sabittir.

### Genişletme: 5'e 1 veri düzlemi anahtarı (2026-08)
`gAXIM_3to1_switch` yerini `gAXIM_5to1_switch`'e bıraktı (`ti375_oob_top.v` HEAD): yuvalar
`MTSE=0, MSDHC=1, MFCU=2, MDNN=3, MCODEC=4` (codec yuvası o tarihte boştaydı). `MDNN` önce
[[gdma-dnn]]/[[openeye]], sonra M7 ve M8'de [[stalyanpu]] tarafından kullanıldı; 128-bit,
`io_ddrMasters_0_clk`. Anahtar AXI ID taşımaz; `snpu_rd_dma` yanıtları ihraç sırasıyla
eşler. Yukarıdaki 3'e 1 anlatımı `docs/help` kaynaklarının tarihindeki durumdur.

### Üçüncü veri yolu: dedicated `axi_target0` portu (2026-09-15, M9)
NPU paylaşımlı anahtarın dışına alındı: `snpu_top` (256-bit AXI) → [[snpu-axi-up512]]
genişletici → [[lpddr4x-controller]]'ın dedicated 512-bit `axi_target0` portu
(`npu_ddr_*` pinleri), yine `io_ddrMasters_0_clk` alanında. `MDNN=3` yuvası HEAD'de
boştadır (localparam duruyor, sürücüsüz); `MCODEC=4` de boş. Böylece veri düzleminde iki
bağımsız DDR yolu vardır: anahtar üzerinden sert SoC köprüsü (`io_ddrMasters_0`, FCU,
gDMA, SDHC) ve doğrudan denetleyici portu (NPU). Kontrol düzlemi değişmedi; NPU CSR'ı sert
SoC AXI-A → `io_apbSlave_0` yolundan sürülür ([[accelerator-control-plane-apb]]). Port
pinlerinin zamanlama kısıtları için bkz. [[ddr-port-pin-constraints]].

### Güncel yuva dağılımı ve codec (2026-09-24)
Yukarıdaki "yuva boşta" ifadeleri eskidi. HEAD'de `MDNN=3` ikinci NPU örneğini (npu1, 16x8,
`axi_reg_slice` arkasında) taşır ([[multi-instance-npu]]); `MCODEC` adı kalktı, yuva 4
`MEMMC` olarak eMMC [[gsdhc]] DMA'sına verildi (`ti375_oob_top.v:317, 1706-1708`). Böylece
anahtarda boş yuva kalmadı. Video codec [[stalyavpu]] için anahtar 6:1 olarak yeniden
üretilecek ve codec yuva 5'i (`MVPU`, 128-bit, `vpu_clk` 160 MHz'ten asenkron köprüyle)
kullanacak ([[stalyavpu-decision-record]]).

## Örnekler
- Kontrol: FCU'nun `sp_m_axis_awaddr[24:0]` üzerinden MAC reset CSR'lerini (`0x080..0x083`) yazması.
- Veri: gDMA'nın `MTSE` portundan DDR'e 128-bit burst yazması.
- Veri (M9): NPU'nun `npu_ddr_*` üzerinden 64 B beat'lerle, 64 B hizalı wide burst'lerle DDR'a doğrudan erişmesi.

## İlişkili Kavramlar
- [[shared-dram-arbitration]]: veri düzleminin belleği paylaşma yolu ve NPU'nun bu paylaşımdan çıkışı
- [[ddr-port-pin-constraints]]: dedicated port pinlerinin SDC kısıtları
- [[ethernet-datapath]]: kontrol/veri düzlemlerini birlikte kullanan alt sistem
- [[dual-soc-architecture]]: topolojinin hizmet ettiği mimari
- [[accelerator-control-plane-apb]]: veri düzlemi yuvasına eşlik eden kontrol penceresi
- [[board-bringup-flow]]: iki yolun board ölçümlerindeki farkı (28,1 → 43,9 fps)
- [[fpga-timing-closure]]: `io_ddrMasters_0_clk` alanındaki kapanış
- [[descriptor-isa]]: CSR penceresi ve DBG yazmaçları
- Varlıklar: [[snpu-axi-up512]], [[lpddr4x-controller]]

## Kaynaklar
- [[hardware-architecture]], [[system-overview]]
- [[dnn-integration-gui-ip-steps]]: anahtarın 5 porta genişletilmesi
- [[stalyanpu-synthesis-guide]]: `MDNN` yuvasına bağlanan NPU (M7, eski)
- [[stalyanpu-architecture]]: DMA ve yanıt sıralaması
- [[stalyanpu-bringup-guide]]: dedicated `axi_target0` portu ve MDNN yuvasının boşa çıkması
