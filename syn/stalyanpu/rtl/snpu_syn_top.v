// =============================================================================
// snpu_syn_top.v
//
// Synthesis wrapper of snpu_top. The APB slave and AXI master inputs are
// driven from a shift register fed by one pin and every output is folded
// into one pin, the same scheme as snpu_syn_conv. The wrapper is not
// functional; it keeps the whole accelerator alive for the mapper so the
// resource and timing numbers of the full top level can be read.
// =============================================================================
`timescale 1ns / 1ps

module snpu_syn_top #(
    parameter N_CHAIN     = 32,
    parameter CHAIN_LEN   = 32,
    parameter P_MAX       = 1024,
    parameter P_W         = 10,
    parameter IBUF_WORDS  = 16384,
    parameter IBUF_AW     = 14,
    parameter WFIFO_WORDS = 1024,
    parameter WFIFO_AW    = 10,
    parameter OC_MAX      = 512,
    parameter AXI_DW      = 128,
    parameter MP_MAX_W    = 128,
    parameter MP_W_AW     = 7
)(
    input  wire clk,
    input  wire pll_locked,
    input  wire rst_i,
    input  wire sin,
    output reg  sout
);

    reg [1:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[0], rst_i || !pll_locked};
    wire rst = rst_sync[1];

    localparam O_PADDR   = 0;
    localparam O_PSEL    = O_PADDR + 6;
    localparam O_PENABLE = O_PSEL + 1;
    localparam O_PWRITE  = O_PENABLE + 1;
    localparam O_PWDATA  = O_PWRITE + 1;
    localparam O_ARREADY = O_PWDATA + 32;
    localparam O_RVALID  = O_ARREADY + 1;
    localparam O_RDATA   = O_RVALID + 1;
    localparam O_RID     = O_RDATA + AXI_DW;
    localparam O_RLAST   = O_RID + 4;
    localparam O_RRESP   = O_RLAST + 1;
    localparam O_AWREADY = O_RRESP + 2;
    localparam O_WREADY  = O_AWREADY + 1;
    localparam O_BVALID  = O_WREADY + 1;
    localparam O_BRESP   = O_BVALID + 1;
    localparam IN_W      = O_BRESP + 2;

    reg [IN_W-1:0] sr;
    always @(posedge clk)
        sr <= {sr[IN_W-2:0], sin ^ sr[IN_W-1] ^ sr[IN_W/2]};

    wire [31:0] prdata;
    wire        pready, pslverr, irq;
    wire        arvalid, rready, awvalid, wvalid, wlast, bready;
    wire [31:0] araddr, awaddr;
    wire [7:0]  arlen, awlen;
    wire [2:0]  arsize, awsize;
    wire [1:0]  arburst, awburst;
    wire [3:0]  arid, awid;
    wire [AXI_DW-1:0]   wdata;
    wire [AXI_DW/8-1:0] wstrb;

    snpu_top #(
        .N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .P_MAX(P_MAX), .P_W(P_W),
        .IBUF_WORDS(IBUF_WORDS), .IBUF_AW(IBUF_AW),
        .WFIFO_WORDS(WFIFO_WORDS), .WFIFO_AW(WFIFO_AW), .OC_MAX(OC_MAX),
        .AXI_DW(AXI_DW), .MP_MAX_W(MP_MAX_W), .MP_W_AW(MP_W_AW)
    ) u_top (
        .clk(clk), .rst(rst),
        .paddr_i   (sr[O_PADDR +: 6]),
        .psel_i    (sr[O_PSEL]),
        .penable_i (sr[O_PENABLE]),
        .pwrite_i  (sr[O_PWRITE]),
        .pwdata_i  (sr[O_PWDATA +: 32]),
        .prdata_o  (prdata),
        .pready_o  (pready),
        .pslverr_o (pslverr),
        .irq_o     (irq),
        .m_arvalid (arvalid),
        .m_arready (sr[O_ARREADY]),
        .m_araddr  (araddr),
        .m_arlen   (arlen),
        .m_arsize  (arsize),
        .m_arburst (arburst),
        .m_arid    (arid),
        .m_rvalid  (sr[O_RVALID]),
        .m_rready  (rready),
        .m_rdata   (sr[O_RDATA +: AXI_DW]),
        .m_rid     (sr[O_RID +: 4]),
        .m_rlast   (sr[O_RLAST]),
        .m_rresp   (sr[O_RRESP +: 2]),
        .m_awvalid (awvalid),
        .m_awready (sr[O_AWREADY]),
        .m_awaddr  (awaddr),
        .m_awlen   (awlen),
        .m_awsize  (awsize),
        .m_awburst (awburst),
        .m_awid    (awid),
        .m_wvalid  (wvalid),
        .m_wready  (sr[O_WREADY]),
        .m_wdata   (wdata),
        .m_wstrb   (wstrb),
        .m_wlast   (wlast),
        .m_bvalid  (sr[O_BVALID]),
        .m_bready  (bready),
        .m_bresp   (sr[O_BRESP +: 2])
    );

    localparam OUT_W = 32 + 3 + 1 + 32 + 8 + 3 + 2 + 4 + 1 + 1 + 32 + 8 + 3 + 2 + 4 + 1 + AXI_DW + AXI_DW/8 + 1 + 1;
    localparam FOLDS = (OUT_W + 31) / 32;
    wire [FOLDS*32-1:0] outs;
    assign outs = {{(FOLDS*32-OUT_W){1'b0}},
                   prdata, pready, pslverr, irq,
                   arvalid, araddr, arlen, arsize, arburst, arid, rready,
                   awvalid, awaddr, awlen, awsize, awburst, awid,
                   wvalid, wdata, wstrb, wlast, bready};
    reg [FOLDS-1:0] fold;
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < FOLDS; i = i + 1)
            fold[i] <= ^outs[i*32 +: 32];
        sout <= ^fold;
    end

endmodule
