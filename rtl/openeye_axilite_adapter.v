// =============================================================================
// openeye_axilite_adapter.v  —  AXI4 (full) slave  ->  AXI4-Lite master bridge
//
// Bridges a full AXI4 master (the Hard SoC EfxSapphireHpSoc_slb fabric AXI master,
// once exposed via Efinity) down to an AXI4-Lite slave such as OpenEye's `cfg_reg`
// (open_eye_mt_v1_0), the DNN-DMA control regs, or the codec stub.
//
// Design (FMU DNN control plane, Faz 2):
//   - SINGLE outstanding transaction, SINGLE beat (control-register MMIO). Bursts
//     into a control window are not expected; awlen/arlen are ignored and a single
//     beat is forwarded (s_wlast/s_rlast are driven as 1).
//   - DATA_WIDTH = 32 (must match the Sapphire axiA master). ID/prot captured and
//     reflected on the response channels.
//   - Clean 5-state write / 4-state read FSMs (correct by inspection; to be
//     simulated against OpenEye cocotb once the Hard SoC master is regenerated).
//
// PARAMS: set ID_WIDTH / ADDR_WIDTH to match the regenerated Hard SoC master.
// Language: Verilog 2001. Reset: active-low async.
// =============================================================================
`timescale 1ns / 1ps

module openeye_axilite_adapter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---------------- AXI4 (full) SLAVE  (from CPU master) ----------------
    input  wire [ID_WIDTH-1:0]     s_awid,
    input  wire [ADDR_WIDTH-1:0]   s_awaddr,
    input  wire [7:0]              s_awlen,   // ignored (single beat)
    input  wire [2:0]              s_awsize,  // ignored
    input  wire [1:0]              s_awburst, // ignored
    input  wire                    s_awvalid,
    output wire                    s_awready,
    input  wire [DATA_WIDTH-1:0]   s_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_wstrb,
    input  wire                    s_wlast,   // ignored (single beat)
    input  wire                    s_wvalid,
    output wire                    s_wready,
    output wire [ID_WIDTH-1:0]     s_bid,
    output wire [1:0]              s_bresp,
    output wire                    s_bvalid,
    input  wire                    s_bready,
    input  wire [ID_WIDTH-1:0]     s_arid,
    input  wire [ADDR_WIDTH-1:0]   s_araddr,
    input  wire [7:0]              s_arlen,   // ignored
    input  wire [2:0]              s_arsize,  // ignored
    input  wire [1:0]              s_arburst, // ignored
    input  wire                    s_arvalid,
    output wire                    s_arready,
    output wire [ID_WIDTH-1:0]     s_rid,
    output wire [DATA_WIDTH-1:0]   s_rdata,
    output wire [1:0]              s_rresp,
    output wire                    s_rlast,
    output wire                    s_rvalid,
    input  wire                    s_rready,

    // ---------------- AXI4-Lite MASTER  (to device cfg_reg) ----------------
    output wire [ADDR_WIDTH-1:0]   m_awaddr,
    output wire [2:0]              m_awprot,
    output wire                    m_awvalid,
    input  wire                    m_awready,
    output wire [DATA_WIDTH-1:0]   m_wdata,
    output wire [DATA_WIDTH/8-1:0] m_wstrb,
    output wire                    m_wvalid,
    input  wire                    m_wready,
    input  wire [1:0]              m_bresp,
    input  wire                    m_bvalid,
    output wire                    m_bready,
    output wire [ADDR_WIDTH-1:0]   m_araddr,
    output wire [2:0]              m_arprot,
    output wire                    m_arvalid,
    input  wire                    m_arready,
    input  wire [DATA_WIDTH-1:0]   m_rdata,
    input  wire [1:0]              m_rresp,
    input  wire                    m_rvalid,
    output wire                    m_rready
);

    // ============================= Write channel =============================
    localparam [2:0] WS_IDLE = 3'd0, // accept AW
                     WS_DATA = 3'd1, // accept W
                     WS_REQ  = 3'd2, // drive Lite AW+W
                     WS_RESP = 3'd3, // wait Lite B
                     WS_BACK = 3'd4; // return B to master
    reg [2:0]              wstate;
    reg [ADDR_WIDTH-1:0]   awaddr_q;
    reg [ID_WIDTH-1:0]     awid_q;
    reg [DATA_WIDTH-1:0]   wdata_q;
    reg [DATA_WIDTH/8-1:0] wstrb_q;
    reg [1:0]              bresp_q;
    reg                    aw_acc, w_acc; // Lite AW / W accepted flags

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= WS_IDLE; aw_acc <= 1'b0; w_acc <= 1'b0;
            awaddr_q <= {ADDR_WIDTH{1'b0}}; awid_q <= {ID_WIDTH{1'b0}};
            wdata_q  <= {DATA_WIDTH{1'b0}}; wstrb_q <= {(DATA_WIDTH/8){1'b0}};
            bresp_q  <= 2'b00;
        end else begin
            case (wstate)
                WS_IDLE: if (s_awvalid) begin
                             awaddr_q <= s_awaddr; awid_q <= s_awid;
                             wstate <= WS_DATA;
                         end
                WS_DATA: if (s_wvalid) begin
                             wdata_q <= s_wdata; wstrb_q <= s_wstrb;
                             aw_acc <= 1'b0; w_acc <= 1'b0;
                             wstate <= WS_REQ;
                         end
                WS_REQ: begin
                    if (m_awvalid & m_awready) aw_acc <= 1'b1;
                    if (m_wvalid  & m_wready ) w_acc  <= 1'b1;
                    if ((aw_acc | (m_awvalid & m_awready)) &&
                        (w_acc  | (m_wvalid  & m_wready )))
                        wstate <= WS_RESP;
                end
                WS_RESP: if (m_bvalid) begin
                             bresp_q <= m_bresp;
                             wstate  <= WS_BACK;
                         end
                WS_BACK: if (s_bready) wstate <= WS_IDLE;
                default: wstate <= WS_IDLE;
            endcase
        end
    end

    assign s_awready = (wstate == WS_IDLE);
    assign s_wready  = (wstate == WS_DATA);
    assign m_awaddr  = awaddr_q;
    assign m_awprot  = 3'b000;
    assign m_awvalid = (wstate == WS_REQ) & ~aw_acc;
    assign m_wdata   = wdata_q;
    assign m_wstrb   = wstrb_q;
    assign m_wvalid  = (wstate == WS_REQ) & ~w_acc;
    assign m_bready  = (wstate == WS_RESP);
    assign s_bid     = awid_q;
    assign s_bresp   = bresp_q;
    assign s_bvalid  = (wstate == WS_BACK);

    // ============================== Read channel =============================
    localparam [1:0] RS_IDLE = 2'd0, // accept AR
                     RS_REQ  = 2'd1, // drive Lite AR
                     RS_WAIT = 2'd2, // wait Lite R
                     RS_BACK = 2'd3; // return R to master
    reg [1:0]            rstate;
    reg [ADDR_WIDTH-1:0] araddr_q;
    reg [ID_WIDTH-1:0]   arid_q;
    reg [DATA_WIDTH-1:0] rdata_q;
    reg [1:0]            rresp_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= RS_IDLE;
            araddr_q <= {ADDR_WIDTH{1'b0}}; arid_q <= {ID_WIDTH{1'b0}};
            rdata_q  <= {DATA_WIDTH{1'b0}}; rresp_q <= 2'b00;
        end else begin
            case (rstate)
                RS_IDLE: if (s_arvalid) begin
                             araddr_q <= s_araddr; arid_q <= s_arid;
                             rstate <= RS_REQ;
                         end
                RS_REQ:  if (m_arready) rstate <= RS_WAIT;
                RS_WAIT: if (m_rvalid) begin
                             rdata_q <= m_rdata; rresp_q <= m_rresp;
                             rstate  <= RS_BACK;
                         end
                RS_BACK: if (s_rready) rstate <= RS_IDLE;
                default: rstate <= RS_IDLE;
            endcase
        end
    end

    assign s_arready = (rstate == RS_IDLE);
    assign m_araddr  = araddr_q;
    assign m_arprot  = 3'b000;
    assign m_arvalid = (rstate == RS_REQ);
    assign m_rready  = (rstate == RS_WAIT);
    assign s_rid     = arid_q;
    assign s_rdata   = rdata_q;
    assign s_rresp   = rresp_q;
    assign s_rlast   = 1'b1;              // single beat
    assign s_rvalid  = (rstate == RS_BACK);

endmodule
