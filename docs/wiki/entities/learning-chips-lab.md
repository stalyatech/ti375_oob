---
title: "Learning-Chips-Lab"
type: entity
category: organization
created: 2026-09-15
updated: 2026-09-15
source_count: 2
tags: [openeye, upstream, open-source, license]
---

# Learning-Chips-Lab

## Tanım
[[openeye]] DNN hızlandırıcısının upstream deposunu (`Learning-Chips-Lab/OpenEye`) sürdüren ve
SHL-2.1 (Solderpad Hardware License 2.1) lisansıyla yayımlayan açık kaynak donanım grubu.

## Temel Bilgiler
Projede `upstream` uzak deposu olarak görünür; stalyatech fork'u (`origin`) buradan türemiştir.
Kaynaklara göre depo 2026 Temmuz'unda yoğun değişim geçirmiştir: PSUM veri yolu düzeltmeleri
(`d19314a`), `raw_wght` bayrak taşımaları, PE.v'nin yeniden yazımı (`ff4f99f`) ve `OpenEye_FPGA.v`
yeniden yazımı. Fork `main`, 2026-08-27'de upstream `fe2f5ed` ile günceldir (`ca5a7dc`'nin 79
commit ilerisi).

Bu projenin bisect çalışması ([[upstream-regression-bisect]]) upstream `main`'in FPGA seviyesi
konvolüsyon testinde bias-only çıktı verdiğini ve 2x2 pytest matrisinin eksik ortam değişkenleri
yüzünden hiç çalışmadığını göstermiştir. Bulgular ve yamalar bir issue taslağında
([[openeye-upstream-issue]]) derlenmiş, stalyatech fork'unun `stalya-upstream` dalına konmuştur.
Yerel yamaların upstream'e PR olarak taşınması "ayrı iş" olarak not edilmiş; OpenEye hattı
2026-08-28'de durdurulduğundan bu taşımanın yapılıp yapılmadığı kaynaklarda yer almaz.

> ❓ **Belirsiz:** Kuruluşun kimliği (akademik grup, şirket) ve issue'nun upstream'e gerçekten
> açılıp açılmadığı kaynaklarda belirtilmez.

## Kaynaklarda Geçişi
- [[dnn-integration-readme]]: `upstream` = Learning-Chips-Lab/OpenEye, SHL-2.1 lisansı
- [[openeye-upstream-issue]]: upstream'e yönelik regresyon raporu

## İlişkiler
- [[openeye]]: sürdürdüğü ürün
- [[upstream-regression-bisect]]: deposuna uygulanan bisect yöntemi
