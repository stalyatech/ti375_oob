# fcu_test — FCU bring-up test, linked for the FCU's on-chip RAM.
#
# Builds against the FCU BSP that Efinity generates into embedded_sw/. The
# on-chip RAM is only 16 KiB and the FCU starts there after reset, so this
# links with the BSP's bootloader.ld (0xF900_0000) instead of default.ld (DDR).
#
#   make                          build/fcu_test.{elf,bin,hex}
#   make RISCV_BIN=riscv-none-elf- MARCH=rv32imafdc_zicsr_zifencei MABI=ilp32d
#
# SMP is required: all four FCU harts start at the same address, and without
# it start.S lets every one of them run main().

PROJ_NAME  = fcu_test

PROJ_ROOT  := $(abspath ../..)
STANDALONE := $(PROJ_ROOT)/embedded_sw/EfxSapphireFCU/software/standalone
BSP_PATH   := $(PROJ_ROOT)/embedded_sw/EfxSapphireFCU/bsp/efinix/EfxSapphireSoc

CFLAGS += -DSMP
CFLAGS += -I$(PROJ_ROOT)/sw/amp

DEBUG    = no
DEBUG_OG = no

SRCS = $(wildcard src/*.c) \
       ${STANDALONE}/common/start.S

include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk

LDSCRIPT = ${BSP_PATH}/linker/bootloader.ld
