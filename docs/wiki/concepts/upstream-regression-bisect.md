---
title: "Upstream Regresyon Bisect Yöntemi"
type: concept
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [bisect, git, cocotb, verification, upstream, regression]
---

# Upstream Regresyon Bisect Yöntemi

## Tanım
Bir açık kaynak IP'nin upstream geçmişinde fonksiyonel regresyonun hangi commit'te girdiğini,
upstream'in kendi test harness'ini yalın worktree'lerde koşarak bulma yöntemi. [[openeye]] upstream
`main`'inin bozuk olduğunun kanıtlanmasında uygulanmıştır.

## Detaylı Açıklama

### Yöntem
1. **Yalın worktree'ler.** Her aday commit için proje yamaları olmadan pristine bir git worktree
   açılır; böylece hata yerel değişikliklere değil upstream'e atfedilebilir. `fe2f5ed` üzerinde
   yalın kopya da düşünce sorunun "bizim değişikliklerimizde olmadığı" gösterilmiştir.
2. **Upstream harness'i Windows'ta çalıştırmak.** `test/cocotb_fpga/OpenEye_FPGA_tb.py`, cocotb
   2.0.1 + Icarus Verilog 12 VPI, Python 3.11, TensorFlow 2.21 ile ayağa kaldırılır. Sürücü
   betikleri Makefile `run` hedefiyle birebir aynı zinciri (generator, vh_file_creator,
   `USE_INTERNAL_PARAMS_PE` define'ları) çalıştırır.
3. **Commit başına Makefile ortamı.** Katman geometrisi upstream Makefile'ından commit'e göre
   değişir (`8350a00` INPUT_SIZE_X'i 4'ten 16'ya çıkarır). Bu yüzden her commit için env
   değişkenleri o commit'in kapasitesine göre sabitlenir; aksi halde kapasite sınırı sahte
   regresyon gibi görünür.
4. **Hunk seviyesinde geri alma.** Şüpheli commit'in yalnız tek bir hunk'ı geri alınıp test
   tekrarlanır; commit'in hangi satırının sorumlu olduğu böyle izole edilir (`d19314a`'da
   `psum_enable_i_reg <= 0` satırı).
5. **Elaborate olmayan commit'leri ayırt etmek.** Sentez/elaborate hatası veren commit'ler
   (`ff4f99f`, `a030ba9`, `302f94e`) "FAIL" değil "test edilemez" olarak işaretlenir.

### Bulgular
| Commit | Tarih | Sonuç |
|---|---|---|
| `ca5a7dc` | 2025 | PASS, üretim tabanı (`stalya` dalı) |
| `d19314a` | 2026-07-20 | 1. regresyon: `PSUM_GET_RESULTS` girişindeki `psum_enable_i_reg <= 0` kaldırıldı |
| `1f29695` / `00893e0` | 2026-07-23 | `raw_wght` bayrağı yanlış bite taşındı; `7abd08c` / `6611d1f` düzeltti |
| `8350a00` | 2026-07-20 | Kırılma değil, Makefile katmanı büyütüldü (kapasite sınırı) |
| `3531eb3` | 2026-07-24 | Son sağlam durum (tek satırlık düzeltmeyle) |
| `ff4f99f` | 2026-07-24 | 2. regresyon: PE.v yeniden yazımı; `9d1aba8`..`fe2f5ed` bias-only FAIL |

Belirti her iki regresyonda aynıdır: her çıkış kelimesi akıtılan bias'a eşittir, PE dizisi katkı
yapmaz. Port sırasında bulunan ek kusurlar (Windows text-mode seek, `fsm_cycle` sıfırlanmaması,
mantis kırpılması, döngü değişkeni `pmc`'nin döngü sonrası kullanımı, `layer_parameters.py`
uyumsuzluğu) [[openeye-upstream-issue]]'da listelenir; yamalar `stalya-upstream` (`21db525`)
dalındadır.

> ❓ **Belirsiz:** 2x2 çok-cluster + 64-bit DMA yolu (projenin üretim geometrisi) `3531eb3` +
> düzeltmeyle bile düşer. Upstream `test_single_layers.py` eksik env değişkenleri (`BRANCHES`,
> `BUFFER_WIDTH`, `BUFFER_WIDTH_WGHT`) yüzünden hiç çalışmadığından bu yolun `ca5a7dc` sonrasında
> upstream'de test edilmediği düşünülür; kök neden ayrı bir bisect ile izole edilmemiştir.

### Sonuç ve karar
Üretim `ca5a7dc` + yerel yamalarda kalmış, upstream'e geçiş `stalya-upstream` dalında bekletilmiş,
ardından OpenEye hattı tümüyle durdurulmuştur ([[dnn-accelerator-options]], [[stalyanpu]]).
Yöntem, [[learning-chips-lab]] deposuna açılacak issue'nun kanıt zincirini oluşturur.

## Örnekler
- `d19314a`: yalnız psum_enable hunk'ı geri alınınca PASS; commit'in geri kalanı masumdur.
- `8350a00`: `3531eb3` de INPUT_SIZE_X=16 ile düşer; dolayısıyla kırılma değil kapasite sınırıdır.

## İlişkili Kavramlar
- [[file-driven-directed-testbench]]: projenin kendi hafif harness'i; bisect için upstream
  harness tercih edilmiştir çünkü permütasyon ve maske karşılaştırması içerir
- [[dnn-accelerator-options]]: bulguların beslediği karar

## Kaynaklar
- [[openeye-upstream-issue]]: ortam, harness ayarları ve bisect zinciri
- [[dnn-integration-readme]]: bisect tablosu ve üretim kararı
