// =============================================================================
// snpu_epilogue.v
//
// Drains a full accumulator bank and produces int8 output words.
//
// For every (tile, oct) queued by the address generator it reads the P
// pixels of the bank. A bank pixel holds N_OC channels; the epilogue takes
// them 32 at a time (one output plane per cycle) through 32 lanes
// (snpu_ep_lane) and packs the lane results into one 256-bit word tagged
// with the output plane and pixel. Planes beyond cfg_n_planes_i are
// skipped. The residual word of the same (pixel, plane) comes from the
// residual stream and is consumed by the last lane stage.
//
// Pipeline: s0 issues the bank and parameter reads, s1 holds the bank
// data, s2..s12 are the lane stages (bias, product, rounding sum, shift,
// saturate, table, residual differences, products, roundings, shifts and
// sum), the output register is stage 13. The residual word is consumed one
// cycle after the table stage, which carries the s7 tag. The whole pipeline advances on one enable, so output
// backpressure and a missing residual word stall it as a unit.
// =============================================================================
`timescale 1ns / 1ps

module snpu_epilogue #(
    parameter N_OC   = 64,
    parameter P_W    = 10,
    parameter OC_MAX = 512
)(
    input  wire                 clk,
    input  wire                 rst,
    // configuration
    input  wire                 cfg_silu_i,
    input  wire                 cfg_residual_i,
    input  wire [7:0]           cfg_n_planes_i,
    input  wire [7:0]           cfg_zp_out_i,
    input  wire [7:0]           cfg_zp_res_i,
    input  wire [7:0]           cfg_zp_out2_i,
    input  wire [15:0]          cfg_res_mult_a_i,
    input  wire [7:0]           cfg_res_shift_a_i,
    input  wire [15:0]          cfg_res_mult_b_i,
    input  wire [7:0]           cfg_res_shift_b_i,
    // parameter and table load
    input  wire                 prm_we_i,
    input  wire [9:0]           prm_addr_i,      // output channel index
    input  wire [63:0]          prm_data_i,      // {zp, shift, mult, bias}
    input  wire                 lut_we_i,
    input  wire [7:0]           lut_addr_i,
    input  wire [7:0]           lut_data_i,
    // tile queue from the address generator
    input  wire                 tile_start_i,
    input  wire [15:0]          tile_px_i,
    input  wire [7:0]           tile_oct_i,
    input  wire [15:0]          tile_idx_i,
    // accumulator bank
    input  wire                 bank_full_i,
    output reg  [P_W-1:0]       ep_addr_o,
    output wire                 ep_re_o,
    input  wire [N_OC*32-1:0]   ep_data_i,
    output reg                  ep_release_o,
    // residual stream
    input  wire                 res_valid_i,
    input  wire [255:0]         res_data_i,
    output wire                 res_ready_o,
    // drain start notification (residual fetch of this tile)
    output reg                  drain_start_o,
    output reg  [7:0]           drain_oct_o,
    // output stream
    output reg                  out_valid_o,
    output wire [255:0]         out_data_o,
    output reg  [7:0]           out_plane_o,
    output reg  [15:0]          out_px_o,
    output reg  [15:0]          out_tile_o,
    output reg                  out_last_o,      // last word of the (tile, oct)
    input  wire                 out_ready_i,
    output wire                 busy_o
);

    localparam LANES   = 32;
    localparam WINDOWS = N_OC / 32;          // planes per oct
    localparam ENTRIES = OC_MAX / 32;
    localparam EW      = (ENTRIES > 1) ? $clog2(ENTRIES) : 1;

    // Tile queue (depth 4).
    reg [39:0] tq [0:3];
    reg [2:0] tq_wp, tq_rp;
    wire tq_empty = (tq_wp == tq_rp);
    always @(posedge clk) begin
        if (tile_start_i)
            tq[tq_wp[1:0]] <= {tile_idx_i, tile_oct_i, tile_px_i};
    end

    // Sequencing: pixel px, window win of the bank.
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_FLUSH = 2'd2;
    reg [1:0] state;
    reg [15:0] px, tile_px, tile_idx;
    reg [7:0]  oct;
    reg [7:0]  win;
    wire [7:0] plane = oct * WINDOWS + win;
    wire plane_valid = (plane < cfg_n_planes_i);
    wire next_plane_valid = (win != WINDOWS - 1) && ((plane + 8'd1) < cfg_n_planes_i);

    // Tag pipeline.
    reg        s0_v, s1_v, s2_v, s3_v, s4_v, s5_v, s6_v, s7_v, s8_v, s9_v, s10_v, s11_v, s12_v;
    reg        s0_last, s1_last, s2_last, s3_last, s4_last, s5_last, s6_last, s7_last, s8_last, s9_last, s10_last, s11_last, s12_last;
    reg [7:0]  s0_win, s1_win;
    reg [7:0]  s0_plane, s1_plane, s2_plane, s3_plane, s4_plane, s5_plane, s6_plane, s7_plane, s8_plane, s9_plane, s10_plane, s11_plane, s12_plane;
    reg [15:0] s0_px, s1_px, s2_px, s3_px, s4_px, s5_px, s6_px, s7_px, s8_px, s9_px, s10_px, s11_px, s12_px;
    reg [15:0] s0_tile, s1_tile, s2_tile, s3_tile, s4_tile, s5_tile, s6_tile, s7_tile, s8_tile, s9_tile, s10_tile, s11_tile, s12_tile;

    // Pipeline enable. The residual word is consumed by the lane stage that
    // follows the table read, whose tag is s7.
    wire s7_need_res = s7_v && cfg_residual_i;
    wire adv = (!out_valid_o || out_ready_i) && (!s7_need_res || res_valid_i);
    assign res_ready_o = adv && s7_need_res;
    assign ep_re_o = adv;

    // A drain is open from the tile start until the bank is released. The
    // release is issued at the edge where stage 2 captures the last word of
    // the tile, so the bank switch of the accumulator can no longer disturb
    // the data in flight.
    reg drain_open;

    // ---- lanes
    genvar l;
    generate
        for (l = 0; l < LANES; l = l + 1) begin : g_lane
            wire [31:0] acc = ep_data_i[(s1_win * LANES + l) * 32 +: 32];
            snpu_ep_lane #(.ENTRIES(ENTRIES), .EW(EW)) u_lane (
                .clk(clk), .rst(rst), .adv_i(adv),
                .prm_we_i(prm_we_i && (prm_addr_i[4:0] == l)),
                .prm_addr_i(prm_addr_i[5 +: EW]),
                .prm_data_i(prm_data_i),
                .lut_we_i(lut_we_i), .lut_addr_i(lut_addr_i), .lut_data_i(lut_data_i),
                .cfg_silu_i(cfg_silu_i), .cfg_residual_i(cfg_residual_i),
                .cfg_zp_out_i(cfg_zp_out_i), .cfg_zp_res_i(cfg_zp_res_i), .cfg_zp_out2_i(cfg_zp_out2_i),
                .cfg_res_mult_a_i(cfg_res_mult_a_i), .cfg_res_shift_a_i(cfg_res_shift_a_i),
                .cfg_res_mult_b_i(cfg_res_mult_b_i), .cfg_res_shift_b_i(cfg_res_shift_b_i),
                .s0_plane_i(s0_plane[EW-1:0]),
                .s1_acc_i(acc),
                .s5_res_i(res_data_i[l*8 +: 8]),
                .y_o(out_data_o[l*8 +: 8])
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; tq_wp <= 3'd0; tq_rp <= 3'd0; drain_open <= 1'b0;
            drain_start_o <= 1'b0; drain_oct_o <= 8'd0;
            px <= 16'd0; tile_px <= 16'd0; tile_idx <= 16'd0; oct <= 8'd0; win <= 8'd0;
            ep_addr_o <= {P_W{1'b0}}; ep_release_o <= 1'b0;
            s0_v <= 1'b0; s1_v <= 1'b0; s2_v <= 1'b0; s3_v <= 1'b0; s4_v <= 1'b0; s5_v <= 1'b0; s6_v <= 1'b0; s7_v <= 1'b0; s8_v <= 1'b0; s9_v <= 1'b0; s10_v <= 1'b0; s11_v <= 1'b0; s12_v <= 1'b0;
            s0_last <= 1'b0; s1_last <= 1'b0; s2_last <= 1'b0; s3_last <= 1'b0; s4_last <= 1'b0; s5_last <= 1'b0; s6_last <= 1'b0; s7_last <= 1'b0; s8_last <= 1'b0; s9_last <= 1'b0; s10_last <= 1'b0; s11_last <= 1'b0; s12_last <= 1'b0;
            out_valid_o <= 1'b0; out_plane_o <= 8'd0; out_px_o <= 16'd0;
            out_tile_o <= 16'd0; out_last_o <= 1'b0;
            s0_win <= 8'd0; s1_win <= 8'd0;
            s0_plane <= 8'd0; s1_plane <= 8'd0; s2_plane <= 8'd0; s3_plane <= 8'd0; s4_plane <= 8'd0; s5_plane <= 8'd0; s6_plane <= 8'd0; s7_plane <= 8'd0; s8_plane <= 8'd0; s9_plane <= 8'd0; s10_plane <= 8'd0; s11_plane <= 8'd0; s12_plane <= 8'd0;
            s0_px <= 16'd0; s1_px <= 16'd0; s2_px <= 16'd0; s3_px <= 16'd0; s4_px <= 16'd0; s5_px <= 16'd0; s6_px <= 16'd0; s7_px <= 16'd0; s8_px <= 16'd0; s9_px <= 16'd0; s10_px <= 16'd0; s11_px <= 16'd0; s12_px <= 16'd0;
            s0_tile <= 16'd0; s1_tile <= 16'd0; s2_tile <= 16'd0; s3_tile <= 16'd0; s4_tile <= 16'd0; s5_tile <= 16'd0; s6_tile <= 16'd0; s7_tile <= 16'd0; s8_tile <= 16'd0; s9_tile <= 16'd0; s10_tile <= 16'd0; s11_tile <= 16'd0; s12_tile <= 16'd0;
        end else begin
            if (tile_start_i)
                tq_wp <= tq_wp + 1'b1;
            ep_release_o <= 1'b0;
            drain_start_o <= 1'b0;
            if (adv && s1_v && s1_last) begin
                ep_release_o <= 1'b1;
                drain_open <= 1'b0;
            end
            if (adv) begin
                // ---- stage 0: sequencing
                s0_v <= 1'b0;
                s0_last <= 1'b0;
                case (state)
                    S_IDLE: begin
                        // The release pulse updates the bank state at the
                        // next edge; do not look at the stale flags meanwhile.
                        if (!tq_empty && bank_full_i && !ep_release_o && !drain_open) begin
                            {tile_idx, oct, tile_px} <= tq[tq_rp[1:0]];
                            tq_rp <= tq_rp + 1'b1;
                            px <= 16'd0;
                            win <= 8'd0;
                            drain_open <= 1'b1;
                            drain_start_o <= 1'b1;
                            drain_oct_o <= tq[tq_rp[1:0]][23:16];
                            state <= S_RUN;
                        end
                    end
                    S_RUN: begin
                        ep_addr_o <= px[P_W-1:0];
                        s0_v <= plane_valid;
                        s0_win <= win;
                        s0_plane <= plane;
                        s0_px <= px;
                        s0_tile <= tile_idx;
                        s0_last <= (px == tile_px - 1) && !next_plane_valid;
                        if (next_plane_valid) begin
                            win <= win + 8'd1;
                        end else begin
                            win <= 8'd0;
                            if (px == tile_px - 1)
                                state <= S_FLUSH;
                            else
                                px <= px + 1'b1;
                        end
                    end
                    S_FLUSH: begin
                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
                // ---- tags: stages 1 to 5, then the output register
                s1_v <= s0_v; s1_last <= s0_last; s1_win <= s0_win; s1_plane <= s0_plane; s1_px <= s0_px; s1_tile <= s0_tile;
                s2_v <= s1_v; s2_last <= s1_last; s2_plane <= s1_plane; s2_px <= s1_px; s2_tile <= s1_tile;
                s3_v <= s2_v; s3_last <= s2_last; s3_plane <= s2_plane; s3_px <= s2_px; s3_tile <= s2_tile;
                s4_v <= s3_v; s4_last <= s3_last; s4_plane <= s3_plane; s4_px <= s3_px; s4_tile <= s3_tile;
                s5_v <= s4_v; s5_last <= s4_last; s5_plane <= s4_plane; s5_px <= s4_px; s5_tile <= s4_tile;
                s6_v <= s5_v; s6_last <= s5_last; s6_plane <= s5_plane; s6_px <= s5_px; s6_tile <= s5_tile;
                s7_v <= s6_v; s7_last <= s6_last; s7_plane <= s6_plane; s7_px <= s6_px; s7_tile <= s6_tile;
                s8_v <= s7_v; s8_last <= s7_last; s8_plane <= s7_plane; s8_px <= s7_px; s8_tile <= s7_tile;
                s9_v <= s8_v; s9_last <= s8_last; s9_plane <= s8_plane; s9_px <= s8_px; s9_tile <= s8_tile;
                s10_v <= s9_v; s10_last <= s9_last; s10_plane <= s9_plane; s10_px <= s9_px; s10_tile <= s9_tile;
                s11_v <= s10_v; s11_last <= s10_last; s11_plane <= s10_plane; s11_px <= s10_px; s11_tile <= s10_tile;
                s12_v <= s11_v; s12_last <= s11_last; s12_plane <= s11_plane; s12_px <= s11_px; s12_tile <= s11_tile;
                out_valid_o <= s12_v;
                out_plane_o <= s12_plane;
                out_px_o <= s12_px;
                out_tile_o <= s12_tile;
                out_last_o <= s12_last;
            end else if (out_valid_o && out_ready_i) begin
                // The pipeline is held (residual word missing) but the
                // consumer took the output word; do not offer it twice.
                out_valid_o <= 1'b0;
            end
        end
    end

    assign busy_o = (state != S_IDLE) || drain_open || s0_v || s1_v || s2_v || s3_v || s4_v || s5_v || s6_v || s7_v || s8_v || s9_v || s10_v || s11_v || s12_v || out_valid_o || !tq_empty;

endmodule
