// =============================================================================
// snpu_config.vh
//
// Geometry of the StalyaNPU instance of this project. Written by
//   python -m stalyanpu project apply --geometry <chains>x<length>
// in ip/stalyanpu. Change it through that command so the recorded
// geometry, the compiled model and the bitstream stay in step.
//
// Configuration: snpu32x16
// Array: 32 chains of 16 DSP48 blocks, 1024 INT8 MAC per cycle, 512 array DSPs.
// Buffers: 512 KB input buffer, 32 KB weight FIFO, 1024 pixel tiles.
// The AXI width and the write burst length come from the board data
// path (dedicated 512 bit DDR port through snpu_axi_up512).
// =============================================================================
`ifndef SNPU_CONFIG_VH
`define SNPU_CONFIG_VH

`define SNPU_CFG_N_CHAIN        32
`define SNPU_CFG_CHAIN_LEN      16
`define SNPU_CFG_P_MAX          1024
`define SNPU_CFG_P_W            10
`define SNPU_CFG_IBUF_WORDS     16384
`define SNPU_CFG_IBUF_AW        14
`define SNPU_CFG_WFIFO_WORDS    1024
`define SNPU_CFG_WFIFO_AW       10
`define SNPU_CFG_OC_MAX         512
`define SNPU_CFG_AXI_DW         256
`define SNPU_CFG_WR_SLOT_WORDS  64
`define SNPU_CFG_MP_MAX_W       128
`define SNPU_CFG_MP_W_AW        7

// Value the GEOMETRY register reports for this build.
`define SNPU_CFG_GEOMETRY       32'h200A1020

`endif
