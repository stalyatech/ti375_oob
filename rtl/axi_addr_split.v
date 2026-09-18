// =============================================================================
// axi_addr_split.v
//
// Routes one AXI4 master to one of two slaves by address. Transactions whose
// address matches (addr & MATCH_MASK) == MATCH_BASE go to slave 1, everything
// else to slave 0.
//
// Used on the hard SoC's AXI-A port: slave 0 is the soft logic block with the
// SoC's own peripherals, slave 1 is the AXI switch in front of the SD host and
// the Ethernet MAC register files.
//
// This bus carries register traffic, so the router favours simplicity and
// timing over throughput. Reads and writes are independent, but each allows
// one transaction in flight. The address phase is registered, which keeps the
// hard block's AXI pins from driving a combinational path through the address
// decode into the downstream ready logic. W, B and R pass through with only a
// select gate in the way.
//
// Write data is accepted only after the chosen slave has taken the address.
// AXI lets a slave take data before its address, so if beats were forwarded
// while the address was still pending, such a slave could swallow WLAST before
// the state machine reached W_DATA, and the router would then wait for a WLAST
// that never comes. Holding WREADY low until then is legal: a slave may wait
// for the address before accepting data, and the master may not wait for
// WREADY before raising AWVALID, so it cannot deadlock the other way either.
//
// No ID signals: the hard SoC's AXI-A port has none, and with one transaction
// per direction the order is already fixed.
//
// Language: Verilog 2001. Reset: active-high synchronous.
// =============================================================================
`timescale 1ns / 1ps

module axi_addr_split #(
    parameter        AW         = 32,
    parameter        DW         = 32,
    parameter [31:0] MATCH_MASK = 32'hFE00_0000,
    parameter [31:0] MATCH_BASE = 32'hEA00_0000
) (
    input  wire            clk,
    input  wire            rst,

    // ------------------------------------------------------------ master side
    input  wire            m_awvalid,
    output wire            m_awready,
    input  wire [AW-1:0]   m_awaddr,
    input  wire [7:0]      m_awlen,
    input  wire [2:0]      m_awsize,
    input  wire [1:0]      m_awburst,
    input  wire            m_awlock,
    input  wire [3:0]      m_awcache,
    input  wire [2:0]      m_awprot,
    input  wire [3:0]      m_awqos,
    input  wire [3:0]      m_awregion,
    input  wire            m_wvalid,
    output wire            m_wready,
    input  wire [DW-1:0]   m_wdata,
    input  wire [DW/8-1:0] m_wstrb,
    input  wire            m_wlast,
    output wire            m_bvalid,
    input  wire            m_bready,
    output wire [1:0]      m_bresp,
    input  wire            m_arvalid,
    output wire            m_arready,
    input  wire [AW-1:0]   m_araddr,
    input  wire [7:0]      m_arlen,
    input  wire [2:0]      m_arsize,
    input  wire [1:0]      m_arburst,
    input  wire            m_arlock,
    input  wire [3:0]      m_arcache,
    input  wire [2:0]      m_arprot,
    input  wire [3:0]      m_arqos,
    input  wire [3:0]      m_arregion,
    output wire            m_rvalid,
    input  wire            m_rready,
    output wire [DW-1:0]   m_rdata,
    output wire [1:0]      m_rresp,
    output wire            m_rlast,

    // ------------------------------------------ slave side, shared payload
    // Address and write payload go to both slaves; only the valid signals
    // are steered.
    output reg  [AW-1:0]   s_awaddr,
    output reg  [7:0]      s_awlen,
    output reg  [2:0]      s_awsize,
    output reg  [1:0]      s_awburst,
    output reg             s_awlock,
    output reg  [3:0]      s_awcache,
    output reg  [2:0]      s_awprot,
    output reg  [3:0]      s_awqos,
    output reg  [3:0]      s_awregion,
    output wire [DW-1:0]   s_wdata,
    output wire [DW/8-1:0] s_wstrb,
    output wire            s_wlast,
    output reg  [AW-1:0]   s_araddr,
    output reg  [7:0]      s_arlen,
    output reg  [2:0]      s_arsize,
    output reg  [1:0]      s_arburst,
    output reg             s_arlock,
    output reg  [3:0]      s_arcache,
    output reg  [2:0]      s_arprot,
    output reg  [3:0]      s_arqos,
    output reg  [3:0]      s_arregion,

    // ------------------------------------------------ slave 0, the default
    output wire            s0_awvalid,
    input  wire            s0_awready,
    output wire            s0_wvalid,
    input  wire            s0_wready,
    input  wire            s0_bvalid,
    output wire            s0_bready,
    input  wire [1:0]      s0_bresp,
    output wire            s0_arvalid,
    input  wire            s0_arready,
    input  wire            s0_rvalid,
    output wire            s0_rready,
    input  wire [DW-1:0]   s0_rdata,
    input  wire [1:0]      s0_rresp,
    input  wire            s0_rlast,

    // ---------------------------------------------- slave 1, the match window
    output wire            s1_awvalid,
    input  wire            s1_awready,
    output wire            s1_wvalid,
    input  wire            s1_wready,
    input  wire            s1_bvalid,
    output wire            s1_bready,
    input  wire [1:0]      s1_bresp,
    output wire            s1_arvalid,
    input  wire            s1_arready,
    input  wire            s1_rvalid,
    output wire            s1_rready,
    input  wire [DW-1:0]   s1_rdata,
    input  wire [1:0]      s1_rresp,
    input  wire            s1_rlast
);

    wire aw_hit = ((m_awaddr & MATCH_MASK[AW-1:0]) == MATCH_BASE[AW-1:0]);
    wire ar_hit = ((m_araddr & MATCH_MASK[AW-1:0]) == MATCH_BASE[AW-1:0]);

    // ================================================================ writes
    localparam [1:0] W_IDLE = 2'd0,   // waiting for the master's address
                     W_ADDR = 2'd1,   // presenting the address to the slave
                     W_DATA = 2'd2,   // forwarding write beats up to WLAST
                     W_RESP = 2'd3;   // forwarding the write response

    reg [1:0] w_state;
    reg       w_sel;                  // 1 = slave 1

    assign m_awready = (w_state == W_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            w_state <= W_IDLE;
            w_sel   <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE:
                    if (m_awvalid) begin
                        w_sel   <= aw_hit;
                        w_state <= W_ADDR;
                    end
                W_ADDR:
                    if (w_sel ? s1_awready : s0_awready)
                        w_state <= W_DATA;
                W_DATA:
                    if (m_wvalid && m_wready && m_wlast)
                        w_state <= W_RESP;
                W_RESP:
                    if (m_bvalid && m_bready)
                        w_state <= W_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (w_state == W_IDLE && m_awvalid) begin
            s_awaddr   <= m_awaddr;
            s_awlen    <= m_awlen;
            s_awsize   <= m_awsize;
            s_awburst  <= m_awburst;
            s_awlock   <= m_awlock;
            s_awcache  <= m_awcache;
            s_awprot   <= m_awprot;
            s_awqos    <= m_awqos;
            s_awregion <= m_awregion;
        end
    end

    wire w_addr = (w_state == W_ADDR);
    wire w_data = (w_state == W_DATA);
    wire w_resp = (w_state == W_RESP);

    assign s0_awvalid = w_addr & ~w_sel;
    assign s1_awvalid = w_addr &  w_sel;

    assign s_wdata   = m_wdata;
    assign s_wstrb   = m_wstrb;
    assign s_wlast   = m_wlast;
    assign s0_wvalid = w_data & ~w_sel & m_wvalid;
    assign s1_wvalid = w_data &  w_sel & m_wvalid;
    assign m_wready  = w_data & (w_sel ? s1_wready : s0_wready);

    assign m_bvalid  = w_resp & (w_sel ? s1_bvalid : s0_bvalid);
    assign m_bresp   = w_sel ? s1_bresp : s0_bresp;
    assign s0_bready = w_resp & ~w_sel & m_bready;
    assign s1_bready = w_resp &  w_sel & m_bready;

    // ================================================================= reads
    localparam [1:0] R_IDLE = 2'd0,
                     R_ADDR = 2'd1,
                     R_DATA = 2'd2;

    reg [1:0] r_state;
    reg       r_sel;

    assign m_arready = (r_state == R_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            r_state <= R_IDLE;
            r_sel   <= 1'b0;
        end else begin
            case (r_state)
                R_IDLE:
                    if (m_arvalid) begin
                        r_sel   <= ar_hit;
                        r_state <= R_ADDR;
                    end
                R_ADDR:
                    if (r_sel ? s1_arready : s0_arready)
                        r_state <= R_DATA;
                R_DATA:
                    if (m_rvalid && m_rready && m_rlast)
                        r_state <= R_IDLE;
                default:
                    r_state <= R_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (r_state == R_IDLE && m_arvalid) begin
            s_araddr   <= m_araddr;
            s_arlen    <= m_arlen;
            s_arsize   <= m_arsize;
            s_arburst  <= m_arburst;
            s_arlock   <= m_arlock;
            s_arcache  <= m_arcache;
            s_arprot   <= m_arprot;
            s_arqos    <= m_arqos;
            s_arregion <= m_arregion;
        end
    end

    wire r_addr = (r_state == R_ADDR);
    wire r_data = (r_state == R_DATA);

    assign s0_arvalid = r_addr & ~r_sel;
    assign s1_arvalid = r_addr &  r_sel;

    assign m_rvalid  = r_data & (r_sel ? s1_rvalid : s0_rvalid);
    assign m_rdata   = r_sel ? s1_rdata : s0_rdata;
    assign m_rresp   = r_sel ? s1_rresp : s0_rresp;
    assign m_rlast   = r_sel ? s1_rlast : s0_rlast;
    assign s0_rready = r_data & ~r_sel & m_rready;
    assign s1_rready = r_data &  r_sel & m_rready;

endmodule
