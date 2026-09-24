`timescale 1ns / 1ps
// AXI4 register slice: every channel passes a two-entry skid buffer, so
// valid, ready and payload are all flop outputs on both sides and the
// combinational paths of the master and of the interconnect behind it no
// longer meet. Full throughput, one cycle of latency per channel. Only the
// signals the StalyaNPU master drives are carried; the rest of the AXI
// qualifiers are tied off where the slice is instantiated.

module axi_skid #(
    parameter W = 8
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [W-1:0] s_data,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [W-1:0] m_data
);
    reg         out_v, skid_v;
    reg [W-1:0] out_d, skid_d;

    // Ready upstream only while the skid entry is empty: a beat accepted
    // while the output stalls parks there.
    assign s_ready = !skid_v;
    assign m_valid = out_v;
    assign m_data  = out_d;

    // The skid entry only counts while skid_v is set, so it follows the input
    // whenever it is free: its enable is then a local flop and not the ready
    // coming back from the other side.
    always @(posedge clk)
        if (!skid_v)
            skid_d <= s_data;

    always @(posedge clk) begin
        if (rst) begin
            out_v  <= 1'b0;
            skid_v <= 1'b0;
        end else if (!skid_v) begin
            if (!out_v || m_ready) begin
                out_v <= s_valid;
                out_d <= s_data;
            end else if (s_valid) begin
                skid_v <= 1'b1;
            end
        end else if (m_ready) begin
            out_d  <= skid_d;
            skid_v <= 1'b0;
        end
    end
endmodule

module axi_reg_slice #(
    parameter DW = 128,
    parameter AW = 32
) (
    input  wire            clk,
    input  wire            rst,

    // Slave side, towards the master
    input  wire            s_arvalid,
    output wire            s_arready,
    input  wire [AW-1:0]   s_araddr,
    input  wire [7:0]      s_arlen,
    input  wire [2:0]      s_arsize,
    input  wire [1:0]      s_arburst,
    output wire            s_rvalid,
    input  wire            s_rready,
    output wire [DW-1:0]   s_rdata,
    output wire            s_rlast,
    output wire [1:0]      s_rresp,
    input  wire            s_awvalid,
    output wire            s_awready,
    input  wire [AW-1:0]   s_awaddr,
    input  wire [7:0]      s_awlen,
    input  wire [2:0]      s_awsize,
    input  wire [1:0]      s_awburst,
    input  wire            s_wvalid,
    output wire            s_wready,
    input  wire [DW-1:0]   s_wdata,
    input  wire [DW/8-1:0] s_wstrb,
    input  wire            s_wlast,
    output wire            s_bvalid,
    input  wire            s_bready,
    output wire [1:0]      s_bresp,

    // Master side, towards the interconnect
    output wire            m_arvalid,
    input  wire            m_arready,
    output wire [AW-1:0]   m_araddr,
    output wire [7:0]      m_arlen,
    output wire [2:0]      m_arsize,
    output wire [1:0]      m_arburst,
    input  wire            m_rvalid,
    output wire            m_rready,
    input  wire [DW-1:0]   m_rdata,
    input  wire            m_rlast,
    input  wire [1:0]      m_rresp,
    output wire            m_awvalid,
    input  wire            m_awready,
    output wire [AW-1:0]   m_awaddr,
    output wire [7:0]      m_awlen,
    output wire [2:0]      m_awsize,
    output wire [1:0]      m_awburst,
    output wire            m_wvalid,
    input  wire            m_wready,
    output wire [DW-1:0]   m_wdata,
    output wire [DW/8-1:0] m_wstrb,
    output wire            m_wlast,
    input  wire            m_bvalid,
    output wire            m_bready,
    input  wire [1:0]      m_bresp
);
    localparam AXW = AW + 8 + 3 + 2;

    axi_skid #(.W(AXW)) u_ar (
        .clk(clk), .rst(rst),
        .s_valid(s_arvalid), .s_ready(s_arready), .s_data({s_araddr, s_arlen, s_arsize, s_arburst}),
        .m_valid(m_arvalid), .m_ready(m_arready), .m_data({m_araddr, m_arlen, m_arsize, m_arburst})
    );

    axi_skid #(.W(AXW)) u_aw (
        .clk(clk), .rst(rst),
        .s_valid(s_awvalid), .s_ready(s_awready), .s_data({s_awaddr, s_awlen, s_awsize, s_awburst}),
        .m_valid(m_awvalid), .m_ready(m_awready), .m_data({m_awaddr, m_awlen, m_awsize, m_awburst})
    );

    axi_skid #(.W(DW + DW/8 + 1)) u_w (
        .clk(clk), .rst(rst),
        .s_valid(s_wvalid), .s_ready(s_wready), .s_data({s_wdata, s_wstrb, s_wlast}),
        .m_valid(m_wvalid), .m_ready(m_wready), .m_data({m_wdata, m_wstrb, m_wlast})
    );

    axi_skid #(.W(DW + 3)) u_r (
        .clk(clk), .rst(rst),
        .s_valid(m_rvalid), .s_ready(m_rready), .s_data({m_rdata, m_rlast, m_rresp}),
        .m_valid(s_rvalid), .m_ready(s_rready), .m_data({s_rdata, s_rlast, s_rresp})
    );

    axi_skid #(.W(2)) u_b (
        .clk(clk), .rst(rst),
        .s_valid(m_bvalid), .s_ready(m_bready), .s_data(m_bresp),
        .m_valid(s_bvalid), .m_ready(s_bready), .m_data(s_bresp)
    );
endmodule
