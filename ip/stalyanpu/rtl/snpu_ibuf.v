// =============================================================================
// snpu_ibuf.v
//
// Input activation buffer: IBUF_WORDS words of 256 bits, one word per
// (pixel, channel group). Simple dual port: the fill side writes, the address
// generator reads with one cycle of latency.
// =============================================================================
`timescale 1ns / 1ps

module snpu_ibuf #(
    parameter IBUF_WORDS = 16384,
    parameter AW = 14
)(
    input  wire           clk,
    input  wire           we_i,
    input  wire [AW-1:0]  waddr_i,
    input  wire [255:0]   wdata_i,
    input  wire [AW-1:0]  raddr_i,
    output reg  [255:0]   rdata_o
);

    reg [255:0] mem [0:IBUF_WORDS-1];

    always @(posedge clk) begin
        if (we_i)
            mem[waddr_i] <= wdata_i;
        rdata_o <= mem[raddr_i];
    end

endmodule
