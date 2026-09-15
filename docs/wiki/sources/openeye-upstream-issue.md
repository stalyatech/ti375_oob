---
title: "Kaynak: OpenEye Upstream Issue Taslağı"
type: source
source_file: "docs/dnn-integration/upstream-issue.md"
author: "volvox"
date: 2026-08-27
created: 2026-09-15
updated: 2026-09-15
tags: [openeye, upstream, bisect, cocotb, regression, verification]
---

# Kaynak: OpenEye Upstream Issue Taslağı

## Özet
[[learning-chips-lab]]'ın [[openeye]] deposuna açılmak üzere hazırlanmış İngilizce issue
taslağıdır. Başlık: "FPGA level conv test fails on main since July 2026 (psum_enable clear, PE
rewrite)". Upstream `main` (`fe2f5ed`) üzerinde FPGA seviyesi konvolüsyon testinin düştüğünü,
yalın bir checkout'un da aynı davranışı gösterdiğini ve git bisect ile iki ayrı regresyonun
bulunduğunu raporlar. Ayrıca Efinity Titanium akışına port sırasında bulunan beş ek kusuru
listeler ve tüm yamaların stalyatech fork'unun `stalya-upstream` dalında (`21db525`) olduğunu
belirtir. Yöntem [[upstream-regression-bisect]] kavram sayfasında genellenmiştir.

## Temel Çıkarımlar
- `main`'de her çıkış kelimesi akıtılan bias'a eşittir; PE dizisi hiçbir katkı yapmaz.
- Birinci regresyon `d19314a`: `PSUM_GET_RESULTS` başındaki `psum_enable_i_reg <= 0` satırının
  kaldırılması. Yalnız bu hunk geri alınınca commit geçer.
- İkinci regresyon `ff4f99f`: PE.v yeniden yazımı; `ff4f99f`, `a030ba9`, `302f94e` elaborate
  olmaz, `9d1aba8`'den `fe2f5ed`'e kadar test bias-only çıktıyla düşer.
- Son sağlam commit `3531eb3` (tek satırlık psum_enable düzeltmesiyle).
- 2x2 çok-cluster yolu `3531eb3`'te bile düşer; upstream pytest matrisi eksik env yüzünden
  hiç çalışmaz.

## Detaylı Notlar

### Ortam ve harness
Icarus Verilog 12, cocotb 2.0.1, Python 3.11, TensorFlow 2.21, Windows 11. Harness
`test/cocotb_fpga/OpenEye_FPGA_tb.py`, Makefile `run` hedefiyle birebir aynı biçimde sürülür
(generator, vh_file_creator, `USE_INTERNAL_PARAMS_PE` define'ları). Katman: Convolution,
NUM_FILTERS=16, INPUT 4x2x4, CLUSTER 1x1, NUM_GLB_IACT=1, IACT_RAM_CELLS=4, BUFFER_WIDTH=9,
DMA_BITWIDTH=32, PARALLEL_MACS=1, SPARSITY_EN=0.

### Bisect zinciri
1. `ca5a7dc` geçer (2x2, o dönemin Makefile'ındaki FC katmanı). Bu, projenin üretim tabanıdır.
2. `d19314a` ("Fix PSUM datapath bugs causing zero-output on GEMM/attention layers") conv testini
   kırar; sorumlu hunk `psum_enable_i_reg <= 0` kaldırımıdır.
3. `1f29695` ve `00893e0` `raw_wght` bayrağını `stream_data[8]`'e taşır, conv tekrar kırılır;
   `7abd08c` ve `6611d1f` bit pozisyonunu düzeltir.
4. `8350a00` kırılma değildir; Makefile katmanını INPUT_SIZE_X=16'ya çıkarır, bu konfigürasyona
   sığmaz (`3531eb3` de INPUT_SIZE_X=16 ile düşer).
5. `3531eb3` düzeltmeyle geçen son commit.
6. `ff4f99f` ("Tested PE for Sparsity and Dense and SIMD and SISD") PE.v'yi yeniden yazar;
   `delay_cluster` çıkışları reg olmadığından üç commit elaborate olmaz, sonrası bias-only.

### Port sırasında bulunan ek kusurlar
- `generator.py` son virgülü text-mode `seek` ile siler; Windows'ta bozulur.
- `GET_PARAMETERS` `GET_ROUTER_CONFIG` öncesinde `fsm_cycle`'ı sıfırlamaz; çok-cluster çıkış
  koşuluna hiç ulaşılmaz.
- `quant_exp` ve `quant_mant` `OFFSET_WIDTH` ile dilimlenir, mantis 8 bite kırpılır.
- `PE.v` döngü değişkeni `pmc`'yi döngü bittikten sonra (indeks PARALLEL_MACS) iki yerde kullanır.
- `layer_parameters.py` `trans_cycles_psum` ve `psum_output_words`
  `different_kernels_per_calculation`'ı yok sayar, üretilen stream'lerle uyuşmaz.

> ❓ **Belirsiz:** 2x2 çok-cluster + 64-bit DMA yolunun `3531eb3`'te bile düşmesi, upstream'in bu
> yolu `ca5a7dc` sonrasında hiç test etmediğini düşündürür; ancak `fsm_cycle` bulgusu dışında
> kök neden izole edilmemiştir. Bu projenin üretim geometrisi (2x2, 64-bit) tam olarak bu yoldur.

### Projeye etkisi
Bu bulgular, [[dnn-integration-readme]]'deki kararı gerekçelendirir: üretim `ca5a7dc` + yerel
yamalarda kalır, upstream'e geçiş `stalya-upstream` dalında bekler. Kısa süre sonra OpenEye hattı
tümüyle durdurulmuş ve [[stalyanpu]]'ya geçilmiştir ([[dnn-accelerator-options]]); issue'nun
upstream'e gerçekten açılıp açılmadığı kaynakta belirtilmez.

## Bağlantılar
- İlgili varlıklar: [[openeye]], [[learning-chips-lab]], [[stalyanpu]]
- İlgili kavramlar: [[upstream-regression-bisect]], [[file-driven-directed-testbench]],
  [[dnn-accelerator-options]]
- İlgili kaynaklar: [[dnn-integration-readme]] (bisect tablosunun özeti orada)

## Alıntılar
- "every output word equals the bias that was streamed in, so the PE array contributes nothing"
  (Observed on main).
- "reverting only that hunk makes d19314a pass again" (Bisect results, madde 2).
