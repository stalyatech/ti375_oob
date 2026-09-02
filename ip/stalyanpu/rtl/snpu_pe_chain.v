// =============================================================================
// snpu_pe_chain.v
//
// One chain of CHAIN_LEN DSP48 blocks. The chain computes the dot product
// of CHAIN_LEN activations with two weight vectors per cycle and returns
// the two 24-bit sums.
//
// The chain is built from CHAIN_LEN / CASC_LEN hardware cascades of
// CASC_LEN blocks each. A Ti375 DSP column holds 48 blocks and a cascade
// cannot leave its column, so the placer only fits 28 cascades of 32 on the
// device; cascades of 8 place freely. The cascade sums are aligned with
// delay lines and added in a registered tree.
//
// x_i and latch_i arrive already skewed (lane i delayed by i cycles, see
// snpu_skew), so byte i of x_i and bit i of latch_i belong to DSP i at the
// cycle they are sampled. The array shares one skew line between chains.
//
// Weight pair i (bits 16*i+15 downto 16*i of the shadow) is {w_hi, w_lo}:
// w_lo drives the low lane and w_hi the high lane of DSP i.
//
// Latency: a vector sampled by the skew line at clock edge s appears on
// psum_*_o after edge s + CHAIN_LEN + 2 + LEVELS, where LEVELS is
// log2(CHAIN_LEN / CASC_LEN): CHAIN_LEN-1 cycles of skew, the A, P, W and O
// stages of the last block, then one register per tree level. A latch
// pulse sampled at edge s takes effect for that same vector on every block
// of the chain.
// =============================================================================
`timescale 1ns / 1ps

module snpu_pe_chain #(
    parameter CHAIN_LEN = 32,
    parameter FILL_W    = 256,
    parameter CASC_LEN  = 8
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

    localparam N_SEG  = CHAIN_LEN / CASC_LEN;
    localparam LEVELS = (N_SEG <= 1) ? 0 : (N_SEG <= 2) ? 1 : (N_SEG <= 4) ? 2 : (N_SEG <= 8) ? 3 : 4;

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
    wire [47:0] seg_o [0:N_SEG-1];
    wire [CHAIN_LEN-1:0] ovfl;

    assign casc[0] = 48'd0;

    genvar i;
    generate
        for (i = 0; i < CHAIN_LEN; i = i + 1) begin : g_dsp
            wire [47:0] o_blk;
            snpu_dsp_mac2 #(
                .FIRST ((i % CASC_LEN) == 0),
                .LAST  ((i % CASC_LEN) == CASC_LEN - 1)
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
            if ((i % CASC_LEN) == CASC_LEN - 1) begin : g_tail
                assign seg_o[i / CASC_LEN] = o_blk;
            end
        end
    endgenerate

    // Alignment: segment s finishes (N_SEG-1-s) * CASC_LEN cycles before the
    // last one, so it waits in a delay line of that length.
    wire [47:0] tree [0:LEVELS][0:N_SEG-1];

    genvar s, lv, n;
    generate
        for (s = 0; s < N_SEG; s = s + 1) begin : g_align
            if (s == N_SEG - 1) begin : g_direct
                assign tree[0][s] = seg_o[s];
            end else begin : g_delay
                localparam D = (N_SEG - 1 - s) * CASC_LEN;
                reg [47:0] dl [0:D-1];
                integer k;
                always @(posedge clk) begin
                    dl[0] <= seg_o[s];
                    for (k = 1; k < D; k = k + 1)
                        dl[k] <= dl[k-1];
                end
                assign tree[0][s] = dl[D-1];
            end
        end
        // Registered adder tree, the two 24-bit lanes added separately.
        for (lv = 1; lv <= LEVELS; lv = lv + 1) begin : g_level
            for (n = 0; n < (N_SEG >> lv); n = n + 1) begin : g_node
                reg [47:0] q;
                always @(posedge clk)
                    q <= {tree[lv-1][2*n][47:24] + tree[lv-1][2*n+1][47:24],
                          tree[lv-1][2*n][23:0]  + tree[lv-1][2*n+1][23:0]};
                assign tree[lv][n] = q;
            end
        end
    endgenerate

    assign psum_lo_o = tree[LEVELS][0][23:0];
    assign psum_hi_o = tree[LEVELS][0][47:24];

    // Overflow collection in two registered steps: one flag per cascade,
    // then the chain flag.
    reg [N_SEG-1:0] ovfl_seg;
    genvar g;
    generate
        for (g = 0; g < N_SEG; g = g + 1) begin : g_ovfl
            always @(posedge clk)
                ovfl_seg[g] <= |ovfl[g*CASC_LEN +: CASC_LEN];
        end
    endgenerate

    always @(posedge clk) begin
        if (rst)
            ovfl_o <= 1'b0;
        else
            ovfl_o <= |ovfl_seg;
    end

endmodule
