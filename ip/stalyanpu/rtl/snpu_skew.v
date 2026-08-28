// =============================================================================
// snpu_skew.v
//
// Triangular delay line. Lane i of the input is delayed by i cycles. The
// cascade chain needs the activation of DSP i one cycle after DSP i-1 and the
// same skew applies to the weight latch pulse, so both use this module.
// =============================================================================
`timescale 1ns / 1ps

module snpu_skew #(
    parameter N = 32,
    parameter W = 8
)(
    input  wire           clk,
    input  wire [N*W-1:0] d_i,
    output wire [N*W-1:0] d_o
);

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_lane
            if (i == 0) begin : g_pass
                assign d_o[W-1:0] = d_i[W-1:0];
            end else begin : g_delay
                reg [W-1:0] pipe [0:i-1];
                integer k;
                always @(posedge clk) begin
                    pipe[0] <= d_i[i*W +: W];
                    for (k = 1; k < i; k = k + 1)
                        pipe[k] <= pipe[k-1];
                end
                assign d_o[i*W +: W] = pipe[i-1];
            end
        end
    endgenerate

endmodule
