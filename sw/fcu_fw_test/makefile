# fcu_fw_test: FCU firmware for testing Linux remoteproc, linked into the FCU
# memory region in DDR (fw.ld). Linux loads build/fcu_fw_test.elf from
# /lib/firmware.
#
#   make RISCV_BIN=riscv-none-elf- MARCH=rv32imafdc_zicsr_zifencei MABI=ilp32d
#
# Uses the FCU BSP headers only for the drivers; start-up code and linker
# script are its own (the BSP's start.S parks the other harts on a DDR
# variable, which a later FCU hold could catch mid-transfer).

PROJ_NAME  = fcu_fw_test

PROJ_ROOT  ?= $(abspath ../..)
STANDALONE := $(PROJ_ROOT)/embedded_sw/EfxSapphireFCU/software/standalone
BSP_PATH   := $(PROJ_ROOT)/embedded_sw/EfxSapphireFCU/bsp/efinix/EfxSapphireSoc

CFLAGS += -I$(PROJ_ROOT)/sw/amp

DEBUG    = no
DEBUG_OG = no

SRCS = $(wildcard src/*.c) src/start.S

include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk

LDSCRIPT = fw.ld
