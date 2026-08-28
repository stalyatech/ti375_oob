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
// The input rows of the layer are assumed resident in the ibuf starting at
// word cfg_ibuf_base_i, plane after plane, cfg_plane_words_i words per
// plane, rows in image order (the ring management of the DMA is added in
// the top level and offsets cfg_ibuf_base_i per tile).
//
// A pass starts only when the weight shadow is ready and, for the first
// pass of a tile, when the accumulator bank the array writes is free.
// =============================================================================
`timescale 1ns / 1ps

module snpu_agen #(
    parameter AW  = 14,
    parameter P_W = 10
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
    // control
    input  wire          start_i,
    output reg           busy_o,
    output reg           done_o,
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
    output reg           latch_o
);

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
    wire [AW-1:0] addr_w = cfg_ibuf_base_i + plane_off + in_row_w[AW-1:0] * cfg_in_w_i + in_col_w[AW-1:0];

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            busy_o <= 1'b0; done_o <= 1'b0;
            tile_start_o <= 1'b0; tile_px_o <= 16'd0; tile_oct_o <= 8'd0; tile_idx_o <= 16'd0;
            addr_o <= {AW{1'b0}}; gate_o <= 1'b0; v_o <= 1'b0; first_o <= 1'b0; last_o <= 1'b0;
            tile_end_o <= 1'b0; p_o <= {P_W{1'b0}}; latch_o <= 1'b0;
            tile <= 16'd0; oct <= 8'd0; icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
            oy <= 16'd0; ox <= 16'd0; row_in_tile <= 16'd0; p <= {P_W{1'b0}};
            tile_rows_cur <= 16'd0; rows_left <= 16'd0; plane_off <= {AW{1'b0}}; tile_px <= 16'd0;
        end else begin
            v_o <= 1'b0; latch_o <= 1'b0; tile_end_o <= 1'b0; done_o <= 1'b0; tile_start_o <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        busy_o <= 1'b1;
                        tile <= 16'd0; oct <= 8'd0; icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
                        rows_left <= cfg_out_h_i;
                        oy <= 16'd0;
                        state <= S_TILE;
                    end
                end
                S_TILE: begin
                    // Size of this tile.
                    tile_rows_cur <= (rows_left < cfg_tile_rows_i) ? rows_left : cfg_tile_rows_i;
                    tile_px <= ((rows_left < cfg_tile_rows_i) ? rows_left : cfg_tile_rows_i) * cfg_out_w_i;
                    icg <= 8'd0; ky <= 4'd0; kx <= 4'd0;
                    plane_off <= {AW{1'b0}};
                    state <= S_PASS_WAIT;
                end
                S_PASS_WAIT: begin
                    if (shadow_ready_i && (!first_pass || bank_free_i)) begin
                        if (first_pass) begin
                            tile_start_o <= 1'b1;
                            tile_px_o <= tile_px;
                            tile_oct_o <= oct;
                            tile_idx_o <= tile;
                        end
                        ox <= 16'd0; row_in_tile <= 16'd0; p <= {P_W{1'b0}};
                        oy <= tile * cfg_tile_rows_i;
                        state <= S_RUN;
                        latch_o <= 1'b1;
                    end
                end
                S_RUN: begin
                    v_o <= 1'b1;
                    addr_o <= addr_w;
                    gate_o <= !(row_ok && col_ok);
                    first_o <= first_pass;
                    last_o <= last_pass;
                    p_o <= p;
                    tile_end_o <= last_pass && last_px;
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
                        plane_off <= plane_off + cfg_plane_words_i;
                        state <= S_PASS_WAIT;
                    end else if (oct != cfg_n_oct_i - 1) begin
                        kx <= 4'd0; ky <= 4'd0; icg <= 8'd0; oct <= oct + 1'b1;
                        plane_off <= {AW{1'b0}};
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
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
