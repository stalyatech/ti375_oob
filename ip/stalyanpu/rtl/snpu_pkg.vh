// =============================================================================
// snpu_pkg.vh
//
// Shared constants of the StalyaNPU accelerator. Geometry values here are the
// defaults of the full array; modules take them as parameters so a smaller
// build (for example N_CHAIN=8, CHAIN_LEN=16) only needs new top level
// parameters.
// =============================================================================
`ifndef SNPU_PKG_VH
`define SNPU_PKG_VH

// Array geometry. One chain holds CHAIN_LEN cascaded DSP48 blocks in DUAL
// mode, each block multiplies one activation by two weights. A chain covers
// CHAIN_LEN input channels and two output channels, so the array processes
// CHAIN_LEN input channels by 2*N_CHAIN output channels per cycle.
`define SNPU_N_CHAIN     32
`define SNPU_CHAIN_LEN   32
`define SNPU_P_MAX       1024
`define SNPU_IBUF_WORDS  16384
`define SNPU_AXI_DW      128

// Weight fill port width. Each fill word carries FILL_W/16 weight pairs.
`define SNPU_FILL_W      256

// Descriptor opcodes (word 0, bits 7:0).
`define SNPU_OP_NOP      8'h00
`define SNPU_OP_CONV     8'h01
`define SNPU_OP_MAXPOOL5 8'h02
`define SNPU_OP_COPY     8'h03
`define SNPU_OP_BARRIER  8'h04
`define SNPU_OP_END      8'hFF

// Descriptor flags (word 0, bits 23:8, bit index relative to bit 8).
`define SNPU_FLAG_SILU       0
`define SNPU_FLAG_RESIDUAL   1
`define SNPU_FLAG_IRQ        2
`define SNPU_FLAG_LAST       3
`define SNPU_FLAG_UPS0       4
`define SNPU_FLAG_UPS1       5
`define SNPU_FLAG_TWO_SRC    6
`define SNPU_FLAG_L0_MODE    7
`define SNPU_FLAG_WAIT_PREV  8
`define SNPU_FLAG_DEBUG_DUMP 9

// Descriptor size in bytes and 32-bit words.
`define SNPU_DESC_BYTES  128
`define SNPU_DESC_WORDS  32

// CSR identification.
`define SNPU_ID          32'h534E5055
`define SNPU_VERSION     32'h00000100

`endif
