// =============================================================================
// snpu_system.vh
//
// Geometry of every StalyaNPU instance of this project, one macro set per
// instance. Written by python -m stalyanpu system apply in ip/stalyanpu from
// rtl/snpu_system.json. Change the system through that command or the System
// page of the web interface, not by hand.
// =============================================================================
`ifndef SNPU_SYSTEM_VH
`define SNPU_SYSTEM_VH

// Instance npu0 (u_snpu): 16 chains of 16 DSP48 blocks, 512 MAC per cycle,
// CSR slot 0 at 0xE8104000, DDR port axi_target0, interrupt line I (PLIC 9).
`define SNPU_NPU0_N_CHAIN        16
`define SNPU_NPU0_CHAIN_LEN      16
`define SNPU_NPU0_P_MAX          1024
`define SNPU_NPU0_P_W            10
`define SNPU_NPU0_IBUF_WORDS     16384
`define SNPU_NPU0_IBUF_AW        14
`define SNPU_NPU0_WFIFO_WORDS    1024
`define SNPU_NPU0_WFIFO_AW       10
`define SNPU_NPU0_OC_MAX         512
`define SNPU_NPU0_AXI_DW         256
`define SNPU_NPU0_WR_SLOT_WORDS  64
`define SNPU_NPU0_MP_MAX_W       128
`define SNPU_NPU0_MP_W_AW        7
`define SNPU_NPU0_GEOMETRY       32'h200A1010

// Instance npu1 (u_snpu_npu1): 16 chains of 8 DSP48 blocks, 256 MAC per cycle,
// CSR slot 1 at 0xE8104100, DDR port MDNN, interrupt line J (PLIC 10).
`define SNPU_NPU1_N_CHAIN        16
`define SNPU_NPU1_CHAIN_LEN      8
`define SNPU_NPU1_P_MAX          512
`define SNPU_NPU1_P_W            9
`define SNPU_NPU1_IBUF_WORDS     8192
`define SNPU_NPU1_IBUF_AW        13
`define SNPU_NPU1_WFIFO_WORDS    1024
`define SNPU_NPU1_WFIFO_AW       10
`define SNPU_NPU1_OC_MAX         512
`define SNPU_NPU1_AXI_DW         128
`define SNPU_NPU1_WR_SLOT_WORDS  128
`define SNPU_NPU1_MP_MAX_W       128
`define SNPU_NPU1_MP_W_AW        7
`define SNPU_NPU1_GEOMETRY       32'h10090810

`endif
