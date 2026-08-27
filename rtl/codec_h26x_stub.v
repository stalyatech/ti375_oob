// =============================================================================
// codec_h26x_stub.v  —  H.264/H.265 codec pipeline-slot placeholder (Faz 4)
//
// Reserves the codec's place in the FMU vision pipeline and DEFINES the interface
// contract that a concrete H.264/H.265 decoder IP must satisfy when it is dropped
// in later. It is a functional no-op:
//   - AXI4-Lite CONTROL slave: a tiny register file (CTRL/STATUS/BITSTREAM_BASE/
//     FRAME_BASE). STATUS reads back a magic id + "idle" so software can probe that
//     the slot exists. Writes are stored but do nothing.
//   - AXI4 DDR MASTER (read bitstream / write decoded frames): tied off IDLE, so it
//     is a harmless 4th/5th master on the DDR switch until the real core replaces it.
//   - frame_ready / irq: held low (no frames produced yet).
//
// Pipeline seam:  codec `frame_ready` pulse  ->  triggers the DNN-DMA to stream the
// decoded frame into OpenEye. See docs/help and the integration handoff.
//
// Register map (AXI4-Lite, 32-bit, byte address):
//   0x00 CTRL          [0]=start (self-clears in real core), [1]=enable
//   0x04 STATUS        RO: {16'hC0DE, 8'h00, 6'b0, frame_ready, busy}  (stub: busy=0)
//   0x08 BITSTREAM_BASE  DDR byte address of the compressed input
//   0x0C FRAME_BASE      DDR byte address of the decoded output
//
// Language: Verilog 2001. Reset: active-low async.
// =============================================================================
`timescale 1ns / 1ps

module codec_h26x_stub #(
    parameter ADDR_WIDTH      = 32,   // DDR master address width
    parameter DDR_DATA_WIDTH  = 128,  // DDR master data width (matches gAXIM switch)
    parameter ID_WIDTH        = 4
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // ------------- AXI4-Lite CONTROL slave (from control fabric) -------------
    input  wire [11:0]                s_ctrl_awaddr,
    input  wire                       s_ctrl_awvalid,
    output reg                        s_ctrl_awready,
    input  wire [31:0]                s_ctrl_wdata,
    input  wire [3:0]                 s_ctrl_wstrb,
    input  wire                       s_ctrl_wvalid,
    output reg                        s_ctrl_wready,
    output reg  [1:0]                 s_ctrl_bresp,
    output reg                        s_ctrl_bvalid,
    input  wire                       s_ctrl_bready,
    input  wire [11:0]                s_ctrl_araddr,
    input  wire                       s_ctrl_arvalid,
    output reg                        s_ctrl_arready,
    output reg  [31:0]                s_ctrl_rdata,
    output reg  [1:0]                 s_ctrl_rresp,
    output reg                        s_ctrl_rvalid,
    input  wire                       s_ctrl_rready,

    // ------------- AXI4 DDR MASTER (bitstream read / frame write) ------------
    // Tied off IDLE in this stub; declared to fix the contract for the real core.
    output wire [ID_WIDTH-1:0]        m_ddr_awid,
    output wire [ADDR_WIDTH-1:0]      m_ddr_awaddr,
    output wire [7:0]                 m_ddr_awlen,
    output wire [2:0]                 m_ddr_awsize,
    output wire [1:0]                 m_ddr_awburst,
    output wire                       m_ddr_awvalid,
    input  wire                       m_ddr_awready,
    output wire [DDR_DATA_WIDTH-1:0]  m_ddr_wdata,
    output wire [DDR_DATA_WIDTH/8-1:0] m_ddr_wstrb,
    output wire                       m_ddr_wlast,
    output wire                       m_ddr_wvalid,
    input  wire                       m_ddr_wready,
    input  wire [ID_WIDTH-1:0]        m_ddr_bid,
    input  wire [1:0]                 m_ddr_bresp,
    input  wire                       m_ddr_bvalid,
    output wire                       m_ddr_bready,
    output wire [ID_WIDTH-1:0]        m_ddr_arid,
    output wire [ADDR_WIDTH-1:0]      m_ddr_araddr,
    output wire [7:0]                 m_ddr_arlen,
    output wire [2:0]                 m_ddr_arsize,
    output wire [1:0]                 m_ddr_arburst,
    output wire                       m_ddr_arvalid,
    input  wire                       m_ddr_arready,
    input  wire [ID_WIDTH-1:0]        m_ddr_rid,
    input  wire [DDR_DATA_WIDTH-1:0]  m_ddr_rdata,
    input  wire [1:0]                 m_ddr_rresp,
    input  wire                       m_ddr_rlast,
    input  wire                       m_ddr_rvalid,
    output wire                       m_ddr_rready,

    // ---------------------------- Pipeline seam ------------------------------
    output wire                       frame_ready, // pulses when a frame is ready in DDR
    output wire                       irq          // decode-done interrupt
);

    // ------------------- Control register file (AXI4-Lite) -------------------
    reg [31:0] reg_ctrl;           // 0x00
    reg [31:0] reg_bitstream_base; // 0x08
    reg [31:0] reg_frame_base;     // 0x0C
    localparam [31:0] STATUS_MAGIC = 32'hC0DE_0000; // stub: idle, no frame

    // ---- Write channel (single outstanding) ----
    reg [11:0] awaddr_q;
    reg        aw_hs, w_hs;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_ctrl_awready <= 1'b0; s_ctrl_wready <= 1'b0;
            s_ctrl_bvalid  <= 1'b0; s_ctrl_bresp  <= 2'b00;
            aw_hs <= 1'b0; w_hs <= 1'b0; awaddr_q <= 12'b0;
            reg_ctrl <= 32'b0; reg_bitstream_base <= 32'b0; reg_frame_base <= 32'b0;
        end else begin
            // accept address
            if (s_ctrl_awvalid & ~aw_hs) begin
                s_ctrl_awready <= 1'b1; awaddr_q <= s_ctrl_awaddr; aw_hs <= 1'b1;
            end else s_ctrl_awready <= 1'b0;
            // accept data
            if (s_ctrl_wvalid & ~w_hs) begin
                s_ctrl_wready <= 1'b1; w_hs <= 1'b1;
            end else s_ctrl_wready <= 1'b0;
            // commit write when both seen
            if (aw_hs & w_hs & ~s_ctrl_bvalid) begin
                case (awaddr_q[11:2])
                    10'h000: reg_ctrl           <= s_ctrl_wdata; // CTRL (start self-clears in real core)
                    10'h002: reg_bitstream_base <= s_ctrl_wdata; // 0x08
                    10'h003: reg_frame_base     <= s_ctrl_wdata; // 0x0C
                    default: ; // ignore
                endcase
                s_ctrl_bvalid <= 1'b1; s_ctrl_bresp <= 2'b00; // OKAY
                aw_hs <= 1'b0; w_hs <= 1'b0;
            end else if (s_ctrl_bvalid & s_ctrl_bready) begin
                s_ctrl_bvalid <= 1'b0;
            end
        end
    end

    // ---- Read channel (single outstanding) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_ctrl_arready <= 1'b0; s_ctrl_rvalid <= 1'b0;
            s_ctrl_rresp   <= 2'b00; s_ctrl_rdata <= 32'b0;
        end else begin
            if (s_ctrl_arvalid & ~s_ctrl_arready & ~s_ctrl_rvalid) begin
                s_ctrl_arready <= 1'b1;
                case (s_ctrl_araddr[11:2])
                    10'h000: s_ctrl_rdata <= reg_ctrl;
                    10'h001: s_ctrl_rdata <= STATUS_MAGIC;       // STATUS RO
                    10'h002: s_ctrl_rdata <= reg_bitstream_base;
                    10'h003: s_ctrl_rdata <= reg_frame_base;
                    default: s_ctrl_rdata <= 32'b0;
                endcase
                s_ctrl_rvalid <= 1'b1; s_ctrl_rresp <= 2'b00;
            end else begin
                s_ctrl_arready <= 1'b0;
                if (s_ctrl_rvalid & s_ctrl_rready) s_ctrl_rvalid <= 1'b0;
            end
        end
    end

    // ------------------- DDR master: tied off IDLE (stub) --------------------
    assign m_ddr_awid    = {ID_WIDTH{1'b0}};
    assign m_ddr_awaddr  = {ADDR_WIDTH{1'b0}};
    assign m_ddr_awlen   = 8'b0;
    assign m_ddr_awsize  = 3'b0;
    assign m_ddr_awburst = 2'b01;
    assign m_ddr_awvalid = 1'b0;
    assign m_ddr_wdata   = {DDR_DATA_WIDTH{1'b0}};
    assign m_ddr_wstrb   = {(DDR_DATA_WIDTH/8){1'b0}};
    assign m_ddr_wlast   = 1'b0;
    assign m_ddr_wvalid  = 1'b0;
    assign m_ddr_bready  = 1'b1;
    assign m_ddr_arid    = {ID_WIDTH{1'b0}};
    assign m_ddr_araddr  = {ADDR_WIDTH{1'b0}};
    assign m_ddr_arlen   = 8'b0;
    assign m_ddr_arsize  = 3'b0;
    assign m_ddr_arburst = 2'b01;
    assign m_ddr_arvalid = 1'b0;
    assign m_ddr_rready  = 1'b1;

    // --------------------------- Pipeline outputs ----------------------------
    assign frame_ready = 1'b0; // stub never produces a frame
    assign irq         = 1'b0;

endmodule
