// =============================================================================
// axi_err_slave.v
//
// An AXI4 slave with nothing behind it. Every write is accepted, its data is
// drained and it completes with DECERR; every read returns ARLEN+1 beats of
// zero data with DECERR and RLAST on the final beat. IDs are echoed.
//
// Terminates the soft FCU SoC's AXI-A port. The SD host and Ethernet MAC it
// used to reach now belong to the hard SoC, so a NuttX build that still
// enables those drivers takes a bus error at its first access, which points
// straight at the misconfiguration. Leaving the port unconnected instead
// would hang the FCU on its first stray access.
//
// One transaction in flight per direction.
//
// Language: Verilog 2001. Reset: active-high synchronous.
// =============================================================================
`timescale 1ns / 1ps

module axi_err_slave #(
    parameter IDW = 8,
    parameter DW  = 32
) (
    input  wire           clk,
    input  wire           rst,

    input  wire           awvalid,
    output wire           awready,
    input  wire [IDW-1:0] awid,
    input  wire           wvalid,
    output wire           wready,
    input  wire           wlast,
    output wire           bvalid,
    input  wire           bready,
    output reg  [IDW-1:0] bid,
    output wire [1:0]     bresp,

    input  wire           arvalid,
    output wire           arready,
    input  wire [IDW-1:0] arid,
    input  wire [7:0]     arlen,
    output wire           rvalid,
    input  wire           rready,
    output reg  [IDW-1:0] rid,
    output wire [DW-1:0]  rdata,
    output wire [1:0]     rresp,
    output wire           rlast
);

    localparam [1:0] DECERR = 2'b11;

    // ---------------------------------------------------------------- writes
    localparam [1:0] W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;
    reg [1:0] w_state;

    assign awready = (w_state == W_IDLE);
    assign wready  = (w_state == W_DATA);
    assign bvalid  = (w_state == W_RESP);
    assign bresp   = DECERR;

    always @(posedge clk) begin
        if (rst) begin
            w_state <= W_IDLE;
            bid     <= {IDW{1'b0}};
        end else begin
            case (w_state)
                W_IDLE: if (awvalid) begin
                            bid     <= awid;
                            w_state <= W_DATA;
                        end
                W_DATA: if (wvalid && wlast)
                            w_state <= W_RESP;
                W_RESP: if (bready)
                            w_state <= W_IDLE;
                default:    w_state <= W_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------------------- reads
    reg       r_busy;
    reg [7:0] r_left;       // beats still to send, minus one

    assign arready = ~r_busy;
    assign rvalid  = r_busy;
    assign rdata   = {DW{1'b0}};
    assign rresp   = DECERR;
    assign rlast   = r_busy & (r_left == 8'd0);

    always @(posedge clk) begin
        if (rst) begin
            r_busy <= 1'b0;
            r_left <= 8'd0;
            rid    <= {IDW{1'b0}};
        end else if (!r_busy) begin
            if (arvalid) begin
                r_busy <= 1'b1;
                r_left <= arlen;
                rid    <= arid;
            end
        end else if (rready) begin
            if (r_left == 8'd0)
                r_busy <= 1'b0;
            else
                r_left <= r_left - 8'd1;
        end
    end

endmodule
