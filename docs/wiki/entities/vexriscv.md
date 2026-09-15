---
title: "VexRiscv Çekirdeği"
type: entity
category: product
created: 2026-07-03
updated: 2026-07-03
source_count: 1
tags: [riscv, cpu, sapphire, saxonsoc]
---

# VexRiscv Çekirdeği

## Tanım
Efinix Sapphire SoC'larının temelindeki SpinalHDL tabanlı, yapılandırılabilir **RISC-V**
yazılım çekirdeği (SaxonSoc soyağacı).

## Temel Bilgiler
Bu tasarımda **RV32IMAFDC** olarak yapılandırılmıştır: M, A, C uzantıları + tek/çift-hassasiyet
FPU (F, D) + Zicsr/Zifencei, ayrıca MMU ve Supervisor modu. [[efx-sapphire-fcu]] dört çekirdekli
(SMP) bir konfigürasyon kullanır; her çekirdek 8 KB 2-yollu I/D önbelleğe sahiptir ve CLINT
200 MHz'dir. Kesmeler PLIC üzerinden dağıtılır. `soc.h` içindeki `SYSTEM_RISCV_ISA_*` tanımları
bu yetenek kümesini doğrular.

## Kaynaklarda Geçişi
- [[software-architecture]]: ISA ve SMP bölümü

## İlişkiler
- [[efx-sapphire-fcu]], [[efx-sapphire-hpsoc-slb]]: bu çekirdeği kullanan SoC'lar
- [[nuttx]]: çekirdek üzerinde koşan RTOS
