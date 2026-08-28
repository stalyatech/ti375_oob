// =============================================================================
// snpu_pe_chain.v
//
// One cascade chain of CHAIN_LEN DSP48 blocks. The chain computes the dot
// product of CHAIN_LEN activations with two weight vectors per cycle and
// returns the two 24-bit sums of the last block.
//
// x_i and latch_i arrive already skewed (lane i delayed by i cycles, see
// snpu_skew), so byte i of x_i and bit i of latch_i belong to DSP i at the
// cycle they are sampled. The array shares one skew line between chains.
//
// Weight pair i (bits 16*i+15 downto 16*i of the shadow) is {w_hi, w_lo}:
// w_lo drives the low lane and w_hi the high lane of DSP i.
//
// Latency: a vector sampled by the skew line at clock edge s appears on
// psum_*_o after edge s + CHAIN_LEN + 2 (CHAIN_LEN-1 cycles of skew, then
// the A, P, W and O stages of the last block). A latch pulse sampled at edge
// s takes effect for that same vector on every block of the chain.
// =============================================================================
`timescale 1ns / 1ps

module snpu_pe_chain #(
    parameter CHAIN_LEN = 32,
    parameter FILL_W    = 256
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [CHAIN_LEN*8-1:0] x_i,
    input  wire [CHAIN_LEN-1:0]   latch_i,
    input  wire                   fill_we_i,
    input  wire [3:0]             fill_sel_i,
    input  wire [FILL_W-1:0]      fill_data_i,
    output wire [23:0]            psum_lo_o,
    output wire [23:0]            psum_hi_o,
    output reg                    ovfl_o
);

    wire [CHAIN_LEN*16-1:0] w_shadow;

    snpu_wshadow #(
        .CHAIN_LEN (CHAIN_LEN),
        .FILL_W    (FILL_W)
    ) u_shadow (
        .clk         (clk),
        .fill_we_i   (fill_we_i),
        .fill_sel_i  (fill_sel_i),
        .fill_data_i (fill_data_i),
        .w_o         (w_shadow)
    );

    wire [47:0] casc [0:CHAIN_LEN];
    wire [47:0] o_last;
    wire [CHAIN_LEN-1:0] ovfl;

    assign casc[0] = 48'd0;

    genvar i;
    generate
        for (i = 0; i < CHAIN_LEN; i = i + 1) begin : g_dsp
            wire [47:0] o_blk;
            snpu_dsp_mac2 #(
                .FIRST (i == 0),
                .LAST  (i == CHAIN_LEN - 1)
            ) u_mac (
                .clk    (clk),
                .rst    (rst),
                .x_i    (x_i[i*8 +: 8]),
                .w_lo_i (w_shadow[i*16 +: 8]),
                .w_hi_i (w_shadow[i*16 + 8 +: 8]),
                .w_we_i (latch_i[i]),
                .casc_i (casc[i]),
                .casc_o (casc[i+1]),
                .o      (o_blk),
                .ovfl_o (ovfl[i])
            );
            if (i == CHAIN_LEN - 1) begin : g_tail
                assign o_last = o_blk;
            end
        end
    endgenerate

    assign psum_lo_o = o_last[23:0];
    assign psum_hi_o = o_last[47:24];

    always @(posedge clk) begin
        if (rst)
            ovfl_o <= 1'b0;
        else
            ovfl_o <= |ovfl;
    end

endmodule
