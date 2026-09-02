// =============================================================================
// tb_pe_chain.sv
//
// Unit test of snpu_pe_chain with the skew lines in front of it, the way the
// array will use it. Random activation vectors stream through the chain
// while the testbench keeps a delayed queue of the expected dot products.
// Weight fills and latch pulses happen while data flows, so the test also
// covers the pass boundary: the vector sampled together with the latch pulse
// is the first one computed with the new weights.
//
// Parameters: CHAIN_LEN (default 32), CASC_LEN (default 8). Override with
// -Ptb_pe_chain.CHAIN_LEN=16 for the reduced geometry.
// Plusargs: +SEED=<n>, +VECTORS=<n> vectors per pass (default 400),
// +PASSES=<n> weight passes (default 8).
// =============================================================================
`timescale 1ns / 1ps
`include "tb_util.svh"

module tb_pe_chain;

    parameter CHAIN_LEN = 32;
    parameter FILL_W    = 256;
    parameter CASC_LEN  = 8;

    localparam N_SEG  = CHAIN_LEN / CASC_LEN;
    localparam LEVELS = (N_SEG <= 1) ? 0 : (N_SEG <= 2) ? 1 : (N_SEG <= 4) ? 2 : (N_SEG <= 8) ? 3 : 4;
    localparam LAT    = CHAIN_LEN + 2 + LEVELS;
    localparam NWORDS = (CHAIN_LEN * 16 + FILL_W - 1) / FILL_W;
    localparam PAIRS  = FILL_W / 16;

    reg clk = 1'b0;
    always #2.0 clk = ~clk;
    reg rst = 1'b1;

    reg  [CHAIN_LEN*8-1:0] x_flat = 0;
    reg                    latch = 1'b0;
    reg                    fill_we = 1'b0;
    reg  [3:0]             fill_sel = 4'd0;
    reg  [FILL_W-1:0]      fill_data = 0;

    wire [CHAIN_LEN*8-1:0] x_skew;
    wire [CHAIN_LEN-1:0]   latch_skew;
    wire [23:0]            psum_lo, psum_hi;
    wire                   ovfl;

    snpu_skew #(.N(CHAIN_LEN), .W(8)) u_skew_x (
        .clk(clk), .d_i(x_flat), .d_o(x_skew)
    );

    snpu_skew #(.N(CHAIN_LEN), .W(1)) u_skew_latch (
        .clk(clk), .d_i({CHAIN_LEN{latch}}), .d_o(latch_skew)
    );

    snpu_pe_chain #(.CHAIN_LEN(CHAIN_LEN), .FILL_W(FILL_W), .CASC_LEN(CASC_LEN)) u_dut (
        .clk(clk), .rst(rst),
        .x_i(x_skew), .latch_i(latch_skew),
        .fill_we_i(fill_we), .fill_sel_i(fill_sel), .fill_data_i(fill_data),
        .psum_lo_o(psum_lo), .psum_hi_o(psum_hi), .ovfl_o(ovfl)
    );

    // Testbench copies of the shadow (what the fill wrote) and of the
    // weights in effect inside the DSPs.
    reg signed [7:0] sh_lo [0:CHAIN_LEN-1];
    reg signed [7:0] sh_hi [0:CHAIN_LEN-1];
    reg signed [7:0] cur_lo [0:CHAIN_LEN-1];
    reg signed [7:0] cur_hi [0:CHAIN_LEN-1];

    // Expected values travel through a delay line of LAT+1 entries so that
    // entry LAT holds the sum for the vector sampled LAT edges ago.
    reg signed [23:0] exp_lo [0:LAT];
    reg signed [23:0] exp_hi [0:LAT];
    reg               exp_v  [0:LAT];

    integer errors = 0, checks = 0;
    integer seed = 1, vectors = 400, passes = 8;
    integer i, k, p, v;
    reg signed [23:0] acc_lo, acc_hi;
    reg signed [7:0] wl, wh;
    reg checking = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k <= LAT; k = k + 1) begin
                exp_lo[k] <= 0; exp_hi[k] <= 0; exp_v[k] <= 1'b0;
            end
        end else begin
            acc_lo = 0;
            acc_hi = 0;
            for (k = 0; k < CHAIN_LEN; k = k + 1) begin
                wl = latch ? sh_lo[k] : cur_lo[k];
                wh = latch ? sh_hi[k] : cur_hi[k];
                acc_lo = acc_lo + $signed(x_flat[k*8 +: 8]) * wl;
                acc_hi = acc_hi + $signed(x_flat[k*8 +: 8]) * wh;
                if (latch) begin
                    cur_lo[k] <= sh_lo[k];
                    cur_hi[k] <= sh_hi[k];
                end
            end
            exp_lo[0] <= acc_lo;
            exp_hi[0] <= acc_hi;
            exp_v[0]  <= checking;
            for (k = 1; k <= LAT; k = k + 1) begin
                exp_lo[k] <= exp_lo[k-1];
                exp_hi[k] <= exp_hi[k-1];
                exp_v[k]  <= exp_v[k-1];
            end
        end
    end

    always @(negedge clk) begin
        if (exp_v[LAT]) begin
            `TB_CHECK(psum_lo == exp_lo[LAT], "psum_lo mismatch")
            `TB_CHECK(psum_hi == exp_hi[LAT], "psum_hi mismatch")
            `TB_CHECK(ovfl == 1'b0, "ovfl set")
            if (errors == 1 && (psum_lo != exp_lo[LAT] || psum_hi != exp_hi[LAT]))
                $display("  psum_lo=%h exp=%h  psum_hi=%h exp=%h", psum_lo, exp_lo[LAT], psum_hi, exp_hi[LAT]);
        end
    end

    // Fill the shadow with the testbench copy, one fill word per cycle.
    task fill_shadow;
        integer w, j;
        begin
            for (w = 0; w < NWORDS; w = w + 1) begin
                @(negedge clk);
                fill_data = 0;
                for (j = 0; j < PAIRS; j = j + 1)
                    if (w * PAIRS + j < CHAIN_LEN)
                        fill_data[j*16 +: 16] = {sh_hi[w*PAIRS+j], sh_lo[w*PAIRS+j]};
                fill_sel = w[3:0];
                fill_we = 1'b1;
            end
            @(negedge clk);
            fill_we = 1'b0;
        end
    endtask

    task new_weights(input integer mode);
        integer j;
        begin
            for (j = 0; j < CHAIN_LEN; j = j + 1) begin
                case (mode)
                    0: begin sh_lo[j] = 8'h80; sh_hi[j] = 8'h80; end
                    1: begin sh_lo[j] = 8'h7F; sh_hi[j] = 8'h80; end
                    default: begin sh_lo[j] = $urandom; sh_hi[j] = $urandom; end
                endcase
            end
        end
    endtask

    task drive_vector(input integer mode);
        integer j;
        begin
            @(negedge clk);
            for (j = 0; j < CHAIN_LEN; j = j + 1) begin
                case (mode)
                    0: x_flat[j*8 +: 8] = 8'h80;
                    1: x_flat[j*8 +: 8] = 8'h7F;
                    default: x_flat[j*8 +: 8] = $urandom;
                endcase
            end
        end
    endtask

    `TB_WATCHDOG("tb_pe_chain", 2000000, clk)

    initial begin
        if ($value$plusargs("SEED=%d", seed)) ;
        if ($value$plusargs("VECTORS=%d", vectors)) ;
        if ($value$plusargs("PASSES=%d", passes)) ;
        i = $urandom(seed);
        for (k = 0; k < CHAIN_LEN; k = k + 1) begin
            cur_lo[k] = 0; cur_hi[k] = 0; sh_lo[k] = 0; sh_hi[k] = 0;
        end

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);
        checking = 1'b1;

        // Zero weights: the chain must output zero for anything.
        for (v = 0; v < 8; v = v + 1) drive_vector(2);

        for (p = 0; p < passes; p = p + 1) begin
            // Pass 0 and 1 use the extreme weights, later passes random.
            new_weights(p < 2 ? p : 2);
            fill_shadow();
            @(negedge clk);
            // Latch pulse together with the first vector of the pass.
            latch = 1'b1;
            for (v = 0; v < vectors; v = v + 1) begin
                drive_vector(p < 2 ? p : ((v % 13 == 0) ? 0 : ((v % 17 == 0) ? 1 : 2)));
                if (v == 0) latch = 1'b0;
            end
            // The shadow may only be refilled once the last DSP has latched.
            // Streaming continues meanwhile with the old weights.
            repeat (CHAIN_LEN + 2) drive_vector(2);
        end

        repeat (LAT + 4) drive_vector(2);
        checking = 1'b0;
        repeat (LAT + 4) @(negedge clk);

        `TB_FINISH("tb_pe_chain")
    end

endmodule
