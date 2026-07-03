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

input [5:0]     sys_gpio_0_io_read,
output [5:0]    sys_gpio_0_io_write,
output [5:0]    sys_gpio_0_io_writeEnable,

output		    sys_uart_0_io_txd,
input		    sys_uart_0_io_rxd,
output		    sys_uart_1_io_txd,
input		    sys_uart_1_io_rxd,
output		    sys_uart_2_io_txd,
input		    sys_uart_2_io_rxd,

output		    sys_spi_0_io_sclk_write,
input		    sys_spi_0_io_data_0_read,
output		    sys_spi_0_io_data_0_write,
output		    sys_spi_0_io_data_0_writeEnable,
input		    sys_spi_0_io_data_1_read,
output		    sys_spi_0_io_data_1_write,
output		    sys_spi_0_io_data_1_writeEnable,
input		    sys_spi_0_io_data_2_read,
output		    sys_spi_0_io_data_2_write,
output		    sys_spi_0_io_data_2_writeEnable,
input		    sys_spi_0_io_data_3_read,
output		    sys_spi_0_io_data_3_write,
output		    sys_spi_0_io_data_3_writeEnable,
output [3:0]    sys_spi_0_io_ss,

output		    sys_spi_1_io_sclk_write,
input		    sys_spi_1_io_data_0_read,
output		    sys_spi_1_io_data_0_write,
output		    sys_spi_1_io_data_0_writeEnable,
input		    sys_spi_1_io_data_1_read,
output		    sys_spi_1_io_data_1_write,
output		    sys_spi_1_io_data_1_writeEnable,
input		    sys_spi_1_io_data_2_read,
output		    sys_spi_1_io_data_2_write,
output		    sys_spi_1_io_data_2_writeEnable,
input		    sys_spi_1_io_data_3_read,
output		    sys_spi_1_io_data_3_write,
output		    sys_spi_1_io_data_3_writeEnable,
output [3:0]    sys_spi_1_io_ss,

output		    sys_spi_2_io_sclk_write,
input		    sys_spi_2_io_data_0_read,
output		    sys_spi_2_io_data_0_write,
output		    sys_spi_2_io_data_0_writeEnable,
input		    sys_spi_2_io_data_1_read,
output		    sys_spi_2_io_data_1_write,
output		    sys_spi_2_io_data_1_writeEnable,
input		    sys_spi_2_io_data_2_read,
output		    sys_spi_2_io_data_2_write,
output		    sys_spi_2_io_data_2_writeEnable,
input		    sys_spi_2_io_data_3_read,
output		    sys_spi_2_io_data_3_write,
output		    sys_spi_2_io_data_3_writeEnable,
output [3:0]    sys_spi_2_io_ss,

input		    sys_i2c_0_io_sda_read,
output		    sys_i2c_0_io_sda_write,
output		    sys_i2c_0_io_sda_writeEnable,
input		    sys_i2c_0_io_scl_read,
output		    sys_i2c_0_io_scl_write,
output		    sys_i2c_0_io_scl_writeEnable,

input		    sys_i2c_1_io_sda_read,
output		    sys_i2c_1_io_sda_write,
output		    sys_i2c_1_io_sda_writeEnable,
input		    sys_i2c_1_io_scl_read,
output		    sys_i2c_1_io_scl_write,
output		    sys_i2c_1_io_scl_writeEnable,

input		    sys_i2c_2_io_sda_read,
output		    sys_i2c_2_io_sda_write,
output		    sys_i2c_2_io_sda_writeEnable,
input		    sys_i2c_2_io_scl_read,
output		    sys_i2c_2_io_scl_write,
output		    sys_i2c_2_io_scl_writeEnable,

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

localparam TSE		= 0;	// AXI S1
localparam SDHC		= 1;	// AXI S0
localparam AXIS_DEV	= 2;

localparam MTSE		= 0;
localparam MSDHC	= 1;
localparam MFCU		= 2;
localparam AXIM_DEV	= 3;

////////////////////////////////////////////////////////////////////////////
// Switch between SP SoC -> SDHC, TSEMAC
// 	These AXI Slaves are connected to the AXI Interconnect Master ports 
wire [(AXIS_DEV*32)-1:0]    s_axis_awaddr;
wire [(AXIS_DEV*8)-1:0]	    s_axis_awlen;
wire [(AXIS_DEV*3)-1:0]	    s_axis_awsize;
wire [(AXIS_DEV*2)-1:0]     s_axis_awburst;
wire [(AXIS_DEV*2)-1:0]     s_axis_awlock;
wire [(AXIS_DEV*4)-1:0]	    s_axis_awcache;
wire [(AXIS_DEV*4)-1:0]	    s_axis_awprot;
wire [(AXIS_DEV*4)-1:0]	    s_axis_awqos;
wire [(AXIS_DEV*4)-1:0]	    s_axis_awregion;
wire [AXIS_DEV-1:0]         s_axis_awvalid;
wire [AXIS_DEV-1:0]         s_axis_awready;
wire [(AXIS_DEV*32)-1:0]    s_axis_wdata;
wire [(AXIS_DEV*4)-1:0]     s_axis_wstrb;
wire [AXIS_DEV-1:0]         s_axis_wvalid;
wire [AXIS_DEV-1:0]         s_axis_wlast;
wire [AXIS_DEV-1:0]         s_axis_wready;
wire [(AXIS_DEV*2)-1:0]     s_axis_bresp;
wire [AXIS_DEV-1:0]         s_axis_bvalid;
wire [AXIS_DEV-1:0]         s_axis_bready;
wire [(AXIS_DEV*32)-1:0]    s_axis_araddr;
wire [(AXIS_DEV*8)-1:0]	    s_axis_arlen;
wire [(AXIS_DEV*3)-1:0]	    s_axis_arsize;
wire [(AXIS_DEV*2)-1:0]	    s_axis_arburst;
wire [(AXIS_DEV*2)-1:0]     s_axis_arlock;
wire [(AXIS_DEV*4)-1:0]	    s_axis_arcache;
wire [(AXIS_DEV*4)-1:0]	    s_axis_arprot;
wire [(AXIS_DEV*4)-1:0]	    s_axis_arqos;
wire [(AXIS_DEV*4)-1:0]	    s_axis_arregion;
wire [AXIS_DEV-1:0]         s_axis_arvalid;
wire [AXIS_DEV-1:0]         s_axis_arready;
wire [(AXIS_DEV*32)-1:0]    s_axis_rdata;
wire [(AXIS_DEV*2)-1:0]     s_axis_rresp;
wire [AXIS_DEV-1:0]         s_axis_rlast;
wire [AXIS_DEV-1:0]         s_axis_rvalid;
wire [AXIS_DEV-1:0]         s_axis_rready;

////////////////////////////////////////////////////////////////////////////
// Switch between TSEMAC, SDHC, SP SoC -> DDRAM
// 	These AXI Masters are connected to the AXI Interconnect Slave ports
wire [(AXIM_DEV*32)-1:0]    m_axis_awaddr;
wire [(AXIM_DEV*8)-1:0]	    m_axis_awlen;
wire [(AXIM_DEV*3)-1:0]	    m_axis_awsize;
wire [(AXIM_DEV*2)-1:0]     m_axis_awburst;
wire [(AXIM_DEV*2)-1:0]     m_axis_awlock;
wire [(AXIM_DEV*4)-1:0]	    m_axis_awcache;
wire [(AXIM_DEV*4)-1:0]	    m_axis_awprot;
wire [(AXIM_DEV*4)-1:0]	    m_axis_awqos;
wire [(AXIM_DEV*4)-1:0]	    m_axis_awregion;
wire [AXIM_DEV-1:0]         m_axis_awvalid;
wire [AXIM_DEV-1:0]         m_axis_awready;
wire [(AXIM_DEV*128)-1:0]   m_axis_wdata;
wire [(AXIM_DEV*16)-1:0]    m_axis_wstrb;
wire [AXIM_DEV-1:0]         m_axis_wvalid;
wire [AXIM_DEV-1:0]         m_axis_wlast;
wire [AXIM_DEV-1:0]         m_axis_wready;
wire [(AXIM_DEV*2)-1:0]     m_axis_bresp;
wire [AXIM_DEV-1:0]         m_axis_bvalid;
wire [AXIM_DEV-1:0]         m_axis_bready;
wire [(AXIM_DEV*32)-1:0]    m_axis_araddr;
wire [(AXIM_DEV*8)-1:0]	    m_axis_arlen;
wire [(AXIM_DEV*3)-1:0]	    m_axis_arsize;
wire [(AXIM_DEV*2)-1:0]	    m_axis_arburst;
wire [(AXIM_DEV*2)-1:0]     m_axis_arlock;
wire [(AXIM_DEV*4)-1:0]	    m_axis_arcache;
wire [(AXIM_DEV*4)-1:0]	    m_axis_arprot;
wire [(AXIM_DEV*4)-1:0]	    m_axis_arqos;
wire [(AXIM_DEV*4)-1:0]	    m_axis_arregion;
wire [AXIM_DEV-1:0]         m_axis_arvalid;
wire [AXIM_DEV-1:0]         m_axis_arready;
wire [(AXIM_DEV*128)-1:0]   m_axis_rdata;
wire [(AXIM_DEV*2)-1:0]     m_axis_rresp;
wire [AXIM_DEV-1:0]         m_axis_rlast;
wire [AXIM_DEV-1:0]         m_axis_rvalid;
wire [AXIM_DEV-1:0]         m_axis_rready;
// SDHC
wire                        sd_rst;
wire                        sd_int;
wire                        sd_dat_oe_i;
// DMA
wire                        dma_tx_rst;
wire                        dma_rx_rst;
wire                        dma_tx_descriptorUpdate;
wire                        dma_rx_descriptorUpdate;
wire [1:0]                  dma_interrupts;
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

wire						sp_asyncReset;
wire 						sp_watchdogReset;
wire						sp_spi_io_sclk_write;
wire						sp_spi_0_io_sclk_write;
wire						sp_spi_1_io_sclk_write;

wire [31:0]    				sp_m_axis_awaddr;
wire [7:0]	    			sp_m_axis_awlen;
wire [2:0]	    			sp_m_axis_awsize;
wire [1:0]	    			sp_m_axis_awburst;
wire		    			sp_m_axis_awlock;
wire [3:0]	    			sp_m_axis_awcache;
wire [2:0]	    			sp_m_axis_awprot;
wire [3:0]	    			sp_m_axis_awqos;
wire [3:0]	    			sp_m_axis_awregion;
wire		    			sp_m_axis_awvalid;
wire		    			sp_m_axis_awready;
wire [7:0]		    		sp_m_axis_awid;
wire [31:0]    				sp_m_axis_wdata;
wire [3:0]     				sp_m_axis_wstrb;
wire		    			sp_m_axis_wvalid;
wire		    			sp_m_axis_wlast;
wire		    			sp_m_axis_wready;
wire [1:0]    				sp_m_axis_bresp;
wire		    			sp_m_axis_bvalid;
wire		    			sp_m_axis_bready;
wire [31:0]    				sp_m_axis_araddr;
wire [7:0]	    			sp_m_axis_arlen;
wire [2:0]	    			sp_m_axis_arsize;
wire [1:0]	    			sp_m_axis_arburst;
wire		    			sp_m_axis_arlock;
wire [3:0]	    			sp_m_axis_arcache;
wire [2:0]	    			sp_m_axis_arprot;
wire [3:0]	    			sp_m_axis_arqos;
wire [3:0]	    			sp_m_axis_arregion;
wire		    			sp_m_axis_arvalid;
wire		    			sp_m_axis_arready;
wire [7:0]					sp_m_axis_arid;
wire [31:0]   				sp_m_axis_rdata;
wire [1:0]    				sp_m_axis_rresp;
wire		    			sp_m_axis_rlast;
wire		    			sp_m_axis_rvalid;
wire		    			sp_m_axis_rready;

wire [15:0]   				sp_apbSlave_0_PADDR;
wire          				sp_apbSlave_0_PSEL;
wire            			sp_apbSlave_0_PENABLE;
wire            			sp_apbSlave_0_PREADY;
wire            			sp_apbSlave_0_PWRITE;
wire [31:0]   				sp_apbSlave_0_PWDATA;
wire [31:0]   				sp_apbSlave_0_PRDATA;
wire            			sp_apbSlave_0_PSLVERROR;

//-------------------------------------------------------------------
// SP SoC can access to the TSEMAC, SDHC using AXI interconnect
//-------------------------------------------------------------------
gAXIS_1to2_switch u_AXIS_1to2_switch
(
    .rst_n              ( ~io_peripheralReset ),
    .clk                ( io_peripheralClk ),
    .m_axi_awvalid      ( s_axis_awvalid ),
    .m_axi_awready      ( s_axis_awready ),
    .m_axi_awid         ( ),
    .m_axi_awaddr       ( s_axis_awaddr ),
    .m_axi_awburst      ( s_axis_awburst ),
    .m_axi_awlen        ( s_axis_awlen ),
    .m_axi_awsize       ( s_axis_awsize ),
    .m_axi_awcache      ( s_axis_awcache ),
    .m_axi_awqos        ( s_axis_awqos ),
    .m_axi_awprot       ( s_axis_awprot ),
    .m_axi_awuser       ( ),
    .m_axi_awlock       ( s_axis_awlock ),
    .m_axi_awregion     ( s_axis_awregion ),
    .m_axi_wvalid       ( s_axis_wvalid ),
    .m_axi_wready       ( s_axis_wready ),
    .m_axi_wdata        ( s_axis_wdata ),
    .m_axi_wstrb        ( s_axis_wstrb ),
    .m_axi_wlast        ( s_axis_wlast ),
    .m_axi_wuser        ( ),
    .m_axi_bready       ( s_axis_bready ),
    .m_axi_bvalid       ( s_axis_bvalid ),
    .m_axi_bresp        ( s_axis_bresp ),
    .m_axi_buser        ( {AXIS_DEV{3'b0}} ),
    .m_axi_bid          ( {AXIS_DEV{8'b0}} ),
    .m_axi_arvalid      ( s_axis_arvalid ),
    .m_axi_arready      ( s_axis_arready ),
    .m_axi_arid         ( ),
    .m_axi_araddr       ( s_axis_araddr ),
    .m_axi_arburst      ( s_axis_arburst ),
    .m_axi_arlen        ( s_axis_arlen ),
    .m_axi_arsize       ( s_axis_arsize ),
    .m_axi_arlock       ( s_axis_arlock ),
    .m_axi_arprot       ( s_axis_arprot ),
    .m_axi_arcache      ( s_axis_arcache ),
    .m_axi_arqos        ( s_axis_arqos ),
    .m_axi_aruser       ( ),
    .m_axi_arregion     ( s_axis_arregion ),
    .m_axi_ruser        ( {AXIS_DEV{3'b0}}),
    .m_axi_rvalid       ( s_axis_rvalid ),
    .m_axi_rready       ( s_axis_rready ),
    .m_axi_rid          ( {AXIS_DEV{8'b0}}),
    .m_axi_rdata        ( s_axis_rdata ),
    .m_axi_rresp        ( s_axis_rresp ),
    .m_axi_rlast        ( s_axis_rlast ),

    .s_axi_awvalid      ( sp_m_axis_awvalid ),
    .s_axi_awready      ( sp_m_axis_awready ),
    .s_axi_awaddr       ( {7'b0, sp_m_axis_awaddr[24:0]} ),
    .s_axi_awid         ( sp_m_axis_awid ),
    .s_axi_awburst      ( sp_m_axis_awburst ),
    .s_axi_awlen        ( sp_m_axis_awlen ),
    .s_axi_awsize       ( sp_m_axis_awsize ),
    .s_axi_awprot       ( {1'b0, sp_m_axis_awprot} ),
    .s_axi_awlock       ( {1'b0, sp_m_axis_awlock} ),
    .s_axi_awcache      ( sp_m_axis_awcache ),
    .s_axi_awqos        ( sp_m_axis_awqos ),
    .s_axi_awuser       ( 3'b0 ),
    .s_axi_wvalid       ( sp_m_axis_wvalid ),
    .s_axi_wready       ( sp_m_axis_wready ),
    .s_axi_wid          ( 8'b0 ),
    .s_axi_wdata        ( sp_m_axis_wdata ),
    .s_axi_wlast        ( sp_m_axis_wlast ),
    .s_axi_wstrb        ( sp_m_axis_wstrb ),
    .s_axi_wuser        ( 3'b0 ),
    .s_axi_bvalid       ( sp_m_axis_bvalid ),
    .s_axi_bready       ( sp_m_axis_bready ),
    .s_axi_bresp        ( sp_m_axis_bresp ),
    .s_axi_bid          ( ),
    .s_axi_buser        ( ),
    .s_axi_arvalid      ( sp_m_axis_arvalid ),
    .s_axi_arready      ( sp_m_axis_arready ),
    .s_axi_araddr       ( {7'b0, sp_m_axis_araddr[24:0]} ),
    .s_axi_arid         ( 8'b0 ),
    .s_axi_arburst      ( sp_m_axis_arburst ),
    .s_axi_arlen        ( sp_m_axis_arlen ),
    .s_axi_arsize       ( sp_m_axis_arsize ),
    .s_axi_arprot       ( {1'b0, sp_m_axis_arprot} ),
    .s_axi_arlock       ( {1'b0, sp_m_axis_arlock} ),
    .s_axi_arcache      ( sp_m_axis_arcache ),
    .s_axi_arqos        ( sp_m_axis_arqos ),
    .s_axi_aruser       ( 3'b0 ),
    .s_axi_rready       ( sp_m_axis_rready ),
    .s_axi_rvalid       ( sp_m_axis_rvalid ),
    .s_axi_rdata        ( sp_m_axis_rdata ),
    .s_axi_rresp        ( sp_m_axis_rresp ),
    .s_axi_rlast        ( sp_m_axis_rlast ),
    .s_axi_rid          ( ),
    .s_axi_ruser        ( )
);

//-------------------------------------------------------------------
// TSEMAC, SP SoC, SDHC can access to the DDRAM using AXI interconnect
//-------------------------------------------------------------------
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
    .m_axi_buser        ( 3'b0 ),
    .m_axi_bid          ( {4'b0, io_ddrMasters_0_b_payload_id} ),
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
    .m_axi_ruser        ( 3'b0),
    .m_axi_rvalid       ( io_ddrMasters_0_r_valid ),
    .m_axi_rready       ( io_ddrMasters_0_r_ready ),
    .m_axi_rid          ( 8'b0 ),
    .m_axi_rdata        ( io_ddrMasters_0_r_payload_data ),
    .m_axi_rresp        ( io_ddrMasters_0_r_payload_resp ),
    .m_axi_rlast        ( io_ddrMasters_0_r_payload_last ),
    
	.s_axi_awvalid      ( m_axis_awvalid ),
    .s_axi_awready      ( m_axis_awready ),
    .s_axi_awaddr       ( m_axis_awaddr ),
    .s_axi_awid         ( {AXIM_DEV{8'b0}} ),
    .s_axi_awburst      ( m_axis_awburst ),
    .s_axi_awlen        ( m_axis_awlen ),
    .s_axi_awsize       ( m_axis_awsize ),
    .s_axi_awprot       ( m_axis_awprot ),
    .s_axi_awlock       ( m_axis_awlock ),
    .s_axi_awcache      ( m_axis_awcache ),
    .s_axi_awqos        ( m_axis_awqos ),
    .s_axi_awuser       ( {AXIM_DEV{3'b0}} ),
    .s_axi_wvalid       ( m_axis_wvalid ),
    .s_axi_wready       ( m_axis_wready ),
    .s_axi_wid          ( {AXIM_DEV{8'b0}} ),
    .s_axi_wdata        ( m_axis_wdata ),
    .s_axi_wlast        ( m_axis_wlast ),
    .s_axi_wstrb        ( m_axis_wstrb ),
    .s_axi_wuser        ( {AXIM_DEV{3'b0}} ),
    .s_axi_bvalid       ( m_axis_bvalid ),
    .s_axi_bready       ( m_axis_bready ),
    .s_axi_bresp        ( m_axis_bresp ),
    .s_axi_bid          ( ),
    .s_axi_buser        ( ),
    .s_axi_arvalid      ( m_axis_arvalid ),
    .s_axi_arready      ( m_axis_arready ),
    .s_axi_araddr       ( m_axis_araddr ),
    .s_axi_arid         ( {AXIM_DEV{8'b0}} ),
    .s_axi_arburst      ( m_axis_arburst ),
    .s_axi_arlen        ( m_axis_arlen ),
    .s_axi_arsize       ( m_axis_arsize ),
    .s_axi_arprot       ( m_axis_arprot ),
    .s_axi_arlock       ( m_axis_arlock ),
    .s_axi_arcache      ( m_axis_arcache ),
    .s_axi_arqos        ( m_axis_arqos ),
    .s_axi_aruser       ( {AXIM_DEV{3'b0}} ),
    .s_axi_rready       ( m_axis_rready ),
    .s_axi_rvalid       ( m_axis_rvalid ),
    .s_axi_rdata        ( m_axis_rdata ),
    .s_axi_rresp        ( m_axis_rresp ),
    .s_axi_rlast        ( m_axis_rlast ),
    .s_axi_rid          ( ),
    .s_axi_ruser        ( )
);

assign sd_rst                    = io_peripheralReset;
assign s_axis_rlast[SDHC*1 +: 1] = 1'b1;
assign sd_dat_oe                 = {4{sd_dat_oe_i}};
assign userInterruptF            = sd_int;
assign m_axis_awqos[SDHC*4 +: 4] = 4'b0;

gSDHC u_gSDHC
(
    .sd_rst             ( sd_rst ),
    .sd_base_clk        ( sd_base_clk ),
    .sd_int             ( sd_int ),
    .sd_cd_n            ( sd_cd_n ),
    .sd_wp              ( sd_wp ),

    .s_axi_aclk         ( io_peripheralClk ),
    .s_axi_awaddr       ( s_axis_awaddr[SDHC*32 +: 32] ),
    .s_axi_awready      ( s_axis_awready[SDHC*1 +: 1] ),
    .s_axi_awvalid      ( s_axis_awvalid[SDHC*1 +: 1] ),
    .s_axi_wstrb        ( s_axis_wstrb[SDHC*4 +: 4]),
    .s_axi_wdata        ( s_axis_wdata[SDHC*32 +: 32] ),
    .s_axi_wready       ( s_axis_wready[SDHC*1 +: 1] ),
    .s_axi_wvalid       ( s_axis_wvalid[SDHC*1 +: 1] ),
    .s_axi_bresp        ( s_axis_bresp[SDHC*2 +: 2] ),
    .s_axi_bvalid       ( s_axis_bvalid[SDHC*1 +: 1] ),
    .s_axi_araddr       ( s_axis_araddr[SDHC*32 +: 32] ),
    .s_axi_bready       ( s_axis_bready[SDHC*1 +: 1] ),
    .s_axi_arready      ( s_axis_arready[SDHC*1 +: 1] ),
    .s_axi_arvalid      ( s_axis_arvalid[SDHC*1 +: 1] ),
    .s_axi_rresp        ( s_axis_rresp[SDHC*2 +: 2] ),
    .s_axi_rdata        ( s_axis_rdata[SDHC*32 +: 32]),
    .s_axi_rvalid       ( s_axis_rvalid[SDHC*1 +: 1] ),
    .s_axi_rready       ( s_axis_rready[SDHC*1 +: 1] ),

	.m_axi_clk          ( io_ddrMasters_0_clk ),
    .m_axi_awaddr       ( m_axis_awaddr[MSDHC*32 +: 32] ),
    .m_axi_awvalid      ( m_axis_awvalid[MSDHC*1 +: 1] ),
    .m_axi_awlen        ( m_axis_awlen[MSDHC*8 +: 8] ),
    .m_axi_awready      ( m_axis_awready[MSDHC*1 +: 1] ),
    .m_axi_awburst      ( m_axis_awburst[MSDHC*2 +: 2] ),
    .m_axi_awsize       ( m_axis_awsize[MSDHC*3 +: 3] ),
    .m_axi_awcache      ( m_axis_awcache[MSDHC*4 +: 4] ),
    .m_axi_awlock       ( m_axis_awlock[MSDHC*2 +: 2] ),
    .m_axi_awprot       ( m_axis_awprot[MSDHC*4 +: 4] ),
    .m_axi_wdata        ( m_axis_wdata[MSDHC*128 +: 128] ),
    .m_axi_wstrb        ( m_axis_wstrb[MSDHC*16 +: 16] ),
    .m_axi_wlast        ( m_axis_wlast[MSDHC*1 +: 1] ),
    .m_axi_wvalid       ( m_axis_wvalid[MSDHC*1 +: 1] ),
    .m_axi_wready       ( m_axis_wready[MSDHC*1 +:1] ),
    .m_axi_bresp        ( m_axis_bresp[MSDHC*2 +: 2] ),
    .m_axi_bvalid       ( m_axis_bvalid[MSDHC*1 +: 1] ),
    .m_axi_bready       ( m_axis_bready[MSDHC*1 +: 1] ),
    .m_axi_arvalid      ( m_axis_arvalid[MSDHC*1 +: 1] ),
    .m_axi_araddr       ( m_axis_araddr[MSDHC*32 +: 32] ),
    .m_axi_arlen        ( m_axis_arlen[MSDHC*8 +: 8] ),
    .m_axi_arsize       ( m_axis_arsize[MSDHC*3 +: 3] ),
    .m_axi_arburst      ( m_axis_arburst[MSDHC*2 +: 2] ),
    .m_axi_arprot       ( m_axis_arprot[MSDHC*4 +: 4] ),
    .m_axi_arlock       ( m_axis_arlock[MSDHC*2 +: 2] ),
    .m_axi_arcache      ( m_axis_arcache[MSDHC*4 +: 4] ),
    .m_axi_arready      ( m_axis_arready[MHSDC*1 +: 1] ),
    .m_axi_rvalid       ( m_axis_rvalid[MSDHC*1 +: 1] ),
    .m_axi_rdata        ( m_axis_rdata[MSDHC*128 +: 128] ),
    .m_axi_rlast        ( m_axis_rlast[MSDHC*1 +: 1] ),
    .m_axi_rresp        ( m_axis_rresp[MSDHC*2 +: 2] ),
    .m_axi_rready       ( m_axis_rready[MSDHC*1 +: 1] ),

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

    .s_axi_awaddr            ( s_axis_awaddr[TSE*32 +: 32] ),
    .s_axi_awvalid           ( s_axis_awvalid[TSE*1 +: 1] ),
    .s_axi_awready           ( s_axis_awready[TSE*1 +: 1] ),
    .s_axi_wdata             ( s_axis_wdata[TSE*32 +: 32] ), 
    .s_axi_wstrb             ( s_axis_wstrb[TSE*4 +: 4] ),
    .s_axi_wlast             ( s_axis_wlast[TSE*1 +: 1] ),
    .s_axi_wvalid            ( s_axis_wvalid[TSE*1 +: 1] ),
    .s_axi_wready            ( s_axis_wready[TSE*1 +: 1] ),
    .s_axi_bresp             ( s_axis_bresp[TSE*2 +: 2] ),
    .s_axi_bvalid            ( s_axis_bvalid[TSE*1 +: 1] ),
    .s_axi_bready            ( s_axis_bready[TSE*1 +: 1] ),
    .s_axi_araddr            ( s_axis_araddr[TSE*32 +: 32] ),
    .s_axi_arvalid           ( s_axis_arvalid[TSE*1 +: 1] ),
    .s_axi_arready           ( s_axis_arready[TSE*1 +: 1] ),
    .s_axi_rresp             ( s_axis_rresp[TSE*2 +: 2] ),
    .s_axi_rdata             ( s_axis_rdata[TSE*32 +: 32] ),
    .s_axi_rlast             ( s_axis_rlast[TSE*1 +: 1] ),
    .s_axi_rvalid            ( s_axis_rvalid[TSE*1 +: 1] ),
    .s_axi_rready            ( s_axis_rready[TSE*1 +: 1] ),

    .s_eth_tx_tvalid         ( s_eth_tx_tvalid ),
    .s_eth_tx_tready         ( s_eth_tx_tready ),
    .s_eth_tx_tdata          ( s_eth_tx_tdata  ),
    .s_eth_tx_tkeep          ( s_eth_tx_tkeep  ),
    .s_eth_tx_tdest          ( s_eth_tx_tdest  ),
    .s_eth_tx_tlast          ( s_eth_tx_tlast  ),
    .m_eth_rx_tvalid         ( m_eth_rx_tvalid ),
    .m_eth_rx_tready         ( m_eth_rx_tready ),
    .m_eth_rx_tdata          ( m_eth_rx_tdata  ),
    .m_eth_rx_tstrb          (  ),
    .m_eth_rx_tlast          ( m_eth_rx_tlast  )
);

assign userInterruptG = dma_interrupts[0];
assign userInterruptH = dma_interrupts[1];

gDMA u_gDMA (
    .clk                     ( io_ddrMasters_0_clk ),
    .reset                   ( io_ddrMasters_0_reset ),
    .ctrl_clk                ( io_peripheralClk ),
    .ctrl_reset              ( io_peripheralReset ),
    .ctrl_PADDR              ( sp_apbSlave_0_PADDR[13:0] ),
    .ctrl_PREADY             ( sp_apbSlave_0_PREADY ),
    .ctrl_PENABLE            ( sp_apbSlave_0_PENABLE ),
    .ctrl_PSEL               ( sp_apbSlave_0_PSEL ),
    .ctrl_PWRITE             ( sp_apbSlave_0_PWRITE ),
    .ctrl_PWDATA             ( sp_apbSlave_0_PWDATA ),
    .ctrl_PRDATA             ( sp_apbSlave_0_PRDATA ),
    .ctrl_PSLVERROR          ( sp_apbSlave_0_PSLVERROR ),
    .ctrl_interrupts         ( dma_interrupts ),
    .read_arvalid            ( m_axis_arvalid[MTSE*1 +: 1] ),
    .read_araddr             ( m_axis_araddr[MTSE*32 +: 32] ),
    .read_arready            ( m_axis_arready[MTSE*1 +: 1] ),
    .read_arregion           ( m_axis_arregion[MTSE*4 +: 4] ),
    .read_arlen              ( m_axis_arlen[MTSE*8 +: 8] ),
    .read_arsize             ( m_axis_arsize[MTSE*3 +: 3] ),
    .read_arburst            ( m_axis_arburst[MTSE*2 +: 2] ),
    .read_arlock             ( m_axis_arlock[MTSE*2 +: 1] ),
    .read_arcache            ( m_axis_arcache[MTSE*4 +: 4] ),
    .read_arqos              ( m_axis_arqos[MTSE*4 +: 4] ),
    .read_arprot             ( m_axis_arprot[MTSE*4 +: 3] ),
    .read_rready             ( m_axis_rready[MTSE*1 +: 1] ),
    .read_rvalid             ( m_axis_rvalid[MTSE*1 +: 1] ),
    .read_rdata              ( m_axis_rdata[MTSE*128 +: 128] ),
    .read_rlast              ( m_axis_rlast[MTSE*1 +: 1] ),
    .read_rresp              ( m_axis_rresp[MTSE*2 +: 2] ),
    .write_awvalid           ( m_axis_awvalid[MTSE*1 +: 1] ),
    .write_awready           ( m_axis_awready[MTSE*1 +: 1] ),
    .write_awaddr            ( m_axis_awaddr[MTSE*32 +: 32] ),
    .write_awregion          ( m_axis_awregion[MTSE*4 +: 4] ),
    .write_awlen             ( m_axis_awlen[MTSE*8 +: 8] ),
    .write_awsize            ( m_axis_awsize[MTSE*3 +: 3] ),
    .write_awburst           ( m_axis_awburst[MTSE*2 +: 2] ),
    .write_awlock            ( m_axis_awlock[MTSE*2 +: 1] ),
    .write_awcache           ( m_axis_awcache[MTSE*4 +: 4] ),
    .write_awqos             ( m_axis_awqos[MTSE*4 +: 4] ),
    .write_awprot            ( m_axis_awprot[MTSE*4 +: 3] ),
    .write_wvalid            ( m_axis_wvalid[MTSE*1 +: 1] ),
    .write_wready            ( m_axis_wready[MTSE*1 +: 1] ),
    .write_wdata             ( m_axis_wdata[MTSE*128 +: 128] ),
    .write_wstrb             ( m_axis_wstrb[MTSE*16 +: 16] ),
    .write_wlast             ( m_axis_wlast[MTSE*1 +: 1] ),
    .write_bvalid            ( m_axis_bvalid[MTSE*1 +: 1] ),
    .write_bready            ( m_axis_bready[MTSE*1 +: 1] ),
    .write_bresp             ( m_axis_bresp[MTSE*2 +: 2] ),
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
    .io_1_descriptorUpdate   ( dma_tx_descriptorUpdate ),
    .io_0_descriptorUpdate   ( dma_rx_descriptorUpdate )
);

//axi4 bridge to various I/O
EfxSapphireHpSoc_slb u_top_peripherals(

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

	.axiA_awvalid                           (  ),
	.axiA_awready                           (  ),
	.axiA_awaddr                            (  ),
	.axiA_awlen                             (  ),
	.axiA_awburst                           (  ),
	.axiA_awsize                            (  ),
	.axiA_awcache                           (  ),
	.axiA_awprot                            (  ),
	.axiA_wvalid                            (  ),
	.axiA_wready                            (  ),
	.axiA_wdata                             (  ),
	.axiA_wstrb                             (  ),
	.axiA_wlast                             (  ),
	.axiA_bvalid                            (  ),
	.axiA_bready                            (  ),
	.axiA_bresp                             (  ),
	.axiA_arvalid                           (  ),
	.axiA_arready                           (  ),
	.axiA_araddr                            (  ),
	.axiA_arlen                             (  ),
	.axiA_arburst                           (  ),
	.axiA_arsize                            (  ),
	.axiA_arcache                           (  ),
	.axiA_arprot                            (  ),
	.axiA_rvalid                            (  ),
	.axiA_rready                            (  ),
	.axiA_rdata                             (  ),
	.axiA_rresp                             (  ),
	.axiA_rlast                             (  ),
	.axiAInterrupt                          (  ),

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

assign sp_asyncReset = sp_watchdogReset | io_asyncReset;
assign sp_spi_io_sclk_write = sp_spi_0_io_sclk_write | sp_spi_1_io_sclk_write;
assign sys_spi_0_io_sclk_write = sp_spi_io_sclk_write;
assign sys_spi_1_io_sclk_write = sp_spi_io_sclk_write;

EfxSapphireFCU u_EfxSapphireFCU
(
	.io_asyncReset 							( sp_asyncReset ),
	.io_systemClk 							( io_peripheralClk ),
	.io_systemReset 						(  ),
	.io_memoryClk 							( io_ddrMasters_0_clk ),
	.io_memoryReset 						(  ),

	.io_jtag_tck 							( sys_jtag_io_tck ),
	.io_jtag_tms 							( sys_jtag_io_tms ),
	.io_jtag_tdi 							( sys_jtag_io_tdi ),
	.io_jtag_tdo 							( sys_jtag_io_tdo ),

	.io_apbSlave_0_PADDR                    ( sp_apbSlave_0_PADDR ),
	.io_apbSlave_0_PENABLE                  ( sp_apbSlave_0_PENABLE ),
	.io_apbSlave_0_PRDATA                   ( sp_apbSlave_0_PRDATA ),
	.io_apbSlave_0_PREADY                   ( sp_apbSlave_0_PREADY ),
	.io_apbSlave_0_PSEL                     ( sp_apbSlave_0_PSEL ),
	.io_apbSlave_0_PSLVERROR                ( sp_apbSlave_0_PSLVERROR ),
	.io_apbSlave_0_PWDATA                   ( sp_apbSlave_0_PWDATA ),
	.io_apbSlave_0_PWRITE                   ( sp_apbSlave_0_PWRITE ),

	.io_ddrA_aw_payload_addr 				( m_axis_awaddr[MFCU*32 +: 32] ),
	.io_ddrA_aw_valid 						( m_axis_awvalid[MFCU*1 +: 1] ),
	.io_ddrA_aw_payload_len 				( m_axis_awlen[MFCU*8 +: 8] ),
	.io_ddrA_aw_ready 						( m_axis_awready[MFCU*1 +: 1] ),
	.io_ddrA_aw_payload_burst 				( m_axis_awburst[MFCU*2 +: 2] ),
	.io_ddrA_aw_payload_size 				( m_axis_awsize[MFCU*3 +: 3] ),
	.io_ddrA_aw_payload_cache 				( m_axis_awcache[MFCU*4 +: 4] ),
	.io_ddrA_aw_payload_lock 				( m_axis_awlock[MFCU*2 +: 1] ),
	.io_ddrA_aw_payload_prot 				( m_axis_awprot[MFCU*4 +: 3] ),
	.io_ddrA_aw_payload_region 				( m_axis_awregion[MFCU*4 +: 4] ),
	.io_ddrA_aw_payload_qos 				( m_axis_awqos[MFCU*4 +: 4] ),
	.io_ddrA_aw_payload_id 					(  ),
	.io_ddrA_w_payload_data 				( m_axis_wdata[MFCU*128 +: 128] ),
	.io_ddrA_w_payload_strb 				( m_axis_wstrb[MFCU*16 +: 16] ),
	.io_ddrA_w_payload_last 				( m_axis_wlast[MFCU*1 +: 1] ),
	.io_ddrA_w_valid 						( m_axis_wvalid[MFCU*1 +: 1] ),
	.io_ddrA_w_ready 						( m_axis_wready[MFCU*1 +:1] ),
	.io_ddrA_b_payload_resp 				( m_axis_bresp[MFCU*2 +: 2] ),
	.io_ddrA_b_valid 						( m_axis_bvalid[MFCU*1 +: 1] ),
	.io_ddrA_b_ready 						( m_axis_bready[MFCU*1 +: 1] ),
	.io_ddrA_b_payload_id 					(  ),
	.io_ddrA_ar_valid 						( m_axis_arvalid[MFCU*1 +: 1] ),
	.io_ddrA_ar_payload_addr 				( m_axis_araddr[MFCU*32 +: 32] ),
	.io_ddrA_ar_payload_len 				( m_axis_arlen[MFCU*8 +: 8] ),
	.io_ddrA_ar_payload_size 				( m_axis_arsize[MFCU*3 +: 3] ),
	.io_ddrA_ar_payload_burst	 			( m_axis_arburst[MFCU*2 +: 2] ),
	.io_ddrA_ar_payload_prot 				( m_axis_arprot[MFCU*4 +: 3] ),
	.io_ddrA_ar_payload_lock 				( m_axis_arlock[MFCU*2 +: 1] ),
	.io_ddrA_ar_payload_cache 				( m_axis_arcache[MFCU*4 +: 4] ),
	.io_ddrA_ar_ready 						( m_axis_arready[MFCU*1 +: 1] ),
	.io_ddrA_ar_payload_region 				( m_axis_arregion[MFCU*4 +: 4] ),
	.io_ddrA_ar_payload_qos 				( m_axis_arqos[MFCU*4 +: 4] ),
	.io_ddrA_ar_payload_id 					(  ),
	.io_ddrA_r_valid 						( m_axis_rvalid[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_data 				( m_axis_rdata[MFCU*128 +: 128] ),
	.io_ddrA_r_payload_last 				( m_axis_rlast[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_resp 				( m_axis_rresp[MFCU*2 +: 2] ),
	.io_ddrA_r_ready	 					( m_axis_rready[MFCU*1 +: 1] ),
	.io_ddrA_r_payload_id 					(  ),

    .axiA_awvalid      						( sp_m_axis_awvalid ),
    .axiA_awready      						( sp_m_axis_awready ),
    .axiA_awid         						( sp_m_axis_awid ),
    .axiA_awaddr       						( sp_m_axis_awaddr ),
    .axiA_awburst      						( sp_m_axis_awburst ),
    .axiA_awlen        						( sp_m_axis_awlen ),
    .axiA_awsize       						( sp_m_axis_awsize ),
    .axiA_awcache      						( sp_m_axis_awcache ),
    .axiA_awqos        						( sp_m_axis_awqos ),
    .axiA_awprot       						( sp_m_axis_awprot ),
    .axiA_awlock       						( sp_m_axis_awlock ),
    .axiA_awregion     						( sp_m_axis_awregion ),
    .axiA_wvalid       						( sp_m_axis_wvalid ),
    .axiA_wready       						( sp_m_axis_wready ),
    .axiA_wdata        						( sp_m_axis_wdata ),
    .axiA_wstrb        						( sp_m_axis_wstrb ),
    .axiA_wlast        						( sp_m_axis_wlast ),
    .axiA_bready       						( sp_m_axis_bready ),
    .axiA_bvalid       						( sp_m_axis_bvalid ),
    .axiA_bresp        						( sp_m_axis_bresp ),
    .axiA_bid          						( 8'b0 ),
    .axiA_arvalid      						( sp_m_axis_arvalid ),
    .axiA_arready      						( sp_m_axis_arready ),
    .axiA_arid         						( sp_m_axis_arid ),
    .axiA_araddr       						( sp_m_axis_araddr ),
    .axiA_arburst      						( sp_m_axis_arburst ),
    .axiA_arlen        						( sp_m_axis_arlen ),
    .axiA_arsize       						( sp_m_axis_arsize ),
    .axiA_arlock       						( sp_m_axis_arlock ),
    .axiA_arprot       						( sp_m_axis_arprot ),
    .axiA_arcache      						( sp_m_axis_arcache ),
    .axiA_arqos        						( sp_m_axis_arqos ),
    .axiA_arregion     						( sp_m_axis_arregion ),
    .axiA_rvalid       						( sp_m_axis_rvalid ),
    .axiA_rready       						( sp_m_axis_rready ),
    .axiA_rid          						( 8'b0 ),
    .axiA_rdata        						( sp_m_axis_rdata ),
    .axiA_rresp        						( sp_m_axis_rresp ),
    .axiA_rlast        						( sp_m_axis_rlast ),
	.axiAInterrupt     						(  ),

	.userInterruptA 						(  ),
	.userInterruptB 						(  ),
	.userInterruptC 						(  ),
	.userInterruptD 						(  ),
	.userInterruptE 						(  ),
	.userInterruptF 						( sd_int ),				/*	SDHC interrupt 				*/
	.userInterruptG 						( dma_interrupts[0] ),	/*	DMA SG RX channel interrupt */
	.userInterruptH 						( dma_interrupts[1] ),	/*	DMA SG TX channel interrupt */
	
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
	.system_spi_0_io_sclk_write 			( sp_spi_0_io_sclk_write ),

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
	.system_spi_1_io_sclk_write 			( sp_spi_1_io_sclk_write ),

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

	.system_gpio_0_io_read 					( {26'b0, sys_gpio_0_io_read} ),
	.system_gpio_0_io_write 				( sys_gpio_0_io_write[5:0] ),
	.system_gpio_0_io_writeEnable 			( sys_gpio_0_io_writeEnable[5:0] ),

	.system_watchdog_hardPanic 				( sp_watchdogReset )
);

endmodule
