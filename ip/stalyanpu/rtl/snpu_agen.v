// =============================================================================
// snpu_agen.v
//
// Address generator of one convolution descriptor. Walks
//
//     for tile: for oct: for icg: for tap (ky, kx): for pixel p
//
// and produces, one pixel per cycle, the ibuf word address of the input
// pixel of that tap, a gate flag for positions outside the image (the data
// is replaced by the input zero point), the side band for the accumulator
// (valid, first pass, last pass, tile end, pixel index) and the weight latch
// pulse at the first pixel of every pass.
//
// The input rows [cfg_row_base_i, ...) of the run are resident in the ibuf
// starting at word cfg_ibuf_base_i, plane after plane, cfg_plane_words_i
// words per plane, rows in image order. The sequencer runs the generator
// once per spatial tile (cfg_n_tiles_i = 1, cfg_tile0_i = tile index) after
// filling the rows of that tile.
//
// A pass starts only when the weight shadow is ready and, for the first
// pass of a tile, when the accumulator bank the array writes is free.
// =============================================================================
`timescale 1ns / 1ps

module snpu_agen #(
    parameter AW  = 14,
    parameter P_W = 10,
    parameter CHAIN_LEN = 32
)(
    input  wire          clk,
    input  wire          rst,
    // configuration, stable while busy
    input  wire [15:0]   cfg_in_h_i,
    input  wire [15:0]   cfg_in_w_i,
    input  wire [15:0]   cfg_out_h_i,
    input  wire [15:0]   cfg_out_w_i,
    input  wire [7:0]    cfg_n_icg_i,
    input  wire [7:0]    cfg_n_oct_i,
    input  wire [3:0]    cfg_k_i,
    input  wire [3:0]    cfg_stride_i,
    input  wire [3:0]    cfg_pad_i,
    input  wire [15:0]   cfg_tile_rows_i,
    input  wire [15:0]   cfg_n_tiles_i,
    input  wire [AW-1:0] cfg_ibuf_base_i,
    input  wire [AW-1:0] cfg_plane_words_i,
    input  wire [15:0]   cfg_row_base_i,    // first input row resident in the ibuf
    input  wire [15:0]   cfg_tile0_i,       // index of the first tile of this run
    input  wire [15:0]   cfg_oy0_i,         // first output row of this run
    input  wire [15:0]   cfg_out_rows_i,    // output rows covered by this run
    // control
    input  wire          start_i,
    output wire          busy_o,
    output wire          done_o,
    input  wire          shadow_ready_i,
    input  wire          bank_free_i,
    output reg           tile_start_o,     // one pulse per (tile, oct) at its first pass
    output reg  [15:0]   tile_px_o,        // pixels of the tile being started
    output reg  [7:0]    tile_oct_o,
    output reg  [15:0]   tile_idx_o,
    // to ibuf and array
    output reg  [AW-1:0] addr_o,
    output reg           gate_o,           // 1: outside the image, use the zero point
    output reg           v_o,
    output reg           first_o,
    output reg           last_o,
    output reg           tile_end_o,
    output reg  [P_W-1:0] p_o,
    output reg           latch_o,
    output reg  [7:0]    sub_o             // input group inside the 32 channel word
);

    // SUBGROUPS input groups share one ibuf word when the chain is shorter
    // than 32 channels.
    localparam SUBGROUPS = 32 / CHAIN_LEN;

    localparam S_IDLE = 3'd0, S_TILE = 3'd1, S_PASS_WAIT = 3'd2, S_RUN = 3'd3, S_NEXT = 3'd4, S_DONE = 3'd5;
    reg [2:0] state;

    reg [15:0] tile, oct_cnt, rows_left;
    reg [7:0]  oct, icg;
    reg [3:0]  ky, kx;
    reg [15:0] oy, ox;          // absolute output row, column inside the tile
    reg [15:0] tile_rows_cur;   // rows in this tile
    reg [15:0] row_in_tile;
    reg [P_W-1:0] p;
    reg [15:0] tile_px;
    reg tphase;

    // Address pieces.
    reg signed [17:0] in_row, in_col;
    reg [AW-1:0] plane_off;

    wire first_pass = (icg == 8'd0) && (ky == 4'd0) && (kx == 4'd0);
    wire last_pass  = (icg == cfg_n_icg_i - 1) && (ky == cfg_k_i - 1) && (kx == cfg_k_i - 1);
    wire last_px    = (row_in_tile == tile_rows_cur - 1) && (ox == cfg_out_w_i - 1);

    // Row and column of the input pixel of the current tap.
    wire signed [17:0] in_row_w = $signed({2'b0, oy}) * $signed({14'b0, cfg_stride_i}) + $signed({14'b0, ky}) - $signed({14'b0, cfg_pad_i});
    wire signed [17:0] in_col_w = $signed({2'b0, ox}) * $signed({14'b0, cfg_stride_i}) + $signed({14'b0, kx}) - $signed({14'b0, cfg_pad_i});
    wire row_ok = (in_row_w >= 0) && (in_row_w < $signed({2'b0, cfg_in_h_i}));
    wire col_ok = (in_col_w >= 0) && (in_col_w < $signed({2'b0, cfg_in_w_i}));
    wire [15:0] in_row_local = in_row_w[15:0] - cfg_row_base_i;

    // Output pipeline. Stage a0 (written by the state machine) captures the
    // row and column pieces, stage a1 holds the row product, the output
    // stage sums the address. Every per pixel flag travels with its pieces
    // so pass boundaries stay aligned; latch and sub ride along too.
    reg        a0_v, a0_first, a0_last, a0_tend, a0_latch;
    reg signed [17:0] a0_row, a0_colw;
    reg [P_W-1:0] a0_p;
    reg [7:0]  a0_sub;
    reg [AW-1:0] a0_poff;
    reg [15:0] a0_rowloc;
    reg [AW-1:0] a0_col;
    reg        a1_v, a1_first, a1_last, a1_tend, a1_latch;
    reg        a1_ok;
    reg [P_W-1:0] a1_p;
    reg [7:0]  a1_sub;
    reg [AW-1:0] a1_poff;
    reg [31:0] a1_rowmul;
    reg [AW-1:0] a1_col;
    reg        busy_q, done_q, d1_done, d2_done;
    reg [7:0]  sub_q;

    assign busy_o = busy_q || a0_v || a1_v || v_o;
    assign done_o = d2_done;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            busy_q <= 1'b0; done_q <= 1'b0;
            tile_start_o <= 1'b0; tile_px_o <= 16'd0; tile_oct_o <= 8'd0; tile_idx_o <= 16'd0;
            a0_v <= 1'b0; a0_first <= 1'b0; a0_last <= 1'b0; a0_tend <= 1'b0; a0_latch <= 1'b0;
            a0_row <= 18'sd0; a0_colw <= 18'sd0;
            a0_p <= {P_W{1'b0}}; a0_sub <= 8'd0; a0_poff <= {AW{1'b0}}; a0_rowloc <= 16'd0; a0_col <= {AW{1'b0}};
            tile <= 16'd0; oct <= 8'd0; icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
            oy <= 16'd0; ox <= 16'd0; row_in_tile <= 16'd0; p <= {P_W{1'b0}};
            tile_rows_cur <= 16'd0; rows_left <= 16'd0; plane_off <= {AW{1'b0}}; tile_px <= 16'd0; sub_q <= 8'd0;
            tphase <= 1'b0;
        end else begin
            a0_v <= 1'b0; a0_latch <= 1'b0; a0_tend <= 1'b0; done_q <= 1'b0; tile_start_o <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        busy_q <= 1'b1;
                        tile <= 16'd0; oct <= 8'd0; icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
                        rows_left <= cfg_out_rows_i;
                        oy <= 16'd0;
                        state <= S_TILE;
                    end
                end
                S_TILE: begin
                    // Size of this tile, in two steps so the pixel count is
                    // a plain registered product.
                    if (!tphase) begin
                        tile_rows_cur <= (rows_left < cfg_tile_rows_i) ? rows_left : cfg_tile_rows_i;
                        tphase <= 1'b1;
                    end else begin
                        tile_px <= tile_rows_cur * cfg_out_w_i;
                        icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
                        plane_off <= {AW{1'b0}};
                        sub_q <= 8'd0;
                        tphase <= 1'b0;
                        state <= S_PASS_WAIT;
                    end
                end
                S_PASS_WAIT: begin
                    // A tile end still inside the output pipeline has not
                    // reached the accumulator guard yet, so the first pass
                    // of the next tile must also wait for it to leave.
                    if (shadow_ready_i && (!first_pass || (bank_free_i && !a0_tend && !a1_tend && !tile_end_o))) begin
                        if (first_pass) begin
                            tile_start_o <= 1'b1;
                            tile_px_o <= tile_px;
                            tile_oct_o <= oct;
                            tile_idx_o <= cfg_tile0_i + tile;
                        end
                        ox <= 16'd0; row_in_tile <= 16'd0; p <= {P_W{1'b0}};
                        oy <= cfg_oy0_i + tile * cfg_tile_rows_i;
                        state <= S_RUN;
                        a0_latch <= 1'b1;
                    end
                end
                S_RUN: begin
                    a0_v <= 1'b1;
                    a0_rowloc <= in_row_local;
                    a0_col <= in_col_w[AW-1:0];
                    a0_row <= in_row_w;
                    a0_colw <= in_col_w;
                    a0_first <= first_pass;
                    a0_last <= last_pass;
                    a0_p <= p;
                    a0_tend <= last_pass && last_px;
                    a0_poff <= plane_off;
                    a0_sub <= sub_q;
                    p <= p + 1'b1;
                    if (ox == cfg_out_w_i - 1) begin
                        ox <= 16'd0;
                        oy <= oy + 1'b1;
                        row_in_tile <= row_in_tile + 1'b1;
                    end else begin
                        ox <= ox + 1'b1;
                    end
                    if (last_px)
                        state <= S_NEXT;
                end
                S_NEXT: begin
                    // Advance tap, input group, output tile, spatial tile.
                    if (kx != cfg_k_i - 1) begin
                        kx <= kx + 1'b1;
                        state <= S_PASS_WAIT;
                    end else if (ky != cfg_k_i - 1) begin
                        kx <= 4'd0; ky <= ky + 1'b1;
                        state <= S_PASS_WAIT;
                    end else if (icg != cfg_n_icg_i - 1) begin
                        kx <= 4'd0; ky <= 4'd0; icg <= icg + 1'b1;
                        if (sub_q == SUBGROUPS - 1) begin
                            plane_off <= plane_off + cfg_plane_words_i;
                            sub_q <= 8'd0;
                        end else begin
                            sub_q <= sub_q + 8'd1;
                        end
                        state <= S_PASS_WAIT;
                    end else if (oct != cfg_n_oct_i - 1) begin
                        kx <= 4'd0; ky <= 4'd0; icg <= 8'd0; oct <= oct + 1'b1;
                        plane_off <= {AW{1'b0}};
                        sub_q <= 8'd0;
                        state <= S_PASS_WAIT;
                    end else if (tile != cfg_n_tiles_i - 1) begin
                        oct <= 8'd0;
                        tile <= tile + 1'b1;
                        rows_left <= rows_left-tile_rows_cur;
                        state <= S_TILE;
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    busy_q <= 1'b0;
                    done_q <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // Stages a1 and output.
    always @(posedge clk) begin
        if (rst) begin
            a1_v <= 1'b0; a1_first <= 1'b0; a1_last <= 1'b0; a1_tend <= 1'b0; a1_latch <= 1'b0; a1_ok <= 1'b0;
            a1_p <= {P_W{1'b0}}; a1_sub <= 8'd0; a1_poff <= {AW{1'b0}}; a1_rowmul <= 32'd0; a1_col <= {AW{1'b0}};
            addr_o <= {AW{1'b0}}; gate_o <= 1'b0; v_o <= 1'b0; first_o <= 1'b0; last_o <= 1'b0;
            tile_end_o <= 1'b0; p_o <= {P_W{1'b0}}; latch_o <= 1'b0; sub_o <= 8'd0;
            d1_done <= 1'b0; d2_done <= 1'b0;
        end else begin
            a1_v <= a0_v; a1_first <= a0_first; a1_last <= a0_last; a1_tend <= a0_tend;
            a1_latch <= a0_latch; a1_p <= a0_p; a1_sub <= a0_sub;
            a1_ok <= (a0_row >= 0) && (a0_row < $signed({2'b0, cfg_in_h_i}))
                  && (a0_colw >= 0) && (a0_colw < $signed({2'b0, cfg_in_w_i}));
            a1_poff <= a0_poff; a1_col <= a0_col;
            a1_rowmul <= a0_rowloc * cfg_in_w_i;
            v_o <= a1_v; first_o <= a1_first; last_o <= a1_last; tile_end_o <= a1_tend;
            latch_o <= a1_latch; p_o <= a1_p; sub_o <= a1_sub;
            gate_o <= !a1_ok;
            addr_o <= cfg_ibuf_base_i + a1_poff + a1_rowmul[AW-1:0] + a1_col;
            d1_done <= done_q;
            d2_done <= d1_done;
        end
    end

endmodule
