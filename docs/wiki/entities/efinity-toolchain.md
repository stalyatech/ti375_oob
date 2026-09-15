---
title: "Efinity Toolchain"
type: entity
category: product
created: 2026-07-03
updated: 2026-09-15
source_count: 6
tags: [toolchain, efinity, efinix, build]
---

# Efinity Toolchain

## Tanım
Efinix FPGA'ler için sentez, yerleşim/yönlendirme (place & route), arayüz tasarımı ve bit-akışı
üretimini sağlayan araç zinciri. Bu projede **sürüm 2025.2.288** kullanılır (önceden 2025.1).

## Temel Bilgiler
Proje dosyaları `ti375_oob.xml` (proje/akış), `ti375_oob.peri.xml` (arayüz tasarımı: PLL'ler,
[[lpddr4x-controller]], RGMII/MDIO, SD, clkmux) ve `ti375_oob.isf` (pin/bank/gerilim atamaları,
`qcrv32_inst1` SOC eşlemesi). Sürüm yükseltmesiyle IP çekirdekleri de yenilendi: `efx_soc`
3.2.3→3.3.0, `efx_tsemac` 6.4→7.0 ([[gtse-mac]]), `efx_dma` 6.4.1→6.4.2 ([[gdma]]). Son çalışma
akışı `place` durumundadır. Gömülü yazılım Efinity RISC-V IDE (Eclipse tabanlı) ile derlenir.

### NPU ve OpenEye akışları (2026-08/09)
- [[stalyanpu]] sentez rehberi: 2025.2, `efx_run ti375_oob --prj -f map|pnr|pgm`, `placer_effort_level` 3, seed taraması (`efx_run_pnr_sweep`), `min-sr-fanout` 64, `use-logic-for-small-mem` 8; SystemVerilog boyut dönüşümü (`N'(...)`) verilog_2k kipinde kabul edilmez.
- Vendor DSP sim modeli `sim_models/verilog/efx_dsp48.v` iverilog'da doğrudan derlenir; Efinity'nin OpenOCD'si ve FTDI programlayıcısı `board.py` tarafından çağrılır.
- OpenEye portunda Efinity'nin kabul etmediği yapılar: boyutsuz sıfır literalleri, karışık blocking/non-blocking atama, instance çıkışıyla sürülen `reg`, sabit sınır dışı indeks; tanımlar `efx:defmacro` ile geçirilir (bkz. [[openeye]]).

### Sert blok portu açma (2026-09-15, M9)
- Arayüz tasarımcısı [[lpddr4x-controller]] `axi_target0` portunu x32 LPDDR4x'te yalnız 512-bit açar (256-bit reddedilir); `efx_run -f interface` `outflow/ti375_oob_template.v` şablonunu üretir.
- Aynı adım `outflow/<prj>.pt.sdc` içinde port pinleri için `set_input_delay`/`set_output_delay` üretir, ancak bunlar proje `constraints.sdc`'sine kendiliğinden girmez; elle kopyalanmalıdır ([[ddr-port-pin-constraints]]).
- Akışı çağıran `.bat` sarmalayıcısında `call efx_run` şarttır; OpenOCD programlama sırasında açıksa JTAG'i kaybeder (`mpsse_flush`).

## Kaynaklarda Geçişi
- [[change-analysis]]: sürüm yükseltme tablosu
- [[system-overview]]: toolchain satırı
- [[stalyanpu-synthesis-guide]]: sentez seçenekleri ve seed taraması
- [[stalyanpu-verification-guide]]: vendor sim modeli
- [[stalyanpu-bringup-guide]]: programlama ve OpenOCD, arayüz tasarımcısı ile port açma, `pt.sdc` kısıtları
- [[openeye-upstream-issue]]: Efinity uyumluluk bulguları

## İlişkiler
- [[ti375c529]]: hedeflenen cihaz
- [[ti375-devkit]]: programlayıcı ve OpenOCD'nin hedefi
- [[stalyanpu-toolchain]]: OpenOCD ve programlayıcıyı çağıran `board.py`
- [[gtse-mac]], [[gdma]]: sürümü yükselen IP çekirdekleri
- [[lpddr4x-controller]]: arayüz tasarımcısında yapılandırılan sert blok
- [[snpu-axi-up512]]: arayüz tasarımcısının 512-bit dayatması yüzünden yazılan genişletici
- [[oob-to-fmu-transformation]]: toolchain geçişinin parçası olduğu dönüşüm
- [[efx-dsp48]]: sim modeli sağlanan DSP bloğu
- [[fpga-timing-closure]]: seed taraması ve kapanış süreci
- [[ddr-port-pin-constraints]]: `pt.sdc` kısıtlarının elle taşınması
