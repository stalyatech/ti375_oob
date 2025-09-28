`define ETH_1000MBPS 1

module ti375_oob_top (
output		    jtagCtrl_tdi,
input		    jtagCtrl_tdo,
output		    jtagCtrl_enable,
output		    jtagCtrl_capture,
output		    jtagCtrl_shift,
output		    jtagCtrl_update,
output		    jtagCtrl_reset,
input		    ut_jtagCtrl_tdi,
output		    ut_jtagCtrl_tdo,
input		    ut_jtagCtrl_enable,
input		    ut_jtagCtrl_capture,
input		    ut_jtagCtrl_shift,
input		    ut_jtagCtrl_update,
input		    ut_jtagCtrl_reset,
input		    io_cfuClk,
input		    io_cfuReset,
input		    cpu0_customInstruction_cmd_valid,
output		    cpu0_customInstruction_cmd_ready,
input [9:0]     cpu0_customInstruction_function_id,
input [31:0]    cpu0_customInstruction_inputs_0,
input [31:0]    cpu0_customInstruction_inputs_1,
output		    cpu0_customInstruction_rsp_valid,
input		    cpu0_customInstruction_rsp_ready,
output [31:0]   cpu0_customInstruction_outputs_0,
input		    cpu1_customInstruction_cmd_valid,
output		    cpu1_customInstruction_cmd_ready,
input [9:0]     cpu1_customInstruction_function_id,
input [31:0]    cpu1_customInstruction_inputs_0,
input [31:0]    cpu1_customInstruction_inputs_1,
output		    cpu1_customInstruction_rsp_valid,
input		    cpu1_customInstruction_rsp_ready,
output [31:0]   cpu1_customInstruction_outputs_0,
input		    cpu2_customInstruction_cmd_valid,
output		    cpu2_customInstruction_cmd_ready,
input [9:0]     cpu2_customInstruction_function_id,
input [31:0]    cpu2_customInstruction_inputs_0,
input [31:0]    cpu2_customInstruction_inputs_1,
output		    cpu2_customInstruction_rsp_valid,
input		    cpu2_customInstruction_rsp_ready,
output [31:0]   cpu2_customInstruction_outputs_0,
input		    cpu3_customInstruction_cmd_valid,
output		    cpu3_customInstruction_cmd_ready,
input [9:0]     cpu3_customInstruction_function_id,
input [31:0]    cpu3_customInstruction_inputs_0,
input [31:0]    cpu3_customInstruction_inputs_1,
output		    cpu3_customInstruction_rsp_valid,
input		    cpu3_customInstruction_rsp_ready,
output [31:0]   cpu3_customInstruction_outputs_0,
output		    io_ddrMasters_0_aw_valid,
input		    io_ddrMasters_0_aw_ready,
output [31:0]   io_ddrMasters_0_aw_payload_addr,
output [3:0]    io_ddrMasters_0_aw_payload_id,
output [3:0]    io_ddrMasters_0_aw_payload_region,
output [7:0]    io_ddrMasters_0_aw_payload_len,
output [2:0]    io_ddrMasters_0_aw_payload_size,
output [1:0]    io_ddrMasters_0_aw_payload_burst,
output		    io_ddrMasters_0_aw_payload_lock,
output [3:0]    io_ddrMasters_0_aw_payload_cache,
output [3:0]    io_ddrMasters_0_aw_payload_qos,
output [2:0]    io_ddrMasters_0_aw_payload_prot,
output		    io_ddrMasters_0_aw_payload_allStrb,
output		    io_ddrMasters_0_w_valid,
input		    io_ddrMasters_0_w_ready,
output [127:0]  io_ddrMasters_0_w_payload_data,
output [15:0]   io_ddrMasters_0_w_payload_strb,
output		    io_ddrMasters_0_w_payload_last,
input		    io_ddrMasters_0_b_valid,
output		    io_ddrMasters_0_b_ready,
input [3:0]     io_ddrMasters_0_b_payload_id,
input [1:0]     io_ddrMasters_0_b_payload_resp,
output		    io_ddrMasters_0_ar_valid,
input		    io_ddrMasters_0_ar_ready,
output [31:0]   io_ddrMasters_0_ar_payload_addr,
output [3:0]    io_ddrMasters_0_ar_payload_id,
output [3:0]    io_ddrMasters_0_ar_payload_region,
output [7:0]    io_ddrMasters_0_ar_payload_len,
output [2:0]    io_ddrMasters_0_ar_payload_size,
output [1:0]    io_ddrMasters_0_ar_payload_burst,
output		    io_ddrMasters_0_ar_payload_lock,
output [3:0]    io_ddrMasters_0_ar_payload_cache,
output [3:0]    io_ddrMasters_0_ar_payload_qos,
output [2:0]    io_ddrMasters_0_ar_payload_prot,
input		    io_ddrMasters_0_r_valid,
output		    io_ddrMasters_0_r_ready,
input [127:0]   io_ddrMasters_0_r_payload_data,
input [3:0]     io_ddrMasters_0_r_payload_id,
input [1:0]     io_ddrMasters_0_r_payload_resp,
input		    io_ddrMasters_0_r_payload_last,
input		    io_ddrMasters_0_clk,
input		    io_ddrMasters_0_reset,
output          io_ddrMasters_memCheck_pass,
output		    userInterruptA,
output		    userInterruptB,
output		    userInterruptC,
output		    userInterruptD,
output		    userInterruptE,
output		    userInterruptF,
output		    userInterruptH,
output		    userInterruptG,
output			userInterruptI,
output			userInterruptJ,
output			userInterruptK,
output			userInterruptL,

input 			sys_jtag_io_tck,
input 			sys_jtag_io_tms,
input 			sys_jtag_io_tdi	,
output 			sys_jtag_io_tdo,

input [3:0]     sys_gpio_0_io_read,
output [3:0]    sys_gpio_0_io_write,
output [3:0]    sys_gpio_0_io_writeEnable,

output		    sys_uart_0_io_txd,
input		    sys_uart_0_io_rxd,
output		    sys_uart_1_io_txd,
input		    sys_uart_1_io_rxd,
output		    sys_uart_2_io_txd,
input		    sys_uart_2_io_rxd,

output		    sys_spi_0_io_sclk_write,
output		    sys_spi_0_io_data_0_writeEnable,
input		    sys_spi_0_io_data_0_read,
output		    sys_spi_0_io_data_0_write,
output		    sys_spi_0_io_data_1_writeEnable,
input		    sys_spi_0_io_data_1_read,
output		    sys_spi_0_io_data_1_write,
output		    sys_spi_0_io_data_2_writeEnable,
input		    sys_spi_0_io_data_2_read,
output		    sys_spi_0_io_data_2_write,
output		    sys_spi_0_io_data_3_writeEnable,
input		    sys_spi_0_io_data_3_read,
output		    sys_spi_0_io_data_3_write,
output [3:0]    sys_spi_0_io_ss,

output		    sys_spi_1_io_sclk_write,
output		    sys_spi_1_io_data_0_writeEnable,
input		    sys_spi_1_io_data_0_read,
output		    sys_spi_1_io_data_0_write,
output		    sys_spi_1_io_data_1_writeEnable,
input		    sys_spi_1_io_data_1_read,
output		    sys_spi_1_io_data_1_write,
output		    sys_spi_1_io_data_2_writeEnable,
input		    sys_spi_1_io_data_2_read,
output		    sys_spi_1_io_data_2_write,
output		    sys_spi_1_io_data_3_writeEnable,
input		    sys_spi_1_io_data_3_read,
output		    sys_spi_1_io_data_3_write,
output [3:0]    sys_spi_1_io_ss,

output		    sys_spi_2_io_sclk_write,
output		    sys_spi_2_io_data_0_writeEnable,
input		    sys_spi_2_io_data_0_read,
output		    sys_spi_2_io_data_0_write,
output		    sys_spi_2_io_data_1_writeEnable,
input		    sys_spi_2_io_data_1_read,
output		    sys_spi_2_io_data_1_write,
output		    sys_spi_2_io_data_2_writeEnable,
input		    sys_spi_2_io_data_2_read,
output		    sys_spi_2_io_data_2_write,
output		    sys_spi_2_io_data_3_writeEnable,
input		    sys_spi_2_io_data_3_read,
output		    sys_spi_2_io_data_3_write,
output [3:0]    sys_spi_2_io_ss,

output		    sys_i2c_0_io_sda_writeEnable,
output		    sys_i2c_0_io_sda_write,
input		    sys_i2c_0_io_sda_read,
output		    sys_i2c_0_io_scl_writeEnable,
output		    sys_i2c_0_io_scl_write,
input		    sys_i2c_0_io_scl_read,

output		    sys_i2c_1_io_sda_writeEnable,
output		    sys_i2c_1_io_sda_write,
input		    sys_i2c_1_io_sda_read,
output		    sys_i2c_1_io_scl_writeEnable,
output		    sys_i2c_1_io_scl_write,
input		    sys_i2c_1_io_scl_read,

output		    sys_i2c_2_io_sda_writeEnable,
output		    sys_i2c_2_io_sda_write,
input		    sys_i2c_2_io_sda_read,
output		    sys_i2c_2_io_scl_writeEnable,
output		    sys_i2c_2_io_scl_write,
input		    sys_i2c_2_io_scl_read,

input [31:0]    axiA_awaddr,
input [7:0]	    axiA_awlen,
input [2:0]	    axiA_awsize,
input [1:0]	    axiA_awburst,
input		    axiA_awlock,
input [3:0]	    axiA_awcache,
input [2:0]	    axiA_awprot,
input [3:0]	    axiA_awqos,
input [3:0]	    axiA_awregion,
input		    axiA_awvalid,
output		    axiA_awready,
input [31:0]    axiA_wdata,
input [3:0]     axiA_wstrb,
input		    axiA_wvalid,
input		    axiA_wlast,
output		    axiA_wready,
output [1:0]    axiA_bresp,
output		    axiA_bvalid,
input		    axiA_bready,
input [31:0]    axiA_araddr,
input [7:0]	    axiA_arlen,
input [2:0]	    axiA_arsize,
input [1:0]	    axiA_arburst,
input		    axiA_arlock,
input [3:0]	    axiA_arcache,
input [2:0]	    axiA_arprot,
input [3:0]	    axiA_arqos,
input [3:0]	    axiA_arregion,
input		    axiA_arvalid,
output		    axiA_arready,
output [31:0]   axiA_rdata,
output [1:0]    axiA_rresp,
output		    axiA_rlast,
output		    axiA_rvalid,
input		    axiA_rready,
output          axiAInterrupt,
input           cfg_done,
output          cfg_start,
output          cfg_sel,
output          cfg_reset,
input		    io_peripheralClk,
input           io_peripheralReset,
output          io_asyncReset,
input           io_gpio_sw_n, 
input           pll_peripheral_locked,
input           pll_system_locked,
input           pll_tse_locked,
//  SDHC
input           sd_base_clk, 
output          sd_clk_hi,
output          sd_clk_lo,
input           sd_cmd_i,
output          sd_cmd_o,
output          sd_cmd_oe,
input  [3:0]    sd_dat_i,
output [3:0]    sd_dat_o,
output [3:0]    sd_dat_oe,
input           sd_cd_n, 
input           sd_wp,
// TSEMAC
input           io_tseClk,
// MAC 
output [3:0]    rgmii_txd_HI,
output [3:0]    rgmii_txd_LO,
output          rgmii_tx_ctl_HI,
output          rgmii_tx_ctl_LO,
output          rgmii_txc_HI,
output          rgmii_txc_LO,
input  [3:0]    rgmii_rxd_HI,
input  [3:0]    rgmii_rxd_LO,
input           rgmii_rx_ctl_HI,
input           rgmii_rx_ctl_LO,
input           mux_clk,
output [1:0]    mux_clk_sw,
// PHY
output          phy_rst,
input           phy_mdi,
output          phy_mdo,
output          phy_mdo_en,
output          phy_mdc,
input           rgmii_rxc,      
input           rgmii_rxc_slow

);
////////////////////////////////////////////////////////////////////////////
localparam PERI_FREQ = 200;
localparam AXIS_DEV  = 3;
localparam AXIM_DEV  = 3;
localparam SLB  = 0;
//  SDHC
localparam SDHC  = 1;
localparam MSDHC = 0;
// TSEMAC
localparam TSE  = 2;
localparam MTSE = 1;
// MFCU
localparam MFCU	= 2;

////////////////////////////////////////////////////////////////////////////
//  Switch between sdhc, tsemac and slb
wire [(AXIS_DEV*32)-1:0]    gAXIS_m_awaddr;
wire [(AXIS_DEV*8)-1:0]	    gAXIS_m_awlen;
wire [(AXIS_DEV*3)-1:0]	    gAXIS_m_awsize;
wire [(AXIS_DEV*2)-1:0]     gAXIS_m_awburst;
wire [(AXIS_DEV*2)-1:0]     gAXIS_m_awlock;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_awcache;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_awprot;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_awqos;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_awregion;
wire [AXIS_DEV-1:0]         gAXIS_m_awvalid;
wire [AXIS_DEV-1:0]         gAXIS_m_awready;
wire [(AXIS_DEV*32)-1:0]    gAXIS_m_wdata;
wire [(AXIS_DEV*4)-1:0]     gAXIS_m_wstrb;
wire [AXIS_DEV-1:0]         gAXIS_m_wvalid;
wire [AXIS_DEV-1:0]         gAXIS_m_wlast;
wire [AXIS_DEV-1:0]         gAXIS_m_wready;
wire [(AXIS_DEV*2)-1:0]     gAXIS_m_bresp;
wire [AXIS_DEV-1:0]         gAXIS_m_bvalid;
wire [AXIS_DEV-1:0]         gAXIS_m_bready;
wire [(AXIS_DEV*32)-1:0]    gAXIS_m_araddr;
wire [(AXIS_DEV*8)-1:0]	    gAXIS_m_arlen;
wire [(AXIS_DEV*3)-1:0]	    gAXIS_m_arsize;
wire [(AXIS_DEV*2)-1:0]	    gAXIS_m_arburst;
wire [(AXIS_DEV*2)-1:0]     gAXIS_m_arlock;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_arcache;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_arprot;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_arqos;
wire [(AXIS_DEV*4)-1:0]	    gAXIS_m_arregion;
wire [AXIS_DEV-1:0]         gAXIS_m_arvalid;
wire [AXIS_DEV-1:0]         gAXIS_m_arready;
wire [(AXIS_DEV*32)-1:0]    gAXIS_m_rdata;
wire [(AXIS_DEV*2)-1:0]     gAXIS_m_rresp;
wire [AXIS_DEV-1:0]         gAXIS_m_rlast;
wire [AXIS_DEV-1:0]         gAXIS_m_rvalid;
wire [AXIS_DEV-1:0]         gAXIS_m_rready;
// Switch between sdhc, tsemac and fcu (flight controller unit)
wire [(AXIM_DEV*32)-1:0]    gAXIM_s_awaddr;
wire [(AXIM_DEV*8)-1:0]	    gAXIM_s_awlen;
wire [(AXIM_DEV*3)-1:0]	    gAXIM_s_awsize;
wire [(AXIM_DEV*2)-1:0]     gAXIM_s_awburst;
wire [(AXIM_DEV*2)-1:0]     gAXIM_s_awlock;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_awcache;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_awprot;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_awqos;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_awregion;
wire [AXIM_DEV-1:0]         gAXIM_s_awvalid;
wire [AXIM_DEV-1:0]         gAXIM_s_awready;
wire [(AXIM_DEV*128)-1:0]   gAXIM_s_wdata;
wire [(AXIM_DEV*16)-1:0]    gAXIM_s_wstrb;
wire [AXIM_DEV-1:0]         gAXIM_s_wvalid;
wire [AXIM_DEV-1:0]         gAXIM_s_wlast;
wire [AXIM_DEV-1:0]         gAXIM_s_wready;
wire [(AXIM_DEV*2)-1:0]     gAXIM_s_bresp;
wire [AXIM_DEV-1:0]         gAXIM_s_bvalid;
wire [AXIM_DEV-1:0]         gAXIM_s_bready;
wire [(AXIM_DEV*32)-1:0]    gAXIM_s_araddr;
wire [(AXIM_DEV*8)-1:0]	    gAXIM_s_arlen;
wire [(AXIM_DEV*3)-1:0]	    gAXIM_s_arsize;
wire [(AXIM_DEV*2)-1:0]	    gAXIM_s_arburst;
wire [(AXIM_DEV*2)-1:0]     gAXIM_s_arlock;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_arcache;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_arprot;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_arqos;
wire [(AXIM_DEV*4)-1:0]	    gAXIM_s_arregion;
wire [AXIM_DEV-1:0]         gAXIM_s_arvalid;
wire [AXIM_DEV-1:0]         gAXIM_s_arready;
wire [(AXIM_DEV*128)-1:0]   gAXIM_s_rdata;
wire [(AXIM_DEV*2)-1:0]     gAXIM_s_rresp;
wire [AXIM_DEV-1:0]         gAXIM_s_rlast;
wire [AXIM_DEV-1:0]         gAXIM_s_rvalid;
wire [AXIM_DEV-1:0]         gAXIM_s_rready;
// SDHC
wire                        sd_rst;
wire                        sd_int;
wire                        sd_dat_oe_i;
// DMA
wire                        dma_tx_rst;
wire                        dma_rx_rst;
wire                        dma_tx_descriptorUpdate;
wire [1:0]                  dma_interrupts;
wire [31:0]                 dma_apb3_paddr;
wire                        dma_apb3_psel;
wire                        dma_apb3_penable;
wire                        dma_apb3_pready;
wire                        dma_apb3_pwrite;
wire [31:0]                 dma_apb3_pwdata;
wire [31:0]                 dma_apb3_prdata;
wire                        dma_apb3_pslverror;
// TSE
wire                        tse_pll_ok;       
wire                        phy_sw_rst;   
wire                        mac_ext_rst;
wire [2:0]                  eth_speed;
wire                        s_eth_tx_tvalid;
wire                        s_eth_tx_tready;
wire [7:0]                  s_eth_tx_tdata;
wire [0:0]                  s_eth_tx_tkeep;
wire [3:0]                  s_eth_tx_tdest;
wire                        s_eth_tx_tlast;
wire                        m_eth_rx_tvalid;
wire                        m_eth_rx_tready;
wire [7:0]                  m_eth_rx_tdata;
wire [0:0]                  m_eth_rx_tkeep;
wire [3:0]                  m_eth_rx_tdest;
wire                        m_eth_rx_tlast;

gAXIS_1to3_switch u_AXIS_1to3_switch
(
    .rst_n              ( ~io_peripheralReset ),
    .clk                ( io_peripheralClk ),
    .m_axi_awvalid      ( gAXIS_m_awvalid ),
    .m_axi_awready      ( gAXIS_m_awready ),
    .m_axi_awid         ( ),
    .m_axi_awaddr       ( gAXIS_m_awaddr ),
    .m_axi_awburst      ( gAXIS_m_awburst ),
    .m_axi_awlen        ( gAXIS_m_awlen ),
    .m_axi_awsize       ( gAXIS_m_awsize ),
    .m_axi_awcache      ( gAXIS_m_awcache ),
    .m_axi_awqos        ( gAXIS_m_awqos ),
    .m_axi_awprot       ( gAXIS_m_awprot ),
    .m_axi_awuser       ( ),
    .m_axi_awlock       ( gAXIS_m_awlock ),
    .m_axi_awregion     ( gAXIS_m_awregion ),
    .m_axi_wvalid       ( gAXIS_m_wvalid ),
    .m_axi_wready       ( gAXIS_m_wready ),
    .m_axi_wdata        ( gAXIS_m_wdata ),
    .m_axi_wstrb        ( gAXIS_m_wstrb ),
    .m_axi_wlast        ( gAXIS_m_wlast ),
    .m_axi_wuser        ( ),
    .m_axi_bready       ( gAXIS_m_bready ),
    .m_axi_bvalid       ( gAXIS_m_bvalid ),
    .m_axi_bresp        ( gAXIS_m_bresp ),
    .m_axi_buser        ( {AXIS_DEV{3'h0}} ),
    .m_axi_bid          ( {AXIS_DEV{8'h0}} ),
    .m_axi_arvalid      ( gAXIS_m_arvalid ),
    .m_axi_arready      ( gAXIS_m_arready ),
    .m_axi_arid         ( ),
    .m_axi_araddr       ( gAXIS_m_araddr ),
    .m_axi_arburst      ( gAXIS_m_arburst ),
    .m_axi_arlen        ( gAXIS_m_arlen ),
    .m_axi_arsize       ( gAXIS_m_arsize ),
    .m_axi_arlock       ( gAXIS_m_arlock ),
    .m_axi_arprot       ( gAXIS_m_arprot ),
    .m_axi_arcache      ( gAXIS_m_arcache ),
    .m_axi_arqos        ( gAXIS_m_arqos ),
    .m_axi_aruser       ( ),
    .m_axi_arregion     ( gAXIS_m_arregion ),
    .m_axi_ruser        ( {AXIS_DEV{3'h0}}),
    .m_axi_rvalid       ( gAXIS_m_rvalid ),
    .m_axi_rready       ( gAXIS_m_rready ),
    .m_axi_rid          ( {AXIS_DEV{8'h0}}),
    .m_axi_rdata        ( gAXIS_m_rdata ),
    .m_axi_rresp        ( gAXIS_m_rresp ),
    .m_axi_rlast        ( gAXIS_m_rlast ),
    .s_axi_awvalid      ( axiA_awvalid ),
    .s_axi_awready      ( axiA_awready ),
    .s_axi_awaddr       ( {7'h00, axiA_awaddr[24:0]} ),
    .s_axi_awid         ( 8'h00 ),
    .s_axi_awburst      ( axiA_awburst ),
    .s_axi_awlen        ( axiA_awlen ),
    .s_axi_awsize       ( axiA_awsize ),
    .s_axi_awprot       ( {1'b0, axiA_awprot} ),
    .s_axi_awlock       ( {1'b0, axiA_awlock} ),
    .s_axi_awcache      ( axiA_awcache ),
    .s_axi_awqos        ( axiA_awqos ),
    .s_axi_awuser       ( 3'h0 ),
    .s_axi_wvalid       ( axiA_wvalid ),
    .s_axi_wready       ( axiA_wready ),
    .s_axi_wid          ( 8'h00 ),
    .s_axi_wdata        ( axiA_wdata ),
    .s_axi_wlast        ( axiA_wlast ),
    .s_axi_wstrb        ( axiA_wstrb ),
    .s_axi_wuser        ( 3'h0 ),
    .s_axi_bvalid       ( axiA_bvalid ),
    .s_axi_bready       ( axiA_bready ),
    .s_axi_bresp        ( axiA_bresp ),
    .s_axi_bid          ( ),
    .s_axi_buser        ( ),
    .s_axi_arvalid      ( axiA_arvalid ),
    .s_axi_arready      ( axiA_arready ),
    .s_axi_araddr       ( {7'h00, axiA_araddr[24:0]} ),
    .s_axi_arid         ( 8'h00 ),
    .s_axi_arburst      ( axiA_arburst ),
    .s_axi_arlen        ( axiA_arlen ),
    .s_axi_arsize       ( axiA_arsize ),
    .s_axi_arprot       ( { 1'b0, axiA_arprot} ),
    .s_axi_arlock       ( { 1'b0, axiA_arlock} ),
    .s_axi_arcache      ( axiA_arcache ),
    .s_axi_arqos        ( axiA_arqos ),
    .s_axi_aruser       ( 3'h0 ),
    .s_axi_rready       ( axiA_rready ),
    .s_axi_rvalid       ( axiA_rvalid ),
    .s_axi_rdata        ( axiA_rdata ),
    .s_axi_rresp        ( axiA_rresp ),
    .s_axi_rlast        ( axiA_rlast ),
    .s_axi_rid          ( ),
    .s_axi_ruser        ( )
);

gAXIM_3to1_switch u_AXIM_3to1_switch
(
    .rst_n              ( ~io_ddrMasters_0_reset ),
    .clk                ( io_ddrMasters_0_clk ),
    .m_axi_awvalid      ( io_ddrMasters_0_aw_valid ),
    .m_axi_awready      ( io_ddrMasters_0_aw_ready ),
    .m_axi_awid         ( io_ddrMasters_0_aw_payload_id ),
    .m_axi_awaddr       ( io_ddrMasters_0_aw_payload_addr ),
    .m_axi_awburst      ( io_ddrMasters_0_aw_payload_burst ),
    .m_axi_awlen        ( io_ddrMasters_0_aw_payload_len ),
    .m_axi_awsize       ( io_ddrMasters_0_aw_payload_size ),
    .m_axi_awcache      ( io_ddrMasters_0_aw_payload_cache ),
    .m_axi_awqos        ( io_ddrMasters_0_aw_payload_qos ),
    .m_axi_awprot       ( io_ddrMasters_0_aw_payload_prot ),
    .m_axi_awuser       ( ),
    .m_axi_awlock       ( io_ddrMasters_0_aw_payload_lock ),
    .m_axi_awregion     ( io_ddrMasters_0_aw_payload_region ),
    .m_axi_wvalid       ( io_ddrMasters_0_w_valid ),
    .m_axi_wready       ( io_ddrMasters_0_w_ready ),
    .m_axi_wdata        ( io_ddrMasters_0_w_payload_data ),
    .m_axi_wstrb        ( io_ddrMasters_0_w_payload_strb ),
    .m_axi_wlast        ( io_ddrMasters_0_w_payload_last ),
    .m_axi_wuser        ( ),
    .m_axi_bready       ( io_ddrMasters_0_b_ready ),
    .m_axi_bvalid       ( io_ddrMasters_0_b_valid ),
    .m_axi_bresp        ( io_ddrMasters_0_b_payload_resp ),
    .m_axi_buser        ( 3'h0 ),
    .m_axi_bid          ( {4'h0, io_ddrMasters_0_b_payload_id} ),
    .m_axi_arvalid      ( io_ddrMasters_0_ar_valid ),
    .m_axi_arready      ( io_ddrMasters_0_ar_ready ),
    .m_axi_arid         ( io_ddrMasters_0_ar_payload_id ),
    .m_axi_araddr       ( io_ddrMasters_0_ar_payload_addr ),
    .m_axi_arburst      ( io_ddrMasters_0_ar_payload_burst ),
    .m_axi_arlen        ( io_ddrMasters_0_ar_payload_len ),
    .m_axi_arsize       ( io_ddrMasters_0_ar_payload_size ),
    .m_axi_arlock       ( io_ddrMasters_0_ar_payload_lock ),
    .m_axi_arprot       ( io_ddrMasters_0_ar_payload_prot ),
    .m_axi_arcache      ( io_ddrMasters_0_ar_payload_cache ),
    .m_axi_arqos        ( io_ddrMasters_0_ar_payload_qos ),
    .m_axi_aruser       ( ),
    .m_axi_arregion     ( io_ddrMasters_0_ar_payload_region ),
    .m_axi_ruser        ( 3'h0),
    .m_axi_rvalid       ( io_ddrMasters_0_r_valid ),
    .m_axi_rready       ( io_ddrMasters_0_r_ready ),
    .m_axi_rid          ( 8'h0 ),
    .m_axi_rdata        ( io_ddrMasters_0_r_payload_data ),
    .m_axi_rresp        ( io_ddrMasters_0_r_payload_resp ),
    .m_axi_rlast        ( io_ddrMasters_0_r_payload_last ),
    .s_axi_awvalid      ( gAXIM_s_awvalid ),
    .s_axi_awready      ( gAXIM_s_awready ),
    .s_axi_awaddr       ( gAXIM_s_awaddr ),
    .s_axi_awid         ( {AXIM_DEV{8'h00}} ),
    .s_axi_awburst      ( gAXIM_s_awburst ),
    .s_axi_awlen        ( gAXIM_s_awlen ),
    .s_axi_awsize       ( gAXIM_s_awsize ),
    .s_axi_awprot       ( gAXIM_s_awprot ),
    .s_axi_awlock       ( gAXIM_s_awlock ),
    .s_axi_awcache      ( gAXIM_s_awcache ),
    .s_axi_awqos        ( gAXIM_s_awqos ),
    .s_axi_awuser       ( {AXIM_DEV{3'h0}} ),
    .s_axi_wvalid       ( gAXIM_s_wvalid ),
    .s_axi_wready       ( gAXIM_s_wready ),
    .s_axi_wid          ( {AXIM_DEV{8'h00}} ),
    .s_axi_wdata        ( gAXIM_s_wdata ),
    .s_axi_wlast        ( gAXIM_s_wlast ),
    .s_axi_wstrb        ( gAXIM_s_wstrb ),
    .s_axi_wuser        ( {AXIM_DEV{3'h0}} ),
    .s_axi_bvalid       ( gAXIM_s_bvalid ),
    .s_axi_bready       ( gAXIM_s_bready ),
    .s_axi_bresp        ( gAXIM_s_bresp ),
    .s_axi_bid          ( ),
    .s_axi_buser        ( ),
    .s_axi_arvalid      ( gAXIM_s_arvalid ),
    .s_axi_arready      ( gAXIM_s_arready ),
    .s_axi_araddr       ( gAXIM_s_araddr ),
    .s_axi_arid         ( {AXIM_DEV{8'h00}} ),
    .s_axi_arburst      ( gAXIM_s_arburst ),
    .s_axi_arlen        ( gAXIM_s_arlen ),
    .s_axi_arsize       ( gAXIM_s_arsize ),
    .s_axi_arprot       ( gAXIM_s_axiA_arprot ),
    .s_axi_arlock       ( gAXIM_s_axiA_arlock ),
    .s_axi_arcache      ( gAXIM_s_arcache ),
    .s_axi_arqos        ( gAXIM_s_arqos ),
    .s_axi_aruser       ( {AXIM_DEV{3'h0}} ),
    .s_axi_rready       ( gAXIM_s_rready ),
    .s_axi_rvalid       ( gAXIM_s_rvalid ),
    .s_axi_rdata        ( gAXIM_s_rdata ),
    .s_axi_rresp        ( gAXIM_s_rresp ),
    .s_axi_rlast        ( gAXIM_s_rlast ),
    .s_axi_rid          ( ),
    .s_axi_ruser        ( )
);

assign sd_rst                       = io_peripheralReset;
assign gAXIS_m_rlast[SDHC*1 +: 1]   = 1'b1;
assign sd_dat_oe                    = {4{sd_dat_oe_i}};
assign userInterruptF               = sd_int;

gSDHC u_gSDHC
(
    .sd_rst             ( sd_rst ),
    .sd_base_clk        ( sd_base_clk ),
    .sd_int             ( sd_int ),
    .sd_cd_n            ( sd_cd_n ),
    .sd_wp              ( sd_wp ),
    .s_axi_aclk         ( io_peripheralClk ),
    .s_axi_awaddr       ( gAXIS_m_awaddr[SDHC*32 +: 32] ),
    .s_axi_awready      ( gAXIS_m_awready[SDHC*1 +: 1] ),
    .s_axi_awvalid      ( gAXIS_m_awvalid[SDHC*1 +: 1] ),
    .s_axi_wstrb        ( gAXIS_m_wstrb[SDHC*4 +: 4]),
    .s_axi_wdata        ( gAXIS_m_wdata[SDHC*32 +: 32] ),
    .s_axi_wready       ( gAXIS_m_wready[SDHC*1 +: 1] ),
    .s_axi_wvalid       ( gAXIS_m_wvalid[SDHC*1 +: 1] ),
    .s_axi_bresp        ( gAXIS_m_bresp[SDHC*2 +: 2] ),
    .s_axi_bvalid       ( gAXIS_m_bvalid[SDHC*1 +: 1] ),
    .s_axi_araddr       ( gAXIS_m_araddr[SDHC*32 +: 32] ),
    .s_axi_bready       ( gAXIS_m_bready[SDHC*1 +: 1] ),
    .s_axi_arready      ( gAXIS_m_arready[SDHC*1 +: 1] ),
    .s_axi_arvalid      ( gAXIS_m_arvalid[SDHC*1 +: 1] ),
    .s_axi_rresp        ( gAXIS_m_rresp[SDHC*2 +: 2] ),
    .s_axi_rdata        ( gAXIS_m_rdata[SDHC*32 +: 32]),
    .s_axi_rvalid       ( gAXIS_m_rvalid[SDHC*1 +: 1] ),
    .s_axi_rready       ( gAXIS_m_rready[SDHC*1 +: 1] ),
    .m_axi_clk          ( io_ddrMasters_0_clk ),
    .m_axi_awaddr       ( gAXIM_s_awaddr[MSDHC*32 +: 32] ),
    .m_axi_awvalid      ( gAXIM_s_awvalid[MSDHC*1 +: 1] ),
    .m_axi_awlen        ( gAXIM_s_awlen[MSDHC*8 +: 8] ),
    .m_axi_awready      ( gAXIM_s_awready[MSDHC*1 +: 1] ),
    .m_axi_awburst      ( gAXIM_s_awburst[MSDHC*2 +: 2] ),
    .m_axi_awsize       ( gAXIM_s_awsize[MSDHC*3 +: 3] ),
    .m_axi_awcache      ( gAXIM_s_awcache[MSDHC*4 +: 4] ),
    .m_axi_awlock       ( gAXIM_s_awlock[MSDHC*2 +: 2] ),
    .m_axi_awprot       ( gAXIM_s_awprot[MSDHC*4 +: 4] ),
    .m_axi_wdata        ( gAXIM_s_wdata[MSDHC*128 +: 128] ),
    .m_axi_wstrb        ( gAXIM_s_wstrb[MSDHC*16 +: 16] ),
    .m_axi_wlast        ( gAXIM_s_wlast[MSDHC*1 +: 1] ),
    .m_axi_wvalid       ( gAXIM_s_wvalid[MSDHC*1 +: 1] ),
    .m_axi_wready       ( gAXIM_s_wready[MSDHC*1 +:1] ),
    .m_axi_bresp        ( gAXIM_s_bresp[MSDHC*2 +: 2] ),
    .m_axi_bvalid       ( gAXIM_s_bvalid[MSDHC*1 +: 1] ),
    .m_axi_bready       ( gAXIM_s_bready[MSDHC*1 +: 1] ),
    .m_axi_arvalid      ( gAXIM_s_arvalid[MSDHC*1 +: 1] ),
    .m_axi_araddr       ( gAXIM_s_araddr[MSDHC*32 +: 32] ),
    .m_axi_arlen        ( gAXIM_s_arlen[MSDHC*8 +: 8] ),
    .m_axi_arsize       ( gAXIM_s_arsize[MSDHC*3 +: 3] ),
    .m_axi_arburst      ( gAXIM_s_arburst[MSDHC*2 +: 2] ),
    .m_axi_arprot       ( gAXIM_s_arprot[MSDHC*4 +: 4] ),
    .m_axi_arlock       ( gAXIM_s_arlock[MSDHC*2 +: 2] ),
    .m_axi_arcache      ( gAXIM_s_arcache[MSDHC*4 +: 4] ),
    .m_axi_arready      ( gAXIM_s_arready[MHSDC*1 +: 1] ),
    .m_axi_rvalid       ( gAXIM_s_rvalid[MSDHC*1 +: 1] ),
    .m_axi_rdata        ( gAXIM_s_rdata[MSDHC*128 +: 128] ),
    .m_axi_rlast        ( gAXIM_s_rlast[MSDHC*1 +: 1] ),
    .m_axi_rresp        ( gAXIM_s_rresp[MSDHC*2 +: 2] ),
    .m_axi_rready       ( gAXIM_s_rready[MSDHC*1 +: 1] ),
    .sd_clk_hi          ( sd_clk_hi ),
    .sd_clk_lo          ( sd_clk_lo ),
    .sd_cmd_i           ( sd_cmd_i ),
    .sd_cmd_o           ( sd_cmd_o ),
    .sd_cmd_oe          ( sd_cmd_oe ),
    .sd_dat_i           ( sd_dat_i ),
    .sd_dat_o           ( sd_dat_o ),
    .sd_dat_oe          ( sd_dat_oe_i )
);

assign m_eth_rx_tdest = 4'h0;
assign phy_rst = phy_sw_rst;
assign tse_pll_ok = pll_tse_locked & pll_peripheral_locked;

tseCore u_tseCore (
    .io_peripheralClk        ( io_peripheralClk ),
    .io_peripheralReset      ( io_peripheralReset ),
    .io_tseClk               ( io_tseClk ),
    .pll_locked              ( tse_pll_ok ),
    .phy_sw_rst              ( phy_sw_rst ),
    .mac_ext_rst             ( mac_ext_rst ),
    .dma_rx_rst              ( dma_rx_rst ),
    .dma_tx_rst              ( dma_tx_rst ),
    .dma_tx_descriptorUpdate ( dma_tx_descriptorUpdate ),
    .dma_interrupts          ( dma_interrupts ),
    .eth_speed               ( eth_speed ),
    .rgmii_txd_HI            ( rgmii_txd_HI ),
    .rgmii_txd_LO            ( rgmii_txd_LO ),
    .rgmii_tx_ctl_HI         ( rgmii_tx_ctl_HI ),
    .rgmii_tx_ctl_LO         ( rgmii_tx_ctl_LO ),
    .rgmii_txc_HI            ( rgmii_txc_HI ),
    .rgmii_txc_LO            ( rgmii_txc_LO ),
    .rgmii_rxd_HI            ( rgmii_rxd_HI ),
    .rgmii_rxd_LO            ( rgmii_rxd_LO ),
    .rgmii_rx_ctl_HI         ( rgmii_rx_ctl_HI ),
    .rgmii_rx_ctl_LO         ( rgmii_rx_ctl_LO ),
`ifdef ETH_1000MBPS
    .rgmii_rxc               ( rgmii_rxc ),
`else
    .rgmii_rxc               ( rgmii_rxc_slow ), 
`endif
    .phy_mdi                 ( phy_mdi ),
    .phy_mdo                 ( phy_mdo ),
    .phy_mdo_en              ( phy_mdo_en ),
    .phy_mdc                 ( phy_mdc ), 
    .s_axi_awaddr            ( gAXIS_m_awaddr[TSE*32 +: 32] ),   
    .s_axi_awvalid           ( gAXIS_m_awvalid[TSE*1 +: 1] ),  
    .s_axi_awready           ( gAXIS_m_awready[TSE*1 +: 1] ),  
    .s_axi_wdata             ( gAXIS_m_wdata[TSE*32 +: 32] ),    
    .s_axi_wstrb             ( gAXIS_m_wstrb[TSE*4 +: 4] ),
    .s_axi_wlast             ( gAXIS_m_wlast[TSE*1 +: 1] ),
    .s_axi_wvalid            ( gAXIS_m_wvalid[TSE*1 +: 1] ),   
    .s_axi_wready            ( gAXIS_m_wready[TSE*1 +: 1] ),   
    .s_axi_bresp             ( gAXIS_m_bresp[TSE*2 +: 2] ),    
    .s_axi_bvalid            ( gAXIS_m_bvalid[TSE*1 +: 1] ),   
    .s_axi_bready            ( gAXIS_m_bready[TSE*1 +: 1] ),   
    .s_axi_araddr            ( gAXIS_m_araddr[TSE*32 +: 32] ),   
    .s_axi_arvalid           ( gAXIS_m_arvalid[TSE*1 +: 1] ),  
    .s_axi_arready           ( gAXIS_m_arready[TSE*1 +: 1] ),  
    .s_axi_rresp             ( gAXIS_m_rresp[TSE*2 +: 2] ),    
    .s_axi_rdata             ( gAXIS_m_rdata[TSE*32 +: 32] ),    
    .s_axi_rlast             ( gAXIS_m_rlast[TSE*1 +: 1] ),
    .s_axi_rvalid            ( gAXIS_m_rvalid[TSE*1 +: 1] ),   
    .s_axi_rready            ( gAXIS_m_rready[TSE*1 +: 1] ),
    .s_eth_tx_tvalid         ( s_eth_tx_tvalid ),
    .s_eth_tx_tready         ( s_eth_tx_tready ),
    .s_eth_tx_tdata          ( s_eth_tx_tdata  ),
    .s_eth_tx_tkeep          ( s_eth_tx_tkeep  ),
    .s_eth_tx_tdest          ( s_eth_tx_tdest  ),
    .s_eth_tx_tlast          ( s_eth_tx_tlast  ),
    .m_eth_rx_tvalid         ( m_eth_rx_tvalid ),
    .m_eth_rx_tready         ( m_eth_rx_tready ),
    .m_eth_rx_tdata          ( m_eth_rx_tdata  ),
    .m_eth_rx_tstrb          ( m_eth_rx_tstrb  ),
    .m_eth_rx_tlast          ( m_eth_rx_tlast  )
);

assign userInterruptG = dma_interrupts[0];
assign userInterruptH = dma_interrupts[1];

gDMA u_gDMA (
    .clk                     ( io_ddrMasters_0_clk ),
    .reset                   ( io_ddrMasters_0_reset ),
    .ctrl_clk                ( io_peripheralClk ),
    .ctrl_reset              ( io_peripheralReset ),
    .ctrl_PADDR              ( dma_apb3_paddr ),
    .ctrl_PREADY             ( dma_apb3_pready ),
    .ctrl_PENABLE            ( dma_apb3_penable ),
    .ctrl_PSEL               ( dma_apb3_psel ),
    .ctrl_PWRITE             ( dma_apb3_pwrite ),
    .ctrl_PWDATA             ( dma_apb3_pwdata ),
    .ctrl_PRDATA             ( dma_apb3_prdata ),
    .ctrl_PSLVERROR          ( dma_apb3_pslverror ),
    .ctrl_interrupts         ( dma_interrupts ),
    .read_arvalid            ( gAXIM_s_arvalid[MTSE*1 +: 1] ),
    .read_araddr             ( gAXIM_s_araddr[MTSE*32 +: 32] ),
    .read_arready            ( gAXIM_s_arready[MTSE*1 +: 1] ),
    .read_arregion           ( gAXIM_s_arregion[MTSE*4 +: 4] ),
    .read_arlen              ( gAXIM_s_arlen[MTSE*8 +: 8] ),
    .read_arsize             ( gAXIM_s_arsize[MTSE*3 +: 3] ),
    .read_arburst            ( gAXIM_s_arburst[MTSE*2 +: 2] ),
    .read_arlock             ( gAXIM_s_arlock[MTSE*2 +: 2] ),
    .read_arcache            ( gAXIM_s_arcache[MTSE*4 +: 4] ),
    .read_arqos              ( gAXIM_s_arqos[MTSE*4 +: 4] ),
    .read_arprot             ( gAXIM_s_arprot[MTSE*4 +: 4] ),
    .read_rready             ( gAXIM_s_rready[MTSE*1 +: 1] ),
    .read_rvalid             ( gAXIM_s_rvalid[MTSE*1 +: 1] ),
    .read_rdata              ( gAXIM_s_rdata[MTSE*128 +: 128] ),
    .read_rlast              ( gAXIM_s_rlast[MTSE*1 +: 1] ),
    .read_rresp              ( gAXIM_s_rresp[MTSE*2 +: 2] ),
    .write_awvalid           ( gAXIM_s_awvalid[MTSE*1 +: 1] ),
    .write_awready           ( gAXIM_s_awready[MTSE*1 +: 1] ),
    .write_awaddr            ( gAXIM_s_awaddr[MTSE*32 +: 32] ),
    .write_awregion          ( gAXIM_s_awregion[MTSE*4 +: 4] ),
    .write_awlen             ( gAXIM_s_awlen[MTSE*8 +: 8] ),
    .write_awsize            ( gAXIM_s_awsize[MTSE*3 +: 3] ),
    .write_awburst           ( gAXIM_s_awburst[MTSE*2 +: 2] ),
    .write_awlock            ( gAXIM_s_awlock[MTSE*2 +: 2] ),
    .write_awcache           ( gAXIM_s_awcache[MTSE*4 +: 4] ),
    .write_awqos             ( gAXIM_s_awqos[MTSE*4 +: 4] ),
    .write_awprot            ( gAXIM_s_awprot[MTSE*4 +: 4] ),
    .write_wvalid            ( gAXIM_s_wvalid[MTSE*1 +: 1] ),
    .write_wready            ( gAXIM_s_wready[MTSE*1 +: 1] ),
    .write_wdata             ( gAXIM_s_wdata[MTSE*128 +: 128] ),
    .write_wstrb             ( gAXIM_s_wstrb[MTSE*16 +: 16] ),
    .write_wlast             ( gAXIM_s_wlast[MTSE*1 +: 1] ),
    .write_bvalid            ( gAXIM_s_bvalid[MTSE*1 +: 1] ),
    .write_bready            ( gAXIM_s_bready[MTSE*1 +: 1] ),
    .write_bresp             ( gAXIM_s_bresp[MTSE*2 +: 2] ),
    .dat1_o_clk              ( io_tseClk ),
    .dat1_o_reset            ( mac_ext_rst | dma_tx_rst),
    .dat1_o_tvalid           ( s_eth_tx_tvalid ),
    .dat1_o_tready           ( s_eth_tx_tready ),
    .dat1_o_tdata            ( s_eth_tx_tdata ),
    .dat1_o_tkeep            ( s_eth_tx_tkeep ),
    .dat1_o_tdest            ( s_eth_tx_tdest ),
    .dat1_o_tlast            ( s_eth_tx_tlast ),
`ifdef ETH_1000MBPS
    .dat0_i_clk              ( rgmii_rxc ),
`else
    .dat0_i_clk              ( rgmii_rxc_slow ),
`endif
    .dat0_i_reset            ( mac_ext_rst | dma_rx_rst ),
    .dat0_i_tvalid           ( m_eth_rx_tvalid ),
    .dat0_i_tready           ( m_eth_rx_tready ),
    .dat0_i_tdata            ( m_eth_rx_tdata ),
    .dat0_i_tkeep            ( 1'b1),
    .dat0_i_tdest            ( m_eth_rx_tdest ),
    .dat0_i_tlast            ( m_eth_rx_tlast ),
    .io_1_descriptorUpdate   (  ),
    .io_0_descriptorUpdate   (dma_tx_descriptorUpdate)

);

////////////////////////////////////////////////////////////////////////////


custom_instruction_tea cpu0_custom_instruction_tea_inst(
	.clk(io_cfuClk),
	.reset(io_cfuReset),
	.cmd_valid(cpu0_customInstruction_cmd_valid),
	.cmd_ready(cpu0_customInstruction_cmd_ready),
	.cmd_function_id(cpu0_customInstruction_function_id),
	.cmd_inputs_0(cpu0_customInstruction_inputs_0),
	.cmd_inputs_1(cpu0_customInstruction_inputs_1),
	.rsp_valid(cpu0_customInstruction_rsp_valid),
	.rsp_ready(cpu0_customInstruction_rsp_ready),
	.rsp_outputs_0(cpu0_customInstruction_outputs_0)
);

custom_instruction_tea cpu1_custom_instruction_tea_inst(
	.clk(io_cfuClk),
	.reset(io_cfuReset),
	.cmd_valid(cpu1_customInstruction_cmd_valid),
	.cmd_ready(cpu1_customInstruction_cmd_ready),
	.cmd_function_id(cpu1_customInstruction_function_id),
	.cmd_inputs_0(cpu1_customInstruction_inputs_0),
	.cmd_inputs_1(cpu1_customInstruction_inputs_1),
	.rsp_valid(cpu1_customInstruction_rsp_valid),
	.rsp_ready(cpu1_customInstruction_rsp_ready),
	.rsp_outputs_0(cpu1_customInstruction_outputs_0)
);

custom_instruction_tea cpu2_custom_instruction_tea_inst(
	.clk(io_cfuClk),
	.reset(io_cfuReset),
	.cmd_valid(cpu2_customInstruction_cmd_valid),
	.cmd_ready(cpu2_customInstruction_cmd_ready),
	.cmd_function_id(cpu2_customInstruction_function_id),
	.cmd_inputs_0(cpu2_customInstruction_inputs_0),
	.cmd_inputs_1(cpu2_customInstruction_inputs_1),
	.rsp_valid(cpu2_customInstruction_rsp_valid),
	.rsp_ready(cpu2_customInstruction_rsp_ready),
	.rsp_outputs_0(cpu2_customInstruction_outputs_0)
);

custom_instruction_tea cpu3_custom_instruction_tea_inst(
	.clk(io_cfuClk),
	.reset(io_cfuReset),
	.cmd_valid(cpu3_customInstruction_cmd_valid),
	.cmd_ready(cpu3_customInstruction_cmd_ready),
	.cmd_function_id(cpu3_customInstruction_function_id),
	.cmd_inputs_0(cpu3_customInstruction_inputs_0),
	.cmd_inputs_1(cpu3_customInstruction_inputs_1),
	.rsp_valid(cpu3_customInstruction_rsp_valid),
	.rsp_ready(cpu3_customInstruction_rsp_ready),
	.rsp_outputs_0(cpu3_customInstruction_outputs_0)
);

//axi4 bridge to various I/O
EfxSapphireHpSoc_slb u_top_peripherals(
	.io_apbSlave_0_PADDR                    ( dma_apb3_paddr ),
	.io_apbSlave_0_PENABLE                  ( dma_apb3_penable ),
	.io_apbSlave_0_PRDATA                   ( dma_apb3_prdata ),
	.io_apbSlave_0_PREADY                   ( dma_apb3_pready ),
	.io_apbSlave_0_PSEL                     ( dma_apb3_psel ),
	.io_apbSlave_0_PSLVERROR                ( dma_apb3_pslverror ),
	.io_apbSlave_0_PWDATA                   ( dma_apb3_pwdata ),
	.io_apbSlave_0_PWRITE                   ( dma_apb3_pwrite ),

	.system_spi_0_io_sclk_write             (  ),
	.system_spi_0_io_data_0_writeEnable     (  ),
	.system_spi_0_io_data_0_read            (  ),
	.system_spi_0_io_data_0_write           (  ),
	.system_spi_0_io_data_1_writeEnable     (  ),
	.system_spi_0_io_data_1_read            (  ),
	.system_spi_0_io_data_1_write           (  ),
	.system_spi_0_io_data_2_writeEnable     (  ),
	.system_spi_0_io_data_2_read            (  ),
	.system_spi_0_io_data_2_write           (  ),
	.system_spi_0_io_data_3_writeEnable     (  ),
	.system_spi_0_io_data_3_read            (  ),
	.system_spi_0_io_data_3_write           (  ),
	.system_spi_0_io_ss                     (  ),

	.system_spi_1_io_sclk_write             (  ),
	.system_spi_1_io_data_0_writeEnable     (  ),
	.system_spi_1_io_data_0_read            (  ),
	.system_spi_1_io_data_0_write           (  ),
	.system_spi_1_io_data_1_writeEnable     (  ),
	.system_spi_1_io_data_1_read            (  ),
	.system_spi_1_io_data_1_write           (  ),
	.system_spi_1_io_data_2_writeEnable     (  ),
	.system_spi_1_io_data_2_read            (  ),
	.system_spi_1_io_data_2_write           (  ),
	.system_spi_1_io_data_3_writeEnable     (  ),
	.system_spi_1_io_data_3_read            (  ),
	.system_spi_1_io_data_3_write           (  ),
	.system_spi_1_io_ss                     (  ),

	.system_spi_2_io_sclk_write             (  ),
	.system_spi_2_io_data_0_writeEnable     (  ),
	.system_spi_2_io_data_0_read            (  ),
	.system_spi_2_io_data_0_write           (  ),
	.system_spi_2_io_data_1_writeEnable     (  ),
	.system_spi_2_io_data_1_read            (  ),
	.system_spi_2_io_data_1_write           (  ),
	.system_spi_2_io_data_2_writeEnable     (  ),
	.system_spi_2_io_data_2_read            (  ),
	.system_spi_2_io_data_2_write           (  ),
	.system_spi_2_io_data_3_writeEnable     (  ),
	.system_spi_2_io_data_3_read            (  ),
	.system_spi_2_io_data_3_write           (  ),
	.system_spi_2_io_ss                     (  ),

	.system_uart_0_io_txd                   (  ),
	.system_uart_0_io_rxd                   (  ),
	.system_uart_1_io_txd                   (  ),
	.system_uart_1_io_rxd                   (  ),
	.system_uart_2_io_txd                   (  ),
	.system_uart_2_io_rxd                   (  ),

	.system_i2c_0_io_sda_writeEnable        (  ),
	.system_i2c_0_io_sda_write              (  ),
	.system_i2c_0_io_sda_read               (  ),
	.system_i2c_0_io_scl_writeEnable        (  ),
	.system_i2c_0_io_scl_write              (  ),
	.system_i2c_0_io_scl_read               (  ),

	.system_i2c_1_io_sda_writeEnable        (  ),
	.system_i2c_1_io_sda_write              (  ),
	.system_i2c_1_io_sda_read               (  ),
	.system_i2c_1_io_scl_writeEnable        (  ),
	.system_i2c_1_io_scl_write              (  ),
	.system_i2c_1_io_scl_read               (  ),

	.system_i2c_2_io_sda_writeEnable        (  ),
	.system_i2c_2_io_sda_write              (  ),
	.system_i2c_2_io_sda_read               (  ),
	.system_i2c_2_io_scl_writeEnable        (  ),
	.system_i2c_2_io_scl_write              (  ),
	.system_i2c_2_io_scl_read               (  ),

	.system_gpio_0_io_read                  (  ),
	.system_gpio_0_io_write                 (  ),
	.system_gpio_0_io_writeEnable           (  ),

	.jtagCtrl_tdi                           ( jtagCtrl_tdi ),
	.jtagCtrl_tdo                           ( jtagCtrl_tdo ),
	.jtagCtrl_enable                        ( jtagCtrl_enable ),
	.jtagCtrl_capture                       ( jtagCtrl_capture ),
	.jtagCtrl_shift                         ( jtagCtrl_shift ),
	.jtagCtrl_update                        ( jtagCtrl_update ),
	.jtagCtrl_reset                         ( jtagCtrl_reset ),
	.ut_jtagCtrl_tdi                        ( ut_jtagCtrl_tdi ),
	.ut_jtagCtrl_tdo                        ( ut_jtagCtrl_tdo ),
	.ut_jtagCtrl_enable                     ( ut_jtagCtrl_enable ),
	.ut_jtagCtrl_capture                    ( ut_jtagCtrl_capture ),
	.ut_jtagCtrl_shift                      ( ut_jtagCtrl_shift ),
	.ut_jtagCtrl_update                     ( ut_jtagCtrl_update ),
	.ut_jtagCtrl_reset                      ( ut_jtagCtrl_reset ),

	.userInterruptA                         (  ),
	.userInterruptB                         (  ),
	.userInterruptC                         (  ),
	.userInterruptD                         (  ),
	.userInterruptE                         (  ),
	.userInterruptF 						(  ),
	.userInterruptG 						(  ),
	.userInterruptH 						(  ),
	.userInterruptI 						(  ),
	.userInterruptJ 						(  ),
	.userInterruptK 						(  ),
	.userInterruptL 						(  ),

	.axiA_awvalid                           ( gAXIS_m_awvalid[SLB*1 +: 1] ),
	.axiA_awready                           ( gAXIS_m_awready[SLB*1 +: 1] ),
	.axiA_awaddr                            ( gAXIS_m_awaddr[SLB*32 +: 32] ),
	.axiA_awlen                             ( gAXIS_m_awlen[SLB*8 +: 8] ),
	.axiA_awburst                           ( gAXIS_m_awburst[SLB*2 +: 2] ),
	.axiA_awsize                            ( gAXIS_m_awsize[SLB*3 +: 3] ),
	.axiA_awcache                           ( gAXIS_m_awcache[SLB*4 +: 4] ),
	.axiA_awprot                            ( gAXIS_m_awprot[SLB*3 +: 3] ),
	.axiA_wvalid                            ( gAXIS_m_wvalid[SLB*1 +: 1] ),
	.axiA_wready                            ( gAXIS_m_wready[SLB*1 +: 1] ),
	.axiA_wdata                             ( gAXIS_m_wdata[SLB*32 +: 32] ),
	.axiA_wstrb                             ( gAXIS_m_wstrb[SLB*4 +: 4] ),
	.axiA_wlast                             ( gAXIS_m_wlast[SLB*1 +: 1] ),
	.axiA_bvalid                            ( gAXIS_m_bvalid[SLB*1 +: 1] ),
	.axiA_bready                            ( gAXIS_m_bready[SLB*1 +: 1] ),
	.axiA_bresp                             ( gAXIS_m_bresp[SLB*2 +: 2] ),
	.axiA_arvalid                           ( gAXIS_m_arvalid[SLB*1 +: 1] ),
	.axiA_arready                           ( gAXIS_m_arready[SLB*1 +: 1] ),
	.axiA_araddr                            ( gAXIS_m_araddr[SLB*32 +: 32] ),
	.axiA_arlen                             ( gAXIS_m_arlen[SLB*8 +: 8] ),
	.axiA_arburst                           ( gAXIS_m_arburst[SLB*2 +: 2]),
	.axiA_arsize                            ( gAXIS_m_arsize[SLB*3 +: 3] ),
	.axiA_arcache                           ( gAXIS_m_arcache[SLB*4 +: 4] ),
	.axiA_arprot                            ( gAXIS_m_arprot[SLB*3 +: 3] ),
	.axiA_rvalid                            ( gAXIS_m_rvalid[SLB*1 +: 1] ),
	.axiA_rready                            ( gAXIS_m_rready[SLB*1 +: 1] ),
	.axiA_rdata                             ( gAXIS_m_rdata[SLB*32 +: 32] ),
	.axiA_rresp                             ( gAXIS_m_rresp[SLB*2 +: 2] ),
	.axiA_rlast                             ( gAXIS_m_rlast[SLB*1 +: 1] ),
	.axiAInterrupt                          ( axiAInterrupt ),

	.cfg_done                               ( cfg_done ),
	.cfg_start                              ( cfg_start ),
	.cfg_sel                                ( cfg_sel ),
	.cfg_reset                              ( cfg_reset ),
	.io_peripheralClk                       ( io_peripheralClk ),
	.io_peripheralReset                     ( io_peripheralReset ),
	.io_asyncReset                          ( io_asyncReset ),
	.io_gpio_sw_n                           ( io_gpio_sw_n ), 
	.pll_peripheral_locked                  ( pll_peripheral_locked ),
	.pll_system_locked                      ( pll_system_locked )
);

EfxSapphireFCU u_EfxSapphireFCU
(
	.io_asyncReset 							( io_asyncReset ),
	.io_systemClk 							( io_peripheralClk ),
	.io_systemReset 						(  ),
	.io_memoryClk 							( io_ddrMasters_0_clk ),
	.io_memoryReset 						(  ),

	.io_jtag_tck 							( sys_jtag_io_tck ),
	.io_jtag_tms 							( sys_jtag_io_tms ),
	.io_jtag_tdi 							( sys_jtag_io_tdi ),
	.io_jtag_tdo 							( sys_jtag_io_tdo ),

	.io_ddrA_aw_payload_addr 				( gAXIM_s_awaddr[MFCU*32 +: 32] ),
	.io_ddrA_aw_valid 						( gAXIM_s_awvalid[MFCU*1 +: 1] ),
	.io_ddrA_aw_payload_len 				( gAXIM_s_awlen[MFCU*8 +: 8] ),
	.io_ddrA_aw_ready 						( gAXIM_s_awready[MFCU*1 +: 1] ),
	.io_ddrA_aw_payload_burst 				( gAXIM_s_awburst[MFCU*2 +: 2] ),
	.io_ddrA_aw_payload_size 				( gAXIM_s_awsize[MFCU*3 +: 3] ),
	.io_ddrA_aw_payload_cache 				( gAXIM_s_awcache[MFCU*4 +: 4] ),
	.io_ddrA_aw_payload_lock 				( gAXIM_s_awlock[MFCU*2 +: 2] ),
	.io_ddrA_aw_payload_prot 				( gAXIM_s_awprot[MFCU*4 +: 4] ),
	.io_ddrA_aw_payload_region 				(  ),
	.io_ddrA_aw_payload_qos 				(  ),
	.io_ddrA_aw_payload_id 					(  ),
	.io_ddrA_w_payload_data 				( gAXIM_s_wdata[MFCU*128 +: 128] ),
	.io_ddrA_w_payload_strb 				( gAXIM_s_wstrb[MFCU*16 +: 16] ),
	.io_ddrA_w_payload_last 				( gAXIM_s_wlast[MFCU*1 +: 1] ),
	.io_ddrA_w_valid 						( gAXIM_s_wvalid[MFCU*1 +: 1] ),
	.io_ddrA_w_ready 						( gAXIM_s_wready[MFCU*1 +:1] ),
	.io_ddrA_b_payload_resp 				( gAXIM_s_bresp[MFCU*2 +: 2] ),
	.io_ddrA_b_valid 						( gAXIM_s_bvalid[MFCU*1 +: 1] ),
	.io_ddrA_b_ready 						( gAXIM_s_bready[MFCU*1 +: 1] ),
	.io_ddrA_b_payload_id 					(  ),
	.io_ddrA_ar_valid 						( gAXIM_s_arvalid[MFCU*1 +: 1] ),
	.io_ddrA_ar_payload_addr 				( gAXIM_s_araddr[MFCU*32 +: 32] ),
	.io_ddrA_ar_payload_len 				( gAXIM_s_arlen[MFCU*8 +: 8] ),
	.io_ddrA_ar_payload_size 				( gAXIM_s_arsize[MFCU*3 +: 3] ),
	.io_ddrA_ar_payload_burst	 			( gAXIM_s_arburst[MFCU*2 +: 2] ),
	.io_ddrA_ar_payload_prot 				( gAXIM_s_arprot[MFCU*4 +: 4] ),
	.io_ddrA_ar_payload_lock 				( gAXIM_s_arlock[MFCU*2 +: 2] ),
	.io_ddrA_ar_payload_cache 				( gAXIM_s_arcache[MFCU*4 +: 4] ),
	.io_ddrA_ar_ready 						( gAXIM_s_arready[MFCU*1 +: 1] ),
	.io_ddrA_ar_payload_region 				( gAXIM_s_arregion[MFCU*4 +: 4] ),
	.io_ddrA_ar_payload_qos 				( gAXIM_s_arqos[MFCU*4 +: 4] ),
	.io_ddrA_ar_payload_id 					(  ),
	.io_ddrA_r_valid 						( gAXIM_s_rvalid[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_data 				( gAXIM_s_rdata[MFCU*128 +: 128] ),
	.io_ddrA_r_payload_last 				( gAXIM_s_rlast[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_resp 				( gAXIM_s_rresp[MFCU*2 +: 2] ),
	.io_ddrA_r_ready	 					( gAXIM_s_rready[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_id 					(  ),

	.userInterruptA 						( userInterruptA ),
	
	.system_spi_0_io_ss 					( sys_spi_0_io_ss[0] ),
	.system_spi_0_io_data_0_read 			( sys_spi_0_io_data_0_read ),
	.system_spi_0_io_data_0_write 			( sys_spi_0_io_data_0_write ),
	.system_spi_0_io_data_0_writeEnable 	( sys_spi_0_io_data_0_writeEnable ),
	.system_spi_0_io_data_1_read 			( sys_spi_0_io_data_1_read ),
	.system_spi_0_io_data_1_write 			( sys_spi_0_io_data_1_write ),
	.system_spi_0_io_data_1_writeEnable	 	( sys_spi_0_io_data_1_writeEnable ),
	.system_spi_0_io_data_2_read 			( sys_spi_0_io_data_2_read ),
	.system_spi_0_io_data_2_write 			( sys_spi_0_io_data_2_write ),
	.system_spi_0_io_data_2_writeEnable 	( sys_spi_0_io_data_2_writeEnable ),
	.system_spi_0_io_data_3_read 			( sys_spi_0_io_data_3_read ),
	.system_spi_0_io_data_3_write 			( sys_spi_0_io_data_3_write ),
	.system_spi_0_io_data_3_writeEnable 	( sys_spi_0_io_data_3_writeEnable ),
	.system_spi_0_io_sclk_write 			( sys_spi_0_io_sclk_write ),

	.system_spi_1_io_ss 					( sys_spi_1_io_ss[0] ),
	.system_spi_1_io_data_0_read 			( sys_spi_1_io_data_0_read ),
	.system_spi_1_io_data_0_write 			( sys_spi_1_io_data_0_write ),
	.system_spi_1_io_data_0_writeEnable 	( sys_spi_1_io_data_0_writeEnable ),
	.system_spi_1_io_data_1_read 			( sys_spi_1_io_data_1_read ),
	.system_spi_1_io_data_1_write 			( sys_spi_1_io_data_1_write ),
	.system_spi_1_io_data_1_writeEnable 	( sys_spi_1_io_data_1_writeEnable ),
	.system_spi_1_io_data_2_read 			( sys_spi_1_io_data_2_read ),
	.system_spi_1_io_data_2_write 			( sys_spi_1_io_data_2_write ),
	.system_spi_1_io_data_2_writeEnable 	( sys_spi_1_io_data_2_writeEnable ),
	.system_spi_1_io_data_3_read 			( sys_spi_1_io_data_3_read ),
	.system_spi_1_io_data_3_write 			( sys_spi_1_io_data_3_write ),
	.system_spi_1_io_data_3_writeEnable 	( sys_spi_1_io_data_3_writeEnable ),
	.system_spi_1_io_sclk_write 			( sys_spi_1_io_sclk_write ),

	.system_spi_2_io_ss 					( sys_spi_2_io_ss[0] ),
	.system_spi_2_io_data_0_read 			( sys_spi_2_io_data_0_read ),
	.system_spi_2_io_data_0_write 			( sys_spi_2_io_data_0_write ),
	.system_spi_2_io_data_0_writeEnable 	( sys_spi_2_io_data_0_writeEnable ),
	.system_spi_2_io_data_1_read 			( sys_spi_2_io_data_1_read ),
	.system_spi_2_io_data_1_write 			( sys_spi_2_io_data_1_write ),
	.system_spi_2_io_data_1_writeEnable 	( sys_spi_2_io_data_1_writeEnable ),
	.system_spi_2_io_data_2_read 			( sys_spi_2_io_data_2_read ),
	.system_spi_2_io_data_2_write 			( sys_spi_2_io_data_2_write ),
	.system_spi_2_io_data_2_writeEnable 	( sys_spi_2_io_data_2_writeEnable ),
	.system_spi_2_io_data_3_read 			( sys_spi_2_io_data_3_read ),
	.system_spi_2_io_data_3_write 			( sys_spi_2_io_data_3_write ),
	.system_spi_2_io_data_3_writeEnable 	( sys_spi_2_io_data_3_writeEnable ),
	.system_spi_2_io_sclk_write 			( sys_spi_2_io_sclk_write ),

	.system_uart_0_io_rxd 					( sys_uart_0_io_rxd ),
	.system_uart_0_io_txd 					( sys_uart_0_io_txd ),
	.system_uart_1_io_rxd 					( sys_uart_1_io_rxd ),
	.system_uart_1_io_txd 					( sys_uart_1_io_txd ),
	.system_uart_2_io_rxd 					( sys_uart_2_io_rxd ),
	.system_uart_2_io_txd 					( sys_uart_2_io_txd ),

	.system_i2c_0_io_scl_read 				( sys_i2c_0_io_scl_read ),
	.system_i2c_0_io_scl_write 				( sys_i2c_0_io_scl_write ),
	.system_i2c_0_io_sda_read 				( sys_i2c_0_io_sda_read ),
	.system_i2c_0_io_sda_write 				( sys_i2c_0_io_sda_write ),

	.system_i2c_1_io_scl_read 				( sys_i2c_1_io_scl_read ),
	.system_i2c_1_io_scl_write 				( sys_i2c_1_io_scl_write ),
	.system_i2c_1_io_sda_write 				( sys_i2c_1_io_sda_write ),
	.system_i2c_1_io_sda_read 				( sys_i2c_1_io_sda_read ),

	.system_i2c_2_io_scl_read 				( sys_i2c_2_io_scl_read ),
	.system_i2c_2_io_scl_write 				( sys_i2c_2_io_scl_write ),
	.system_i2c_2_io_sda_write 				( sys_i2c_2_io_sda_write ),
	.system_i2c_2_io_sda_read 				( sys_i2c_2_io_sda_read ),

	.system_gpio_0_io_read 					( sys_gpio_0_io_read ),
	.system_gpio_0_io_write 				( sys_gpio_0_io_write ),
	.system_gpio_0_io_writeEnable 			( sys_gpio_0_io_writeEnable ),

	.system_gpio_1_io_read 					(  ),
	.system_gpio_1_io_write 				(  ),
	.system_gpio_1_io_writeEnable 			(  ),

	.system_watchdog_hardPanic 				(  )
);

endmodule
