// =============================================================================
// lfsr16.sv
//
// 16-bit LFSR for pseudo random stalls in testbenches. Same taps and seed as
// the backpressure generator in sim/openeye/tb_openeye_core.v so stall
// patterns stay comparable between the two simulation trees.
// =============================================================================
`timescale 1ns / 1ps

module lfsr16 #(
    parameter [15:0] SEED = 16'hACE1
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    output reg  [15:0] q
);

    always @(posedge clk) begin
        if (rst)
            q <= SEED;
        else if (en)
            q <= {q[14:0], q[15] ^ q[13] ^ q[12] ^ q[10]};
    end

endmodule
