/*
 * fcu_fw_test: linked into the FCU memory region (AMP_FCU_MEM_BASE in
 * sw/amp/amp_ctrl.h), where Linux remoteproc loads it. One loadable segment;
 * the loader zero-fills .bss and the stacks (memsz > filesz).
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    fcu (wxa!r) : ORIGIN = 0x1E000000, LENGTH = 1M
}

PHDRS
{
    fcu PT_LOAD;
}

SECTIONS
{
    .text : {
        KEEP(*(.init))
        *(.text .text.*)
    } >fcu :fcu

    .rodata : ALIGN(4) {
        *(.rodata .rodata.* .srodata .srodata.*)
    } >fcu :fcu

    .data : ALIGN(8) {
        *(.data .data.*)
        PROVIDE(__global_pointer$ = . + 0x7F0);
        *(.sdata .sdata.*)
    } >fcu :fcu

    .bss (NOLOAD) : ALIGN(8) {
        __bss_start = .;
        *(.sbss .sbss.* .bss .bss.* COMMON)
        . = ALIGN(8);
        _end = .;
    } >fcu :fcu

    .stack (NOLOAD) : ALIGN(16) {
        . += 4K;
        _sp = .;
    } >fcu :fcu
}
