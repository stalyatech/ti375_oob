// =============================================================================
// tb_dsp_mac.sv
//
// Unit test of snpu_dsp_mac2 against the Efinix DSP48 simulation model (or
// the behavioural twin with -DSNPU_SIM_BEHAV). Two instances are checked:
//
//   u_head: FIRST=1, LAST=1, a stand alone block with registered output.
//   u_body: FIRST=0, LAST=0, cascade input driven by the testbench.
//
// The reference is a cycle by cycle mirror of the expected pipeline built
// from $signed products, so both lane values, weight latching through the
// clock enable, the cascade adder, 24-bit wrap and the OVFL flag are checked
// every cycle.
//
// Plusargs: +SEED=<n> random seed, +CYCLES=<n> random cycles (default 20000).
// =============================================================================
`timescale 1ns / 1ps
`include "tb_util.svh"

module tb_dsp_mac;

    reg clk = 1'b0;
    always #2.0 clk = ~clk;

    reg rst = 1'b1;

    reg  [7:0]  x = 8'd0;
    reg  [7:0]  w_lo = 8'd0;
    reg  [7:0]  w_hi = 8'd0;
    reg         w_we = 1'b0;
    reg  [47:0] casc = 48'd0;

    wire [47:0] head_o, head_casc, body_o, body_casc;
    wire        head_ovfl, body_ovfl;

    snpu_dsp_mac2 #(.FIRST(1), .LAST(1)) u_head (
        .clk(clk), .rst(rst), .x_i(x), .w_lo_i(w_lo), .w_hi_i(w_hi), .w_we_i(w_we),
        .casc_i(48'd0), .casc_o(head_casc), .o(head_o), .ovfl_o(head_ovfl)
    );

    snpu_dsp_mac2 #(.FIRST(0), .LAST(0)) u_body (
        .clk(clk), .rst(rst), .x_i(x), .w_lo_i(w_lo), .w_hi_i(w_hi), .w_we_i(w_we),
        .casc_i(casc), .casc_o(body_casc), .o(body_o), .ovfl_o(body_ovfl)
    );

    // Reference pipeline. Stage names follow the DSP: A/B sampled at the
    // same edge, P one edge later, W one edge later (adds the cascade input
    // sampled at that edge), O one edge later.
    reg signed [7:0]  ref_b_lo = 8'd0;
    reg signed [7:0]  ref_b_hi = 8'd0;
    reg signed [31:0] ref_p_lo = 0, ref_p_hi = 0;
    reg signed [31:0] ref_pp_lo = 0, ref_pp_hi = 0;
    reg signed [24:0] ref_w_lo = 0, ref_w_hi = 0;
    reg signed [24:0] ref_wh_lo = 0, ref_wh_hi = 0;
    reg signed [24:0] ref_o_lo = 0, ref_o_hi = 0;
    reg               ref_ovfl_w = 1'b0, ref_ovfl_o_h = 1'b0, ref_ovfl_w_h = 1'b0;
    reg               ref_ovfl_body = 1'b0;

    reg signed [7:0] eff_lo, eff_hi;
    reg signed [24:0] sum_lo, sum_hi, sumh_lo, sumh_hi;

    always @(posedge clk) begin
        if (rst) begin
            ref_b_lo <= 0; ref_b_hi <= 0;
            ref_p_lo <= 0; ref_p_hi <= 0;
            ref_pp_lo <= 0; ref_pp_hi <= 0;
            ref_w_lo <= 0; ref_w_hi <= 0;
            ref_wh_lo <= 0; ref_wh_hi <= 0;
            ref_o_lo <= 0; ref_o_hi <= 0;
            ref_ovfl_w <= 0; ref_ovfl_w_h <= 0; ref_ovfl_o_h <= 0; ref_ovfl_body <= 0;
        end else begin
            eff_lo = w_we ? $signed(w_lo) : ref_b_lo;
            eff_hi = w_we ? $signed(w_hi) : ref_b_hi;
            if (w_we) begin
                ref_b_lo <= $signed(w_lo);
                ref_b_hi <= $signed(w_hi);
            end
            ref_p_lo  <= $signed(x) * eff_lo;
            ref_p_hi  <= $signed(x) * eff_hi;
            ref_pp_lo <= ref_p_lo;
            ref_pp_hi <= ref_p_hi;
            // body: product plus cascade lanes, 24-bit wrap, overflow flag
            sum_lo = ref_pp_lo[24:0] + {casc[23], casc[23:0]};
            sum_hi = ref_pp_hi[24:0] + {casc[47], casc[47:24]};
            ref_w_lo <= sum_lo;
            ref_w_hi <= sum_hi;
            ref_ovfl_body <= (sum_lo[24] != sum_lo[23]) | (sum_hi[24] != sum_hi[23]);
            // head: product plus zero
            sumh_lo = ref_pp_lo[24:0];
            sumh_hi = ref_pp_hi[24:0];
            ref_wh_lo <= sumh_lo;
            ref_wh_hi <= sumh_hi;
            ref_ovfl_w_h <= 1'b0;
            ref_o_lo <= ref_wh_lo;
            ref_o_hi <= ref_wh_hi;
            ref_ovfl_o_h <= ref_ovfl_w_h;
        end
    end

    integer errors = 0, checks = 0;
    integer seed = 1, cycles = 20000, i;
    reg checking = 1'b0;
    reg [47:0] exp_head, exp_body;
    reg [255:0] msg;

    // Compare on the falling edge, after the outputs of the rising edge
    // have settled.
    always @(negedge clk) begin
        if (checking) begin
            exp_head = {ref_o_hi[23:0], ref_o_lo[23:0]};
            exp_body = {ref_w_hi[23:0], ref_w_lo[23:0]};
            `TB_CHECK(head_o == exp_head, "head o mismatch")
            `TB_CHECK(head_casc == {ref_wh_hi[23:0], ref_wh_lo[23:0]}, "head casc_o mismatch")
            `TB_CHECK(head_ovfl == 1'b0, "head ovfl set")
            `TB_CHECK(body_casc == exp_body, "body casc_o mismatch")
            `TB_CHECK(body_o == exp_body, "body o (LAST=0) must equal casc_o")
            `TB_CHECK(body_ovfl == ref_ovfl_body, "body ovfl mismatch")
            if (errors == 1 && (head_o != exp_head || body_casc != exp_body))
                $display("  head_o=%h exp=%h  body_casc=%h exp=%h", head_o, exp_head, body_casc, exp_body);
        end
    end

    task drive(input [7:0] xv, input [7:0] wl, input [7:0] wh, input we, input [47:0] cv);
        begin
            @(negedge clk);
            x = xv; w_lo = wl; w_hi = wh; w_we = we; casc = cv;
        end
    endtask

    `TB_WATCHDOG("tb_dsp_mac", 400000, clk)

    initial begin
        if ($value$plusargs("SEED=%d", seed)) ;
        if ($value$plusargs("CYCLES=%d", cycles)) ;
        i = $urandom(seed);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        checking = 1'b1;

        // 1. Directed extremes with a fresh weight load each time.
        drive(8'h80, 8'h80, 8'h80, 1'b1, 48'd0);            // -128 * -128
        drive(8'h7F, 8'h80, 8'h7F, 1'b1, 48'd0);            // 127 * -128, 127 * 127
        drive(8'h80, 8'h7F, 8'h01, 1'b1, 48'd0);            // -128 * 127, -128 * 1
        drive(8'h00, 8'h55, 8'hAA, 1'b1, 48'd0);            // zero activation
        drive(8'hFF, 8'hFF, 8'h01, 1'b1, 48'd0);            // -1 * -1, -1 * 1
        repeat (6) drive(8'h01, 8'h00, 8'h00, 1'b0, 48'd0); // hold weights, x = 1

        // 2. Cascade extremes on the body: force 24-bit overflow in each lane.
        drive(8'h7F, 8'h7F, 8'h7F, 1'b1, 48'd0);
        drive(8'h7F, 8'h7F, 8'h7F, 1'b0, {24'h000000, 24'h7FFFFF}); // low lane wraps
        drive(8'h7F, 8'h7F, 8'h7F, 1'b0, {24'h7FFFFF, 24'h000000}); // high lane wraps
        drive(8'h80, 8'h7F, 8'h7F, 1'b0, {24'h800000, 24'h800000}); // both lanes wrap negative
        drive(8'h01, 8'h7F, 8'h7F, 1'b0, {24'h7FFF00, 24'h7FFF00}); // no overflow
        repeat (6) drive(8'h00, 8'h00, 8'h00, 1'b0, 48'd0);

        // 3. Random traffic, weights reloaded on about 5 percent of cycles,
        //    cascade input random every cycle.
        for (i = 0; i < cycles; i = i + 1) begin
            drive($urandom, $urandom, $urandom, ($urandom % 20) == 0, {$urandom, $urandom});
        end
        repeat (6) drive(8'h00, 8'h00, 8'h00, 1'b0, 48'd0);

        // 4. Reset in the middle of traffic: outputs must clear and the
        //    weights must read as zero until reloaded.
        drive(8'h11, 8'h22, 8'h33, 1'b1, 48'd0);
        drive(8'h44, 8'h00, 8'h00, 1'b0, 48'd0);
        @(negedge clk);
        checking = 1'b0;
        rst = 1'b1;
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        x = 8'h55; w_we = 1'b0; casc = 48'd0;
        checking = 1'b1;
        repeat (8) @(negedge clk);
        `TB_CHECK(head_o == 48'd0, "head o not zero after reset")
        `TB_CHECK(body_casc == 48'd0, "body casc_o not zero after reset")
        for (i = 0; i < 2000; i = i + 1) begin
            drive($urandom, $urandom, $urandom, ($urandom % 7) == 0, {$urandom, $urandom});
        end
        repeat (6) drive(8'h00, 8'h00, 8'h00, 1'b0, 48'd0);

        `TB_FINISH("tb_dsp_mac")
    end

endmodule
