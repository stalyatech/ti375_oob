// =============================================================================
// snpu_ep_lane.v
//
// One output channel lane of the epilogue. The lane owns its parameter RAM
// (one 64-bit entry per plane) and its copy of the activation table, and
// runs the fixed point chain
//
//     acc32 + bias -> * mult -> round -> >> shift -> + zp -> saturate
//     -> table -> residual add -> saturate
//
// as a pipeline that advances on adv_i. The parameter RAM is read with the
// stage 0 plane index and the accumulator value arrives one cycle later, so
// both meet in stage 2. The table is read in stage 5 from the stage 4
// result. Both memories are read every cycle; their addresses hold while
// the pipeline stalls, so the read data holds as well.
//
// Local stage names: s2 bias, s3 product, s4a rounding sum, s4b shift,
// s4_q quantised value, s5 table, s6 residual differences, s7 residual
// products, s8a residual rounding, s8 residual shifts, s9 residual sum,
// then the output register. Every arithmetic
// step (multiply, wide add, barrel shift, saturate) has a stage of its own
// so no stage carries two of them. The epilogue tag pipeline is two stages
// longer than the local names suggest; see snpu_epilogue for the mapping.
// =============================================================================
`timescale 1ns / 1ps

module snpu_ep_lane #(
    parameter ENTRIES = 16,
    parameter EW      = 4
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          adv_i,

    input  wire          prm_we_i,
    input  wire [EW-1:0] prm_addr_i,
    input  wire [63:0]   prm_data_i,      // {zp, shift, mult, bias}
    input  wire          lut_we_i,
    input  wire [7:0]    lut_addr_i,
    input  wire [7:0]    lut_data_i,

    input  wire          cfg_silu_i,
    input  wire          cfg_residual_i,
    input  wire [7:0]    cfg_zp_out_i,
    input  wire [7:0]    cfg_zp_res_i,
    input  wire [7:0]    cfg_zp_out2_i,
    input  wire [15:0]   cfg_res_mult_a_i,
    input  wire [7:0]    cfg_res_shift_a_i,
    input  wire [15:0]   cfg_res_mult_b_i,
    input  wire [7:0]    cfg_res_shift_b_i,

    input  wire [EW-1:0] s0_plane_i,
    input  wire [31:0]   s1_acc_i,
    input  wire [7:0]    s5_res_i,
    output reg  [7:0]    y_o
);

    // ---- memories
    reg [63:0] prm [0:ENTRIES-1];
    reg [7:0]  lut [0:255];
    reg [63:0] s1_prm;
    reg [7:0]  s5_lut;

    always @(posedge clk) begin
        if (prm_we_i)
            prm[prm_addr_i] <= prm_data_i;
        if (adv_i)
            s1_prm <= prm[s0_plane_i];
    end

    // ---- stage 2: bias
    reg signed [32:0] s2_sum;
    reg [15:0] s2_mult;
    reg [5:0]  s2_shift;
    reg [7:0]  s2_zp;
    // ---- stage 3: product
    reg signed [49:0] s3_prod;
    reg [5:0]  s3_shift;
    reg [7:0]  s3_zp;
    // ---- stage 4: quantised value
    reg [7:0]  s4_q;
    // ---- stage 5: table output and bypass
    reg [7:0]  s5_q;
    // ---- stage 6: activation byte and residual differences
    reg [7:0]  s6_y;
    reg signed [8:0] s6_da, s6_db;
    // ---- stage 7: residual products
    reg [7:0]  s7_y;
    reg signed [25:0] s7_pa, s7_pb;
    // ---- stage 8a: rounded residual terms
    reg [7:0]  s8a_y;
    reg signed [31:0] s8a_pa, s8a_pb;
    // ---- stage 8: shifted residual terms
    reg [7:0]  s8_y;
    reg signed [31:0] s8_ra, s8_rb;
    // ---- stage 9: residual sum
    reg [7:0]  s9_y;
    reg signed [31:0] s9_sum;

    // Local copies of the shared configuration. The values are static
    // during a run and fan out to every lane, so each lane holds its own
    // register to keep the distribution off the critical paths.
    reg        silu_q, residual_q;
    reg [7:0]  zp_out_q, zp_res_q, zp_out2_q;
    reg [15:0] mult_a_q, mult_b_q;
    reg [7:0]  shift_a_q, shift_b_q;
    always @(posedge clk) begin
        silu_q <= cfg_silu_i;
        residual_q <= cfg_residual_i;
        zp_out_q <= cfg_zp_out_i;
        zp_res_q <= cfg_zp_res_i;
        zp_out2_q <= cfg_zp_out2_i;
        mult_a_q <= cfg_res_mult_a_i;
        mult_b_q <= cfg_res_mult_b_i;
        shift_a_q <= cfg_res_shift_a_i;
        shift_b_q <= cfg_res_shift_b_i;
    end

    // Rounding constants of the residual shifts. The shift amounts are
    // static during a run, so the constants are registered from the
    // configuration with no enable.
    reg signed [31:0] rnd_a_q, rnd_b_q;
    always @(posedge clk) begin
        rnd_a_q <= (shift_a_q == 8'd0) ? 32'sd0 : (32'sd1 <<< (shift_a_q - 1));
        rnd_b_q <= (shift_b_q == 8'd0) ? 32'sd0 : (32'sd1 <<< (shift_b_q - 1));
    end

    // Stage 4 in three steps: 4a adds the rounding constant (a one hot
    // value at shift-1), 4b shifts, the s4_q capture adds the zero point
    // and saturates. The value fits in int8 exactly when bits 49..7 agree.
    reg signed [49:0] s4a_sum;
    reg [5:0]  s4a_shift;
    reg [7:0]  s4a_zp;
    reg signed [49:0] s4b_sh;
    reg [7:0]  s4b_zp;
    wire signed [49:0] rnd = (s3_shift == 6'd0) ? 50'sd0 : (50'sd1 <<< (s3_shift - 6'd1));
    wire signed [49:0] t = s4b_sh + $signed(s4b_zp);
    wire t_fit = (&t[49:7]) || (~|t[49:7]);
    wire [7:0] q8 = t_fit ? t[7:0] : (t[49] ? 8'h80 : 8'd127);

    // Stage 6 selects the activation byte and forms the differences, stage
    // 7 multiplies them, stage 8 rounds and shifts with the 32-bit
    // reference width, stage 9 sums and saturates.
    wire signed [7:0] y8 = silu_q ? $signed(s5_lut) : $signed(s5_q);
    wire signed [8:0] da = $signed({y8[7], y8}) - $signed({zp_out_q[7], zp_out_q});
    wire signed [8:0] db = $signed({s5_res_i[7], s5_res_i}) - $signed({zp_res_q[7], zp_res_q});
    reg signed [31:0] ra, rb, rsum;
    reg [7:0] r8;
    always @(*) begin
        ra = s8a_pa >>> shift_a_q;
        rb = s8a_pb >>> shift_b_q;
        rsum = s9_sum + $signed({{24{zp_out2_q[7]}}, zp_out2_q});
        if (rsum > 32'sd127) r8 = 8'd127;
        else if (rsum < -32'sd128) r8 = 8'h80;
        else r8 = rsum[7:0];
    end

    // Table read. Both memories are read with the pipeline enable so the
    // read data stays aligned with the stage that issued the address.
    always @(posedge clk) begin
        if (lut_we_i)
            lut[lut_addr_i] <= lut_data_i;
        if (adv_i)
            s5_lut <= lut[{~s4_q[7], s4_q[6:0]}];
    end

    // The whole chain is a data pipeline qualified by the epilogue tags, so
    // none of these registers needs a reset value.
    always @(posedge clk) begin
        if (adv_i) begin
            s2_sum   <= $signed(s1_acc_i) + $signed(s1_prm[31:0]);
            s2_mult  <= s1_prm[47:32];
            s2_shift <= s1_prm[53:48];
            s2_zp    <= s1_prm[63:56];
            s3_prod  <= s2_sum * $signed({1'b0, s2_mult});
            s3_shift <= s2_shift;
            s3_zp    <= s2_zp;
            s4a_sum  <= s3_prod + rnd;
            s4a_shift <= s3_shift;
            s4a_zp   <= s3_zp;
            s4b_sh   <= s4a_sum >>> s4a_shift;
            s4b_zp   <= s4a_zp;
            s4_q     <= q8;
            s5_q     <= s4_q;
            s6_y     <= y8;
            s6_da    <= da;
            s6_db    <= db;
            s7_y     <= s6_y;
            s7_pa    <= s6_da * $signed({1'b0, mult_a_q});
            s7_pb    <= s6_db * $signed({1'b0, mult_b_q});
            s8a_y    <= s7_y;
            s8a_pa   <= $signed({{6{s7_pa[25]}}, s7_pa}) + rnd_a_q;
            s8a_pb   <= $signed({{6{s7_pb[25]}}, s7_pb}) + rnd_b_q;
            s8_y     <= s8a_y;
            s8_ra    <= ra;
            s8_rb    <= rb;
            s9_y     <= s8_y;
            s9_sum   <= s8_ra + s8_rb;
            y_o      <= residual_q ? r8 : s9_y;
        end
    end

endmodule
