// =============================================================================
// snpu_syn_chain.v
//
// Synthesis wrapper of a few PE chains. It exists to check how long a DSP48
// cascade the placer accepts and what the array alone closes at, without
// the rest of the engine. Inputs come from a shift register fed by one pin
// and the outputs fold into one pin, as in snpu_syn_conv.
// =============================================================================
`timescale 1ns / 1ps

module snpu_syn_chain #(
    parameter N_CHAIN   = 32,
    parameter CHAIN_LEN = 32,
    parameter FILL_W    = 256,
    parameter P_W       = 10
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

    localparam O_X     = 0;
    localparam O_V     = O_X + CHAIN_LEN * 8;
    localparam O_FIRST = O_V + 1;
    localparam O_LAST  = O_FIRST + 1;
    localparam O_TEND  = O_LAST + 1;
    localparam O_P     = O_TEND + 1;
    localparam O_LATCH = O_P + P_W;
    localparam O_FWE   = O_LATCH + 1;
    localparam O_FCH   = O_FWE + 1;
    localparam O_FSEL  = O_FCH + 8;
    localparam O_FDATA = O_FSEL + 4;
    localparam IN_W    = O_FDATA + FILL_W;

    reg [IN_W-1:0] sr;
    always @(posedge clk)
        sr <= {sr[IN_W-2:0], sin ^ sr[IN_W-1] ^ sr[IN_W/2]};

    wire [N_CHAIN*48-1:0] psum;
    wire v, first, last, tend, ovfl;
    wire [P_W-1:0] p;

    snpu_pe_array #(.N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .FILL_W(FILL_W), .P_W(P_W)) u_array (
        .clk(clk), .rst(rst),
        .x_i(sr[O_X +: CHAIN_LEN*8]),
        .v_i(sr[O_V]), .first_i(sr[O_FIRST]), .last_i(sr[O_LAST]), .tile_end_i(sr[O_TEND]),
        .p_i(sr[O_P +: P_W]), .latch_i(sr[O_LATCH]),
        .fill_we_i(sr[O_FWE]), .fill_chain_i(sr[O_FCH +: 8]), .fill_sel_i(sr[O_FSEL +: 4]),
        .fill_data_i(sr[O_FDATA +: FILL_W]),
        .psum_o(psum), .v_o(v), .first_o(first), .last_o(last), .tile_end_o(tend), .p_o(p), .ovfl_o(ovfl)
    );

    localparam OUT_W = N_CHAIN * 48 + 5 + P_W;
    localparam FOLDS = (OUT_W + 31) / 32;
    wire [FOLDS*32-1:0] outs = {{(FOLDS*32-OUT_W){1'b0}}, psum, v, first, last, tend, ovfl, p};
    reg [FOLDS-1:0] fold;
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < FOLDS; i = i + 1)
            fold[i] <= ^outs[i*32 +: 32];
        sout <= ^fold;
    end

endmodule
