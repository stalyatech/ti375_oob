# Efinity GUI IP Manager — DNN Pipeline için Üretilecek IP'ler

Bu doküman, DNN (OpenEye) + codec pipeline'ı için Efinity GUI'de üretmen gereken **3 IP'yi**
birebir değerlerle anlatır. IP üretimi CLI ile güvenilir olmadığından (bkz. [README](README.md))
bu adımlar GUI'de yapılır. Her üretimden sonra tasarım yeniden **sentez + PnR** gerektirir; onu
`efx_run` ile ben koşabilirim.

> **Genel akış (GUI):** Efinity'yi aç → projeyi aç → sol panelde **IP** sekmesi → **Add IP** (veya
> mevcut IP'ye çift tıkla → Configure) → katalogdan IP'yi seç → aşağıdaki değerleri gir →
> **Generate**. Üretim `ip/<isim>/` altına `.v` + `settings.json` yazar ve projeye ekler.

---

## Kontrol düzlemi kararı (önemli — plandan revizyon)

Hard SoC'un fabric'e **AXI master'ı yok** (`axiA` slave; `intf_axim` yalnızca DDR master'ı).
Efinity Sapphire Hard SoC'ta özel fabric peripheral'e erişmenin **desteklenen** yolu bir
**APB3 peripheral** portu açmaktır (config'de `peri_apb_0..4` var, şu an kapalı). Bu, FCU'nun
`gDMA`'yı APB ile kontrol etmesiyle **birebir aynı** desendir ve mevcut
[`rtl/apb3_2_axi4_lite.v`](../../rtl/apb3_2_axi4_lite.v) köprümüzle AXI4-Lite'a çevrilir.

**Kontrol topolojisi:**
```
Hard SoC (io_apbSlave_0, APB3 master)
        │
        ▼  APB adres decode (PADDR)
   ┌────┴────────────┬──────────────────┐
   ▼                 ▼                   ▼
 gDMA_dnn ctrl   apb3_2_axi4_lite    apb3_2_axi4_lite
 (APB native)    → OpenEye cfg_reg   → codec_h26x_stub ctrl
```

---

## IP 1 — `gAXIM_4to1_switch` (yeni)

DNN DMA'sına DDR'de 4. master yuvası (`MDNN`) açar.

- **Katalog:** `efx_axi_interconnect` (v5.4) — `axi_infra` kütüphanesi.
- **Başlangıç:** mevcut `ip/gAXIM_3to1_switch`'i referans al (aynı ayarlar).
- **Değişecek tek şey:** slave port sayısı **3 → 4**.

| Parametre | Değer |
|-----------|-------|
| `S_PORTS` | **4** (3to1'de 3 idi) |
| `M_PORTS` | 1 |
| `DATA_WIDTH` | 128 |
| `ADDR_WIDTH` | 32 |
| `ID_WIDTH` | 8 |
| `USER_WIDTH` | 3 |
| `PROTOCOL` | AXI4 |
| `ARB_MODE` | ROUND_ROBIN_1 |
| Adres tablosu (`TABLE0_AXI_S0..S3`) | 3to1 ile aynı bırak (tek DDR hedefi; GUI otomatik doldurur) |

> İsim olarak `gAXIM_4to1_switch` ver. (Codec'i de aynı anda eklemek istersen `S_PORTS=5` yapıp
> `gAXIM_5to1_switch` üret — `MDNN` + `MCODEC` birlikte.)

---

## IP 2 — `gDMA_dnn` (yeni)

OpenEye'ın 64-bit `dma_i`/`dma_o` AXI-Stream'lerini DDR ile taşır.

- **Katalog:** `efx_dma` (v6.4.2) — `bridges_and_adaptors` kütüphanesi.
- **Başlangıç:** mevcut `ip/gDMA`'yı referans al (aynı MemExtWidth=128, SG mode, async).
- **Kanal ayarı (OpenEye için):**

| Ayar | Değer | Neden |
|------|-------|-------|
| `MemExtWidth` | 128 | DDR AXI master genişliği (gAXIM_4to1 ile uyumlu) |
| Kanal A: MEM→STREAM | Output, **Width=64**, SG mode, BurstSize~1024 | Ağırlık/aktivasyon'u OpenEye `dma_i`'ye besler |
| Kanal B: STREAM→MEM | Input, **Width=64**, SG mode | OpenEye `dma_o` sonucunu DDR'e yazar |
| `CTRL_ASYNC_MODE` | 1 | APB kontrol saati ≠ DDR saati |
| Kanal AsyncMode | 1 (stream saati ≠ DDR ise) | OpenEye saati farklıysa CDC |

> Mevcut `gDMA` 8-bit Ethernet stream'leri için ayarlı; `gDMA_dnn`'de stream genişliğini **64**
> yap (OpenEye DMA_BITWIDTH=64). Kanal sayısı/derinlik bring-up'ta ayarlanır. İsim: `gDMA_dnn`.

---

## IP 3 — Hard SoC'a APB3 peripheral portu aç (regen)

Hard SoC'un DNN/DMA/codec kontrol slave'lerini sürebilmesi için bir APB3 master portu ekler.

- **Katalog:** mevcut `EfxSapphireHpSoc_slb` IP'sini **Configure** et (efx_hard_soc).
- **Değişiklik:** IP configurator'da **APB peripheral 0**'ı etkinleştir.
  - `hard_ip_args.ini` karşılığı: `peri_apb_0 = 1` (şu an `0`), `peri_apb_0_size = 65536` (zaten var).
  - Bu, top'a bir `io_apbSlave_0_*` (APB3) master portu ekler — FCU'daki `io_apbSlave_0` gibi.
- **Regenerate** et. Bu, çalışan `place` durumunu bozar → yeniden sentez/PnR gerekir (en yüksek
  etkili adım budur).

> Not: Bu adım Linux/OS'tan bağımsızdır — sadece donanım peripheral arayüzü ekler. "Hard SoC'ta
> Linux" ayrı bir yazılım/boot işidir.

---

## Adres haritası (öneri — GUI'de kesinleştir)

Hard SoC APB peripheral penceresi (ör. `io_apbSlave_0`, 64 KB) içinde PADDR decode:

| Aygıt | APB alt-pencere | Köprü |
|-------|-----------------|-------|
| `gDMA_dnn` kontrol | 0x0000–0x3FFF | APB native (gDMA gibi) |
| OpenEye `cfg_reg` | 0x4000–0x40FF | `apb3_2_axi4_lite` → AXI4-Lite |
| `codec_h26x_stub` kontrol | 0x8000–0x80FF | `apb3_2_axi4_lite` → AXI4-Lite |

DDR master yuvaları: `MTSE=0, MSDHC=1, MFCU=2, MDNN=3` (codec eklenirse `MCODEC=4`).
DNN "done" IRQ: Hard SoC `userInterruptA` (`openeye_irq` üzerinden); codec: `userInterruptB`.

---

## Üretimden sonra (bende)

3 IP hazır olunca ben şunları yaparım:
1. `ti375_oob_top.v` üst-seviye wiring: `open_eye_mt_v1_0`, `gDMA_dnn`, `gAXIM_4to1_switch`,
   `apb3_2_axi4_lite`, `openeye_irq`, `codec_h26x_stub` örnekleme + bağlama; `MDNN`/`AXIM_DEV`
   localparam'ları; `MHSDC → MSDHC` düzeltmesi.
2. OpenEye kaynaklarını `ti375_oob.xml`'e ekleme + `USE_INTERNAL_PARAMS` define + `hdl/include` yolu.
3. `efx_run` ile sentez/PnR koşup util + timing raporlama (BRAM'e dikkat; gerekirse OpenEye geometrisini küçültme).
