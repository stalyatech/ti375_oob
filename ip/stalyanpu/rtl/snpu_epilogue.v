// =============================================================================
// snpu_epilogue.v
//
// Drains a full accumulator bank and produces int8 output words.
//
// For every (tile, oct) queued by the address generator it reads the P
// pixels of the bank. A bank pixel holds N_OC channels; the epilogue takes
// them 32 at a time (one output plane per cycle) through 32 lanes:
//
//     acc32 + bias -> * mult -> + 2^(shift-1) -> >> shift -> + zp_pre
//     -> saturate -> activation table -> residual add -> saturate
//
// and packs the lanes into one 256-bit word tagged with the output plane
// and pixel. Planes beyond cfg_n_planes_i are skipped. The residual word of
// the same (pixel, plane) comes from the residual stream.
//
// Per channel parameters live in 32 small RAMs indexed by plane (entry =
// output channel / 32). The activation table is replicated per lane.
//
// The whole pipeline advances on one enable, so output backpressure and a
// missing residual word stall it as a unit.
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
    // output stream
    output reg                  out_valid_o,
    output reg  [255:0]         out_data_o,
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
    localparam EW      = 8;

    // Tile queue (depth 4).
    reg [39:0] tq [0:3];
    reg [2:0] tq_wp, tq_rp;
    wire tq_empty = (tq_wp == tq_rp);
    always @(posedge clk) begin
        if (tile_start_i)
            tq[tq_wp[1:0]] <= {tile_idx_i, tile_oct_i, tile_px_i};
    end

    // Parameter RAMs, one per lane, and the replicated activation table.
    reg [63:0] prm [0:LANES-1][0:ENTRIES-1];
    reg [7:0]  lut [0:LANES-1][0:255];
    integer li;
    always @(posedge clk) begin
        if (prm_we_i)
            prm[prm_addr_i[4:0]][prm_addr_i[9:5]] <= prm_data_i;
        if (lut_we_i)
            for (li = 0; li < LANES; li = li + 1)
                lut[li][lut_addr_i] <= lut_data_i;
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

    // Pipeline enable.
    wire s4_need_res;
    wire adv = (!out_valid_o || out_ready_i) && (!s4_need_res || res_valid_i);
    assign res_ready_o = adv && s4_need_res;
    assign ep_re_o = adv;

    // A drain is open from the tile start until the bank is released. The
    // release is issued at the edge where stage 2 captures the last word of
    // the tile, so the bank switch of the accumulator can no longer disturb
    // the data in flight.
    reg drain_open;

    // Stage 0: issue bank read and parameter read.
    reg        s0_v, s0_last;
    reg [7:0]  s0_win, s0_plane;
    reg [15:0] s0_px, s0_tile;
    // Stage 1: data from bank and params.
    reg        s1_v, s1_last;
    reg [7:0]  s1_win, s1_plane;
    reg [15:0] s1_px, s1_tile;
    reg [63:0] s1_prm [0:LANES-1];
    // Stage 2: bias add.
    reg        s2_v, s2_last;
    reg [7:0]  s2_plane;
    reg [15:0] s2_px, s2_tile;
    reg signed [32:0] s2_sum [0:LANES-1];
    reg [15:0] s2_mult [0:LANES-1];
    reg [7:0]  s2_shift [0:LANES-1];
    reg [7:0]  s2_zp [0:LANES-1];
    // Stage 3: multiply.
    reg        s3_v, s3_last;
    reg [7:0]  s3_plane;
    reg [15:0] s3_px, s3_tile;
    reg signed [49:0] s3_prod [0:LANES-1];
    reg [7:0]  s3_shift [0:LANES-1];
    reg [7:0]  s3_zp [0:LANES-1];
    // Stage 4: shift, zero point, saturate, table.
    reg        s4_v, s4_last;
    reg [7:0]  s4_plane;
    reg [15:0] s4_px, s4_tile;
    reg [7:0]  s4_q [0:LANES-1];

    assign s4_need_res = s4_v && cfg_residual_i;

    integer l;
    reg signed [49:0] shifted, rnd, t;
    reg [7:0] q8;
    reg signed [7:0] y8, r8;
    reg signed [31:0] ra, rb, rsum;
    reg [255:0] pack_w;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; tq_wp <= 3'd0; tq_rp <= 3'd0; drain_open <= 1'b0;
            px <= 16'd0; tile_px <= 16'd0; tile_idx <= 16'd0; oct <= 8'd0; win <= 8'd0;
            ep_addr_o <= {P_W{1'b0}}; ep_release_o <= 1'b0;
            s0_v <= 1'b0; s1_v <= 1'b0; s2_v <= 1'b0; s3_v <= 1'b0; s4_v <= 1'b0;
            s0_last <= 1'b0; s1_last <= 1'b0; s2_last <= 1'b0; s3_last <= 1'b0; s4_last <= 1'b0;
            out_valid_o <= 1'b0; out_data_o <= 256'd0; out_plane_o <= 8'd0; out_px_o <= 16'd0;
            out_tile_o <= 16'd0; out_last_o <= 1'b0;
            s0_win <= 8'd0; s0_plane <= 8'd0; s0_px <= 16'd0; s0_tile <= 16'd0;
            s1_win <= 8'd0; s1_plane <= 8'd0; s1_px <= 16'd0; s1_tile <= 16'd0;
            s2_plane <= 8'd0; s2_px <= 16'd0; s2_tile <= 16'd0;
            s3_plane <= 8'd0; s3_px <= 16'd0; s3_tile <= 16'd0;
            s4_plane <= 8'd0; s4_px <= 16'd0; s4_tile <= 16'd0;
        end else begin
            if (tile_start_i)
                tq_wp <= tq_wp + 1'b1;
            ep_release_o <= 1'b0;
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
                // ---- stage 1: capture bank and parameter reads
                s1_v <= s0_v; s1_last <= s0_last; s1_win <= s0_win; s1_plane <= s0_plane;
                s1_px <= s0_px; s1_tile <= s0_tile;
                for (l = 0; l < LANES; l = l + 1)
                    s1_prm[l] <= prm[l][s0_plane[EW-1:0]];
                // ---- stage 2: select window, add bias
                s2_v <= s1_v; s2_last <= s1_last; s2_plane <= s1_plane; s2_px <= s1_px; s2_tile <= s1_tile;
                for (l = 0; l < LANES; l = l + 1) begin
                    s2_sum[l] <= $signed(ep_data_i[(s1_win * LANES + l) * 32 +: 32]) + $signed(s1_prm[l][31:0]);
                    s2_mult[l] <= s1_prm[l][47:32];
                    s2_shift[l] <= s1_prm[l][55:48];
                    s2_zp[l] <= s1_prm[l][63:56];
                end
                // ---- stage 3: multiply
                s3_v <= s2_v; s3_last <= s2_last; s3_plane <= s2_plane; s3_px <= s2_px; s3_tile <= s2_tile;
                for (l = 0; l < LANES; l = l + 1) begin
                    s3_prod[l] <= s2_sum[l] * $signed({1'b0, s2_mult[l]});
                    s3_shift[l] <= s2_shift[l];
                    s3_zp[l] <= s2_zp[l];
                end
                // ---- stage 4: round, shift, zero point, saturate, table
                s4_v <= s3_v; s4_last <= s3_last; s4_plane <= s3_plane; s4_px <= s3_px; s4_tile <= s3_tile;
                for (l = 0; l < LANES; l = l + 1) begin
                    rnd = (s3_shift[l] == 8'd0) ? 50'sd0 : (50'sd1 <<< (s3_shift[l] - 1));
                    shifted = (s3_prod[l] + rnd) >>> s3_shift[l];
                    t = shifted + $signed(s3_zp[l]);
                    if (t > 50'sd127) q8 = 8'd127;
                    else if (t < -50'sd128) q8 = 8'h80;
                    else q8 = t[7:0];
                    s4_q[l] <= cfg_silu_i ? lut[l][{~q8[7], q8[6:0]}] : q8;
                end
                // ---- stage 5: residual add, pack, output register
                out_valid_o <= s4_v;
                out_plane_o <= s4_plane;
                out_px_o <= s4_px;
                out_tile_o <= s4_tile;
                out_last_o <= s4_last;
                for (l = 0; l < LANES; l = l + 1) begin
                    y8 = s4_q[l];
                    if (cfg_residual_i) begin
                        r8 = res_data_i[l*8 +: 8];
                        ra = ($signed({{24{y8[7]}}, y8}) - $signed({{24{cfg_zp_out_i[7]}}, cfg_zp_out_i})) * $signed({1'b0, cfg_res_mult_a_i});
                        rb = ($signed({{24{r8[7]}}, r8}) - $signed({{24{cfg_zp_res_i[7]}}, cfg_zp_res_i})) * $signed({1'b0, cfg_res_mult_b_i});
                        ra = (ra + ((cfg_res_shift_a_i == 8'd0) ? 32'sd0 : (32'sd1 <<< (cfg_res_shift_a_i - 1)))) >>> cfg_res_shift_a_i;
                        rb = (rb + ((cfg_res_shift_b_i == 8'd0) ? 32'sd0 : (32'sd1 <<< (cfg_res_shift_b_i - 1)))) >>> cfg_res_shift_b_i;
                        rsum = ra + rb + $signed({{24{cfg_zp_out2_i[7]}}, cfg_zp_out2_i});
                        if (rsum > 32'sd127) pack_w[l*8 +: 8] = 8'd127;
                        else if (rsum < -32'sd128) pack_w[l*8 +: 8] = 8'h80;
                        else pack_w[l*8 +: 8] = rsum[7:0];
                    end else begin
                        pack_w[l*8 +: 8] = y8;
                    end
                end
                out_data_o <= pack_w;
            end else if (out_valid_o && out_ready_i) begin
                // The pipeline is held (residual word missing) but the
                // consumer took the output word; do not offer it twice.
                out_valid_o <= 1'b0;
            end
        end
    end

    assign busy_o = (state != S_IDLE) || drain_open || s0_v || s1_v || s2_v || s3_v || s4_v || out_valid_o || !tq_empty;

endmodule
