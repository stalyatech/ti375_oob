// =============================================================================
// snpu_dsp_mac2.v
//
// One Efinix DSP48 block in DUAL mode used as two INT8 multipliers with a
// shared activation. The low lane multiplies x by w_lo, the high lane
// multiplies x by w_hi. Each lane keeps a 24-bit partial sum that enters on
// casc_i and leaves on casc_o, so a column of these blocks forms a cascade
// adder for two output channels.
//
// Pipeline: x and the weights are registered in the DSP (A and B stages), the
// product is registered (P stage) and the adder output is registered (W
// stage). casc_o is the W stage, three cycles after x. With LAST=1 the O
// stage adds one more register on o.
//
// The weights live in the DSP B register. They are only reloaded while w_we_i
// is high, which makes the block weight stationary without any extra fabric
// register. The activation path never uses the clock enable.
//
// Define SNPU_SIM_BEHAV to replace the vendor primitive by a behavioural twin
// with the same timing, for faster simulation without the Efinity model.
// =============================================================================
`timescale 1ns / 1ps

module snpu_dsp_mac2 #(
    parameter FIRST = 0,
    parameter LAST  = 0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  x_i,
    input  wire [7:0]  w_lo_i,
    input  wire [7:0]  w_hi_i,
    input  wire        w_we_i,
    input  wire [47:0] casc_i,
    output wire [47:0] casc_o,
    output wire [47:0] o,
    output wire        ovfl_o
);

    // DUAL mode lane placement: the high lane multiplies A[18:8] by B[17:8],
    // the low lane multiplies A[7:0] by B[7:0]. Both lanes get the same
    // activation, sign extended to the lane width.
    wire [18:0] dsp_a = {{3{x_i[7]}}, x_i, x_i};
    wire [17:0] dsp_b = {{2{w_hi_i[7]}}, w_hi_i, w_lo_i};

`ifdef SNPU_SIM_BEHAV

    reg signed [10:0] a_hi_q;
    reg signed [7:0]  a_lo_q;
    reg signed [9:0]  b_hi_q;
    reg signed [7:0]  b_lo_q;
    reg signed [23:0] p_hi_q;
    reg signed [23:0] p_lo_q;
    reg        [47:0] w_q;
    reg        [47:0] o_q;
    reg               ovfl_w_q;
    reg               ovfl_o_q;

    wire [47:0] n_in = FIRST ? 48'd0 : casc_i;

    wire signed [24:0] sum_hi = {p_hi_q[23], p_hi_q} + {n_in[47], n_in[47:24]};
    wire signed [24:0] sum_lo = {p_lo_q[23], p_lo_q} + {n_in[23], n_in[23:0]};
    wire ovfl_w = (sum_hi[24] != sum_hi[23]) | (sum_lo[24] != sum_lo[23]);

    always @(posedge clk) begin
        if (rst) begin
            a_hi_q   <= 11'd0;
            a_lo_q   <= 8'd0;
            b_hi_q   <= 10'd0;
            b_lo_q   <= 8'd0;
            p_hi_q   <= 24'd0;
            p_lo_q   <= 24'd0;
            w_q      <= 48'd0;
            o_q      <= 48'd0;
            ovfl_w_q <= 1'b0;
            ovfl_o_q <= 1'b0;
        end else begin
            a_hi_q <= $signed(dsp_a[18:8]);
            a_lo_q <= $signed(dsp_a[7:0]);
            if (w_we_i) begin
                b_hi_q <= $signed(dsp_b[17:8]);
                b_lo_q <= $signed(dsp_b[7:0]);
            end
            p_hi_q   <= a_hi_q * b_hi_q;
            p_lo_q   <= a_lo_q * b_lo_q;
            w_q      <= {sum_hi[23:0], sum_lo[23:0]};
            ovfl_w_q <= ovfl_w;
            o_q      <= w_q;
            ovfl_o_q <= ovfl_w_q;
        end
    end

    assign casc_o = w_q;
    assign o      = LAST ? o_q : w_q;
    assign ovfl_o = LAST ? ovfl_o_q : ovfl_w_q;

`else

    generate
        if (FIRST) begin : g_head
            EFX_DSP48 #(
                .MODE("DUAL"),
                .A_REG(1), .B_REG(1), .C_REG(0), .P_REG(1), .OP_REG(0),
                .W_REG(1), .O_REG(LAST), .SHIFTER(0), .RST_SYNC(1), .SIGNED(1),
                .P_EXT("ALIGN_RIGHT"), .C_EXT("ALIGN_RIGHT"),
                .M_SEL("P"), .N_SEL("CONST0"), .W_SEL("X"), .CASCOUT_SEL("W"),
                .A_REG_USE_CE(0), .B_REG_USE_CE(1), .C_REG_USE_CE(0),
                .OP_REG_USE_CE(0), .P_REG_USE_CE(0), .W_REG_USE_CE(0), .O_REG_USE_CE(0),
                .A_REG_USE_RST(1), .B_REG_USE_RST(1), .C_REG_USE_RST(1),
                .OP_REG_USE_RST(1), .P_REG_USE_RST(1), .W_REG_USE_RST(1), .O_REG_USE_RST(1)
            ) u_dsp (
                .A(dsp_a), .B(dsp_b), .C(18'd0), .CASCIN(48'd0), .OP(2'b00),
                .SHIFT_ENA(1'b0), .CLK(clk), .CE(w_we_i), .RST(rst),
                .O(o), .CASCOUT(casc_o), .OVFL(ovfl_o)
            );
        end else begin : g_body
            EFX_DSP48 #(
                .MODE("DUAL"),
                .A_REG(1), .B_REG(1), .C_REG(0), .P_REG(1), .OP_REG(0),
                .W_REG(1), .O_REG(LAST), .SHIFTER(0), .RST_SYNC(1), .SIGNED(1),
                .P_EXT("ALIGN_RIGHT"), .C_EXT("ALIGN_RIGHT"),
                .M_SEL("P"), .N_SEL("CASCIN"), .W_SEL("X"), .CASCOUT_SEL("W"),
                .A_REG_USE_CE(0), .B_REG_USE_CE(1), .C_REG_USE_CE(0),
                .OP_REG_USE_CE(0), .P_REG_USE_CE(0), .W_REG_USE_CE(0), .O_REG_USE_CE(0),
                .A_REG_USE_RST(1), .B_REG_USE_RST(1), .C_REG_USE_RST(1),
                .OP_REG_USE_RST(1), .P_REG_USE_RST(1), .W_REG_USE_RST(1), .O_REG_USE_RST(1)
            ) u_dsp (
                .A(dsp_a), .B(dsp_b), .C(18'd0), .CASCIN(casc_i), .OP(2'b00),
                .SHIFT_ENA(1'b0), .CLK(clk), .CE(w_we_i), .RST(rst),
                .O(o), .CASCOUT(casc_o), .OVFL(ovfl_o)
            );
        end
    endgenerate

`endif

endmodule
