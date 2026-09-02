// =============================================================================
// snpu_syn_conv.v
//
// Synthesis wrapper of the convolution engine. The wrapper exists only to
// measure resources and timing of snpu_conv_unit on its own: every input of
// the unit is driven from a long shift register fed by a single pin, and
// every output is folded into one pin through a registered xor tree. Nothing
// is constant, so the mapper cannot trim the engine, and the pin count stays
// at four.
// =============================================================================
`timescale 1ns / 1ps

module snpu_syn_conv #(
    parameter N_CHAIN     = 32,
    parameter CHAIN_LEN   = 32,
    parameter P_MAX       = 1024,
    parameter P_W         = 10,
    parameter IBUF_WORDS  = 16384,
    parameter IBUF_AW     = 14,
    parameter WFIFO_WORDS = 1024,
    parameter WFIFO_AW    = 10,
    parameter OC_MAX      = 512
)(
    input  wire clk,
    input  wire pll_locked,
    input  wire rst_i,
    input  wire sin,
    output reg  sout
);

    // Reset synchroniser. The engine stays in reset until the PLL locks.
    reg [1:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[0], rst_i || !pll_locked};
    wire rst = rst_sync[1];

    // Input shift register. Field offsets are accumulated below.
    localparam O_IN_H      = 0;
    localparam O_IN_W      = O_IN_H + 16;
    localparam O_OUT_H     = O_IN_W + 16;
    localparam O_OUT_W     = O_OUT_H + 16;
    localparam O_N_ICG     = O_OUT_W + 16;
    localparam O_N_OCT     = O_N_ICG + 8;
    localparam O_N_PLANES  = O_N_OCT + 8;
    localparam O_K         = O_N_PLANES + 8;
    localparam O_STRIDE    = O_K + 4;
    localparam O_PAD       = O_STRIDE + 4;
    localparam O_ZP_IN     = O_PAD + 4;
    localparam O_TILE_ROWS = O_ZP_IN + 8;
    localparam O_N_TILES   = O_TILE_ROWS + 16;
    localparam O_IBUF_BASE = O_N_TILES + 16;
    localparam O_PLANE_W   = O_IBUF_BASE + IBUF_AW;
    localparam O_ROW_BASE  = O_PLANE_W + IBUF_AW;
    localparam O_TILE0     = O_ROW_BASE + 16;
    localparam O_OY0       = O_TILE0 + 16;
    localparam O_OUT_ROWS  = O_OY0 + 16;
    localparam O_SILU      = O_OUT_ROWS + 16;
    localparam O_RESIDUAL  = O_SILU + 1;
    localparam O_ZP_OUT    = O_RESIDUAL + 1;
    localparam O_ZP_RES    = O_ZP_OUT + 8;
    localparam O_ZP_OUT2   = O_ZP_RES + 8;
    localparam O_RMA       = O_ZP_OUT2 + 8;
    localparam O_RSA       = O_RMA + 16;
    localparam O_RMB       = O_RSA + 8;
    localparam O_RSB       = O_RMB + 16;
    localparam O_START     = O_RSB + 8;
    localparam O_IB_WE     = O_START + 1;
    localparam O_IB_WADDR  = O_IB_WE + 1;
    localparam O_IB_WDATA  = O_IB_WADDR + IBUF_AW;
    localparam O_W_VALID   = O_IB_WDATA + 256;
    localparam O_W_DATA    = O_W_VALID + 1;
    localparam O_PRM_WE    = O_W_DATA + 256;
    localparam O_PRM_ADDR  = O_PRM_WE + 1;
    localparam O_PRM_DATA  = O_PRM_ADDR + 10;
    localparam O_LUT_WE    = O_PRM_DATA + 64;
    localparam O_LUT_ADDR  = O_LUT_WE + 1;
    localparam O_LUT_DATA  = O_LUT_ADDR + 8;
    localparam O_RES_VALID = O_LUT_DATA + 8;
    localparam O_RES_DATA  = O_RES_VALID + 1;
    localparam O_OUT_READY = O_RES_DATA + 256;
    localparam IN_W        = O_OUT_READY + 1;

    reg [IN_W-1:0] sr;
    always @(posedge clk)
        sr <= {sr[IN_W-2:0], sin ^ sr[IN_W-1] ^ sr[IN_W/2]};

    wire        busy, done, w_ready, res_ready, drain_start, out_valid, out_last, ovfl;
    wire [7:0]  drain_oct, out_plane;
    wire [255:0] out_data;
    wire [15:0] out_px, out_tile;

    snpu_conv_unit #(
        .N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .P_MAX(P_MAX), .P_W(P_W),
        .IBUF_WORDS(IBUF_WORDS), .IBUF_AW(IBUF_AW),
        .WFIFO_WORDS(WFIFO_WORDS), .WFIFO_AW(WFIFO_AW), .OC_MAX(OC_MAX)
    ) u_conv (
        .clk(clk), .rst(rst),
        .cfg_in_h_i       (sr[O_IN_H      +: 16]),
        .cfg_in_w_i       (sr[O_IN_W      +: 16]),
        .cfg_out_h_i      (sr[O_OUT_H     +: 16]),
        .cfg_out_w_i      (sr[O_OUT_W     +: 16]),
        .cfg_n_icg_i      (sr[O_N_ICG     +: 8]),
        .cfg_n_oct_i      (sr[O_N_OCT     +: 8]),
        .cfg_n_planes_i   (sr[O_N_PLANES  +: 8]),
        .cfg_k_i          (sr[O_K         +: 4]),
        .cfg_stride_i     (sr[O_STRIDE    +: 4]),
        .cfg_pad_i        (sr[O_PAD       +: 4]),
        .cfg_zp_in_i      (sr[O_ZP_IN     +: 8]),
        .cfg_tile_rows_i  (sr[O_TILE_ROWS +: 16]),
        .cfg_n_tiles_i    (sr[O_N_TILES   +: 16]),
        .cfg_ibuf_base_i  (sr[O_IBUF_BASE +: IBUF_AW]),
        .cfg_plane_words_i(sr[O_PLANE_W   +: IBUF_AW]),
        .cfg_row_base_i   (sr[O_ROW_BASE  +: 16]),
        .cfg_tile0_i      (sr[O_TILE0     +: 16]),
        .cfg_oy0_i        (sr[O_OY0       +: 16]),
        .cfg_out_rows_i   (sr[O_OUT_ROWS  +: 16]),
        .cfg_silu_i       (sr[O_SILU]),
        .cfg_residual_i   (sr[O_RESIDUAL]),
        .cfg_zp_out_i     (sr[O_ZP_OUT    +: 8]),
        .cfg_zp_res_i     (sr[O_ZP_RES    +: 8]),
        .cfg_zp_out2_i    (sr[O_ZP_OUT2   +: 8]),
        .cfg_res_mult_a_i (sr[O_RMA       +: 16]),
        .cfg_res_shift_a_i(sr[O_RSA       +: 8]),
        .cfg_res_mult_b_i (sr[O_RMB       +: 16]),
        .cfg_res_shift_b_i(sr[O_RSB       +: 8]),
        .start_i          (sr[O_START]),
        .busy_o           (busy),
        .done_o           (done),
        .ibuf_we_i        (sr[O_IB_WE]),
        .ibuf_waddr_i     (sr[O_IB_WADDR  +: IBUF_AW]),
        .ibuf_wdata_i     (sr[O_IB_WDATA  +: 256]),
        .w_valid_i        (sr[O_W_VALID]),
        .w_data_i         (sr[O_W_DATA    +: 256]),
        .w_ready_o        (w_ready),
        .prm_we_i         (sr[O_PRM_WE]),
        .prm_addr_i       (sr[O_PRM_ADDR  +: 10]),
        .prm_data_i       (sr[O_PRM_DATA  +: 64]),
        .lut_we_i         (sr[O_LUT_WE]),
        .lut_addr_i       (sr[O_LUT_ADDR  +: 8]),
        .lut_data_i       (sr[O_LUT_DATA  +: 8]),
        .res_valid_i      (sr[O_RES_VALID]),
        .res_data_i       (sr[O_RES_DATA  +: 256]),
        .res_ready_o      (res_ready),
        .drain_start_o    (drain_start),
        .drain_oct_o      (drain_oct),
        .out_valid_o      (out_valid),
        .out_data_o       (out_data),
        .out_plane_o      (out_plane),
        .out_px_o         (out_px),
        .out_tile_o       (out_tile),
        .out_last_o       (out_last),
        .out_ready_i      (sr[O_OUT_READY]),
        .ovfl_o           (ovfl)
    );

    // Output fold: one register per 32-bit slice, then one more register.
    wire [319:0] outs = {9'd0, busy, done, w_ready, res_ready, drain_start, drain_oct,
                         out_valid, out_last, ovfl, out_plane, out_px, out_tile, out_data};
    reg [9:0] fold;
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < 10; i = i + 1)
            fold[i] <= ^outs[i*32 +: 32];
        sout <= ^fold;
    end

endmodule
