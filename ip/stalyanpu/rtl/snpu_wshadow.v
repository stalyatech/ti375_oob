// =============================================================================
// snpu_wshadow.v
//
// Shadow weight registers of one chain. The weight FIFO fills them in words
// of FILL_W bits (FILL_W/16 weight pairs per word) while the chain computes
// with the weights already latched in the DSP B registers. A latch pulse
// then copies the shadow into the DSPs, one DSP per cycle along the chain.
//
// The fill of the next pass may start once every DSP of the chain has seen
// its latch pulse, which is CHAIN_LEN cycles after the pulse entered.
// =============================================================================
`timescale 1ns / 1ps

module snpu_wshadow #(
    parameter CHAIN_LEN = 32,
    parameter FILL_W    = 256
)(
    input  wire                    clk,
    input  wire                    fill_we_i,
    input  wire [3:0]              fill_sel_i,
    input  wire [FILL_W-1:0]       fill_data_i,
    output wire [CHAIN_LEN*16-1:0] w_o
);

    localparam PAIRS_PER_WORD = FILL_W / 16;

    reg [15:0] shadow [0:CHAIN_LEN-1];

    integer j;
    always @(posedge clk) begin
        if (fill_we_i) begin
            for (j = 0; j < PAIRS_PER_WORD; j = j + 1)
                if (fill_sel_i * PAIRS_PER_WORD + j < CHAIN_LEN)
                    shadow[fill_sel_i * PAIRS_PER_WORD + j] <= fill_data_i[j*16 +: 16];
        end
    end

    genvar i;
    generate
        for (i = 0; i < CHAIN_LEN; i = i + 1) begin : g_out
            assign w_o[i*16 +: 16] = shadow[i];
        end
    endgenerate

endmodule
