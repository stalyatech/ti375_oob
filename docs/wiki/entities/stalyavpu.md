---
title: "StalyaVPU"
type: entity
category: product
created: 2026-09-24
updated: 2026-09-24
source_count: 1
tags: [stalyavpu, vpu, codec, h264, hevc, video, rtl]
---

# StalyaVPU

## Tanım
Ti375 için tasarlanan H.264/H.265 video codec IP'si. `ip/stalyavpu` submodule'ü
(`https://github.com/stalyatech/StalyaVPU.git`), RTL öneki `svpu_`, Python paketi `stalyavpu`.
İlk blok 1080p30 H.264 decoder'dır; HEVC decoder ve encoder sonra gelir.

## Temel Bilgiler
- **Kapsam (ilk blok):** H.264 High profile, progressive, 8-bit 4:2:0, CABAC ve CAVLC; sıra
  I, P, B. Interlaced, FMO ve ASO kapsam dışı.
- **Bölüm:** stateless. Yazılım SPS/PPS, slice header, POC, DPB ve referans listelerini
  çıkarıp resim başına descriptor yazar; donanım `slice_data()` baytından NV12 çıkışa kadar
  çalışır. Descriptor alanları V4L2 stateless kontrollerine eşlenir.
- **Boru hattı:** bitstream okuyucu → CABAC/CAVLC → sözdizimi → MB/CTU komut FIFO'su →
  dequant/ters dönüşüm, MV tahmini, MC, intra → rekonstrüksiyon → deblocking → çıkış yazıcı.
  H.264 makrobloğu 16x16 CTU olarak işlenir.
- **Saat ve bağlantı:** `vpu_clk` 160 MHz; DDR'a 6:1 switch'in yuva 5'inden (128-bit, asenkron
  köprü); kontrol sert SoC APB `0xE810_C000`; kesme PLIC 3.
- **Başarım ölçütleri:** kare MD5'i ffmpeg ile bit bit aynı; 1080p 20 Mbps IPB'de ortalama
  ≥ 36 fps; ≤ 545 çevrim/MB; DDR ≤ 500 MB/s; H.264 decoder RAM10 ≤ 150, XLR ≤ 60k,
  DSP48 ≤ 96.
- **Kaynak dengesi:** DSP48 bol, RAM10 ve XLR kıt; sabit katsayılı çarpımlar DSP48'e eşlenir.
  Yer açmak için npu0 tamponları küçültülür ([[stalyavpu-decision-record]]).
- **Durum (2026-09-24):** V0 tamam, commit bekliyor. Submodule iskeleti, belgeler (`docs/`),
  11 akışlık üretilmiş test seti (`python -m stalyavpu streams`, ffmpeg 9.0.2 + libx264) ve
  ITU-T H.264.1 conformance seçimi (`python -m stalyavpu conformance`: 176 akıştan 98'i
  kapsamda, 13 996 kare; ölçekleme matrisi, I_PCM ve constrained intra gerektiriyor).
- **V1 (2026-09-24):** Python referans modeli (`py/stalyavpu/h264/`): yazılım tarafı (parametre
  setleri, POC, DPB, referans listeleri, MMCO, descriptor) ve decoder tarafı (CAVLC, CABAC, MV
  tahmini, intra/inter, ağırlıklı tahmin, dönüşüm, deblocking). Conformance 98/98 ve üretilmiş
  küçük akışlar ffmpeg ile bit bit aynı. Descriptor ikili düzeni ve C başlığı hazır; model her
  resmi bu ikili biçimden çözer. Perf modeli 1080p'de 20 Mbps için ortalama 213 çevrim/MB
  (92 fps), 40 Mbps için 344 (57 fps) tahmin ediyor; sınırlayıcı aşama I resimlerinde CABAC.

> ❓ **Belirsiz:** `amp_ctrl`'ün APB adres aralığının `0xE810_C000` penceresine taşmadığı
> entegrasyon adımında (V5) doğrulanacak. Linux `no-map` bölgesinin adresi V6'da DTS ile
> kesinleşecek.

## Kaynaklarda Geçişi
- [[stalyavpu-decision-record]]: hedef, kaynak ölçümü, NPU küçültmesi, mimari kararlar

## İlişkiler
- [[stalyanpu]]: aynı FPGA'yı paylaştığı NPU; npu0 tamponları codec için küçültülür, decoder
  çıkışı NPU girdisi olabilir
- [[lpddr4x-controller]]: çıkış kareleri ve referanslar için DDR
- [[ti375c529]], [[ti375-devkit]]: hedef cihaz ve board
- [[gsdhc]]: codec için ayrılan switch yuvasını bugün kullanan eMMC denetleyicisi
- Kavramlar: [[shared-dram-arbitration]], [[axi-interconnect-topology]], [[accelerator-control-plane-apb]], [[hard-soc-fabric-interrupt-path]], [[multi-instance-npu]], [[fpga-timing-closure]], [[descriptor-isa]]
