// =============================================================================
// snpu_pe_array.v
//
// N_CHAIN cascade chains behind shared skew lines. Each cycle the array
// takes one activation vector of CHAIN_LEN bytes and, LAT cycles
// later, delivers 2 * N_CHAIN partial sums of 24 bits together with the
// side band (valid, first, last, pixel index) delayed by the same amount.
//
// The weight shadow of every chain is filled through one shared port: the
// word fill_data_i goes to chain fill_chain_i, half fill_sel_i. A latch
// pulse on latch_i copies every shadow into the DSP registers, skewed along
// the chains like the data, so it belongs to the vector presented with it.
// =============================================================================
`timescale 1ns / 1ps

module snpu_pe_array #(
    parameter N_CHAIN   = 32,
    parameter CHAIN_LEN = 32,
    parameter FILL_W    = 256,
    parameter P_W       = 10,
    parameter SKEW_COPIES = 1,
    parameter CASC_LEN  = 8
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire [CHAIN_LEN*8-1:0]   x_i,
    input  wire                     v_i,
    input  wire                     first_i,
    input  wire                     last_i,
    input  wire                     tile_end_i,
    input  wire [P_W-1:0]           p_i,
    input  wire                     latch_i,
    input  wire                     fill_we_i,
    input  wire [7:0]               fill_chain_i,
    input  wire [3:0]               fill_sel_i,
    input  wire [FILL_W-1:0]        fill_data_i,
    output wire [N_CHAIN*48-1:0]    psum_o,
    output wire                     v_o,
    output wire                     first_o,
    output wire                     last_o,
    output wire                     tile_end_o,
    output wire [P_W-1:0]           p_o,
    output wire                     ovfl_o
);

    // Chain latency: skew, the four DSP stages, then one register per
    // level of the cascade adder tree (see snpu_pe_chain).
    localparam N_SEG  = CHAIN_LEN / CASC_LEN;
    localparam LEVELS = (N_SEG <= 1) ? 0 : (N_SEG <= 2) ? 1 : (N_SEG <= 4) ? 2 : (N_SEG <= 8) ? 3 : 4;
    localparam LAT = CHAIN_LEN + 2 + LEVELS;

    // Skew lines. Several copies of the data line cut the fanout into the
    // chains; each copy serves N_CHAIN / SKEW_COPIES chains.
    wire [CHAIN_LEN*8-1:0] x_skew [0:SKEW_COPIES-1];
    wire [CHAIN_LEN-1:0]   latch_skew;

    genvar s;
    generate
        for (s = 0; s < SKEW_COPIES; s = s + 1) begin : g_skew
            snpu_skew #(.N(CHAIN_LEN), .W(8)) u_skew_x (
                .clk(clk), .d_i(x_i), .d_o(x_skew[s])
            );
        end
    endgenerate

    snpu_skew #(.N(CHAIN_LEN), .W(1)) u_skew_latch (
        .clk(clk), .d_i({CHAIN_LEN{latch_i}}), .d_o(latch_skew)
    );

    wire [N_CHAIN-1:0] ovfl;

    genvar c;
    generate
        for (c = 0; c < N_CHAIN; c = c + 1) begin : g_chain
            wire [23:0] lo, hi;
            snpu_pe_chain #(.CHAIN_LEN(CHAIN_LEN), .FILL_W(FILL_W), .CASC_LEN(CASC_LEN)) u_chain (
                .clk         (clk),
                .rst         (rst),
                .x_i         (x_skew[c / (N_CHAIN / SKEW_COPIES)]),
                .latch_i     (latch_skew),
                .fill_we_i   (fill_we_i && (fill_chain_i == c)),
                .fill_sel_i  (fill_sel_i),
                .fill_data_i (fill_data_i),
                .psum_lo_o   (lo),
                .psum_hi_o   (hi),
                .ovfl_o      (ovfl[c])
            );
            assign psum_o[c*48 +: 48] = {hi, lo};
        end
    endgenerate

    // Side band delay line matching the chain latency: a vector sampled at
    // edge s produces its sums after edge s + LAT, so the side band needs
    // LAT + 1 registers.
    reg [P_W+3:0] side [0:LAT];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i <= LAT; i = i + 1)
                side[i] <= {(P_W+4){1'b0}};
        end else begin
            side[0] <= {p_i, tile_end_i, last_i, first_i, v_i};
            for (i = 1; i <= LAT; i = i + 1)
                side[i] <= side[i-1];
        end
    end

    assign v_o        = side[LAT][0];
    assign first_o    = side[LAT][1];
    assign last_o     = side[LAT][2];
    assign tile_end_o = side[LAT][3];
    assign p_o        = side[LAT][P_W+3:4];

    reg ovfl_q;
    always @(posedge clk) ovfl_q <= |ovfl;
    assign ovfl_o = ovfl_q;

endmodule
