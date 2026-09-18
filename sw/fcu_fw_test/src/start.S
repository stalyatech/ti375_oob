/*
 * fcu_fw_test start-up. All four FCU harts arrive here from the on-chip RAM
 * boot stub. Hart 0 runs main(); the others idle in wfi with interrupts off,
 * so they fetch nothing from DDR and a later FCU hold cannot catch one of them
 * in the middle of a bus transfer.
 */
    .section .init
    .globl _start
_start:
.option push
.option norelax
    la      gp, __global_pointer$
.option pop
    csrc    mstatus, 8              /* MIE off */
    csrr    a0, mhartid
    bnez    a0, park_hart

    la      sp, _sp
    la      a0, __bss_start
    la      a1, _end
1:  bgeu    a0, a1, 2f
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       1b
2:  call    main

park_hart:
    wfi
    j       park_hart
