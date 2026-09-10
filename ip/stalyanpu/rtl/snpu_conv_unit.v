// =============================================================================
// snpu_conv_unit.v
//
// Convolution engine without the DMA and the sequencer: input buffer,
// address generator, weight FIFO with shadow fill, PE array, two bank
// accumulator and epilogue. The surrounding logic (M4) loads the ibuf,
// streams weights, parameters, tables and residual words, sets the
// configuration of one descriptor and pulses start_i; output words come
// out tagged with plane and pixel for the write DMA.
// =============================================================================
`timescale 1ns / 1ps

module snpu_conv_unit #(
    parameter N_CHAIN    = 32,
    parameter CHAIN_LEN  = 32,
    parameter P_MAX      = 1024,
    parameter P_W        = 10,
    parameter IBUF_WORDS = 16384,
    parameter IBUF_AW    = 14,
    parameter WFIFO_WORDS = 1024,
    parameter WFIFO_AW   = 10,
    parameter OC_MAX     = 512
)(
    input  wire                 clk,
    input  wire                 rst,
    // configuration of the current descriptor
    input  wire [15:0]          cfg_in_h_i,
    input  wire [15:0]          cfg_in_w_i,
    input  wire [15:0]          cfg_out_h_i,
    input  wire [15:0]          cfg_out_w_i,
    input  wire [7:0]           cfg_n_icg_i,
    input  wire [7:0]           cfg_n_oct_i,
    input  wire [7:0]           cfg_n_planes_i,
    input  wire [3:0]           cfg_k_i,
    input  wire [3:0]           cfg_stride_i,
    input  wire [3:0]           cfg_pad_i,
    input  wire [7:0]           cfg_zp_in_i,
    input  wire [15:0]          cfg_tile_rows_i,
    input  wire [15:0]          cfg_n_tiles_i,
    input  wire [IBUF_AW-1:0]   cfg_ibuf_base_i,
    input  wire [IBUF_AW-1:0]   cfg_plane_words_i,
    input  wire [15:0]          cfg_row_base_i,
    input  wire [15:0]          cfg_tile0_i,
    input  wire [15:0]          cfg_oy0_i,
    input  wire [15:0]          cfg_out_rows_i,
    input  wire                 cfg_silu_i,
    input  wire                 cfg_residual_i,
    input  wire [7:0]           cfg_zp_out_i,
    input  wire [7:0]           cfg_zp_res_i,
    input  wire [7:0]           cfg_zp_out2_i,
    input  wire [15:0]          cfg_res_mult_a_i,
    input  wire [7:0]           cfg_res_shift_a_i,
    input  wire [15:0]          cfg_res_mult_b_i,
    input  wire [7:0]           cfg_res_shift_b_i,
    // control
    input  wire                 start_i,
    output wire                 busy_o,
    output wire                 done_o,        // address generator finished
    // ibuf fill
    input  wire                 ibuf_we_i,
    input  wire [IBUF_AW-1:0]   ibuf_waddr_i,
    input  wire [255:0]         ibuf_wdata_i,
    // weight stream
    input  wire                 w_valid_i,
    input  wire [255:0]         w_data_i,
    output wire                 w_ready_o,
    // parameters and table
    input  wire                 prm_we_i,
    input  wire [9:0]           prm_addr_i,
    input  wire [63:0]          prm_data_i,
    input  wire                 lut_we_i,
    input  wire [7:0]           lut_addr_i,
    input  wire [7:0]           lut_data_i,
    // residual stream
    input  wire                 res_valid_i,
    input  wire [255:0]         res_data_i,
    output wire                 res_ready_o,
    // drain start of an output channel tile (residual fetch trigger)
    output wire                 drain_start_o,
    output wire [7:0]           drain_oct_o,
    // output stream
    output wire                 out_valid_o,
    output wire [255:0]         out_data_o,
    output wire [7:0]           out_plane_o,
    output wire [15:0]          out_px_o,
    output wire [15:0]          out_tile_o,
    output wire                 out_last_o,
    input  wire                 out_ready_i,
    output wire                 ovfl_o
);

    localparam N_OC = 2 * N_CHAIN;

    // ---- address generator
    wire [IBUF_AW-1:0] ag_addr;
    wire ag_gate, ag_v, ag_first, ag_last, ag_end, ag_latch, ag_busy, ag_done;
    wire [P_W-1:0] ag_p;
    wire [7:0] ag_sub;
    wire shadow_ready, bank_free;
    wire tile_start;
    wire [15:0] tile_px, tile_idx;
    wire [7:0] tile_oct;

    snpu_agen #(.AW(IBUF_AW), .P_W(P_W), .CHAIN_LEN(CHAIN_LEN)) u_agen (
        .clk(clk), .rst(rst),
        .cfg_in_h_i(cfg_in_h_i), .cfg_in_w_i(cfg_in_w_i), .cfg_out_h_i(cfg_out_h_i), .cfg_out_w_i(cfg_out_w_i),
        .cfg_n_icg_i(cfg_n_icg_i), .cfg_n_oct_i(cfg_n_oct_i), .cfg_k_i(cfg_k_i), .cfg_stride_i(cfg_stride_i),
        .cfg_pad_i(cfg_pad_i), .cfg_tile_rows_i(cfg_tile_rows_i), .cfg_n_tiles_i(cfg_n_tiles_i),
        .cfg_ibuf_base_i(cfg_ibuf_base_i), .cfg_plane_words_i(cfg_plane_words_i),
        .cfg_row_base_i(cfg_row_base_i), .cfg_tile0_i(cfg_tile0_i),
        .cfg_oy0_i(cfg_oy0_i), .cfg_out_rows_i(cfg_out_rows_i),
        .start_i(start_i), .busy_o(ag_busy), .done_o(ag_done),
        .shadow_ready_i(shadow_ready), .bank_free_i(bank_free),
        .tile_start_o(tile_start), .tile_px_o(tile_px), .tile_oct_o(tile_oct), .tile_idx_o(tile_idx),
        .addr_o(ag_addr), .gate_o(ag_gate), .v_o(ag_v), .first_o(ag_first), .last_o(ag_last),
        .tile_end_o(ag_end), .p_o(ag_p), .latch_o(ag_latch), .sub_o(ag_sub)
    );

    // ---- input buffer, one cycle of read latency; side band delayed to match
    wire [255:0] ib_data;
    snpu_ibuf #(.IBUF_WORDS(IBUF_WORDS), .AW(IBUF_AW)) u_ibuf (
        .clk(clk), .we_i(ibuf_we_i), .waddr_i(ibuf_waddr_i), .wdata_i(ibuf_wdata_i),
        .raddr_i(ag_addr), .rdata_o(ib_data)
    );

    reg d_gate, d_v, d_first, d_last, d_end, d_latch;
    reg [P_W-1:0] d_p;
    reg [7:0] d_sub;
    always @(posedge clk) begin
        if (rst) begin
            d_gate <= 1'b0; d_v <= 1'b0; d_first <= 1'b0; d_last <= 1'b0; d_end <= 1'b0; d_latch <= 1'b0;
            d_p <= {P_W{1'b0}}; d_sub <= 8'd0;
        end else begin
            d_gate <= ag_gate; d_v <= ag_v; d_first <= ag_first; d_last <= ag_last; d_end <= ag_end;
            d_latch <= ag_latch; d_p <= ag_p; d_sub <= ag_sub;
        end
    end

    // A 32 channel ibuf word feeds 32 / CHAIN_LEN input groups.
    wire [CHAIN_LEN*8-1:0] x_word = ib_data[d_sub * CHAIN_LEN * 8 +: CHAIN_LEN*8];
    wire [CHAIN_LEN*8-1:0] x_vec = d_gate ? {CHAIN_LEN{cfg_zp_in_i}} : x_word;

    // ---- weights
    wire fill_we;
    wire [7:0] fill_chain;
    wire [3:0] fill_sel;
    wire [255:0] fill_data;

    snpu_wfifo #(.N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .FILL_W(256), .FIFO_WORDS(WFIFO_WORDS), .FIFO_AW(WFIFO_AW)) u_wfifo (
        .clk(clk), .rst(rst),
        .w_valid_i(w_valid_i), .w_data_i(w_data_i), .w_ready_o(w_ready_o),
        .start_i(start_i), .latch_i(ag_latch), .shadow_ready_o(shadow_ready),
        .fill_we_o(fill_we), .fill_chain_o(fill_chain), .fill_sel_o(fill_sel), .fill_data_o(fill_data)
    );

    // ---- array
    wire [N_CHAIN*48-1:0] psum;
    wire ps_v, ps_first, ps_last, ps_end;
    wire [P_W-1:0] ps_p;

    snpu_pe_array #(.N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .FILL_W(256), .P_W(P_W)) u_array (
        .clk(clk), .rst(rst),
        .x_i(x_vec), .v_i(d_v), .first_i(d_first), .last_i(d_last), .tile_end_i(d_end), .p_i(d_p),
        .latch_i(d_latch),
        .fill_we_i(fill_we), .fill_chain_i(fill_chain), .fill_sel_i(fill_sel), .fill_data_i(fill_data),
        .psum_o(psum), .v_o(ps_v), .first_o(ps_first), .last_o(ps_last), .tile_end_o(ps_end), .p_o(ps_p),
        .ovfl_o(ovfl_o)
    );

    // ---- accumulator
    wire bank_full, ep_release, ep_re, acc_bank_free, tile_done;
    wire [P_W-1:0] ep_addr;
    wire [N_OC*32-1:0] ep_data;

    // A tile end takes the array latency to reach the accumulator. Until it
    // lands the bank is still the one being written, so the next tile must
    // not start.
    reg end_pending;
    always @(posedge clk) begin
        if (rst)
            end_pending <= 1'b0;
        else if (ag_end)
            end_pending <= 1'b1;
        else if (tile_done)
            end_pending <= 1'b0;
    end
    // The bank free flag is registered before it reaches the address
    // generator. Every 1 to 0 edge of the flag follows an ag_end pulse that
    // the generator already sees in its own output pipeline, so the one
    // cycle lag can only delay a start, never allow an early one.
    reg bank_free_q;
    always @(posedge clk) begin
        if (rst)
            bank_free_q <= 1'b0;
        else
            bank_free_q <= acc_bank_free && !end_pending && !ag_end;
    end
    assign bank_free = bank_free_q;

    snpu_acc #(.N_OC(N_OC), .P_MAX(P_MAX), .P_W(P_W)) u_acc (
        .clk(clk), .rst(rst),
        .psum_i(psum), .v_i(ps_v), .first_i(ps_first), .tile_end_i(ps_end), .p_i(ps_p),
        .wr_bank_free_o(acc_bank_free), .tile_done_o(tile_done),
        .rd_bank_full_o(bank_full), .ep_addr_i(ep_addr), .ep_re_i(ep_re), .ep_data_o(ep_data), .ep_release_i(ep_release)
    );

    // ---- epilogue
    wire ep_busy;
    snpu_epilogue #(.N_OC(N_OC), .P_W(P_W), .OC_MAX(OC_MAX)) u_ep (
        .clk(clk), .rst(rst),
        .cfg_silu_i(cfg_silu_i), .cfg_residual_i(cfg_residual_i), .cfg_n_planes_i(cfg_n_planes_i),
        .cfg_zp_out_i(cfg_zp_out_i), .cfg_zp_res_i(cfg_zp_res_i), .cfg_zp_out2_i(cfg_zp_out2_i),
        .cfg_res_mult_a_i(cfg_res_mult_a_i), .cfg_res_shift_a_i(cfg_res_shift_a_i),
        .cfg_res_mult_b_i(cfg_res_mult_b_i), .cfg_res_shift_b_i(cfg_res_shift_b_i),
        .prm_we_i(prm_we_i), .prm_addr_i(prm_addr_i), .prm_data_i(prm_data_i),
        .lut_we_i(lut_we_i), .lut_addr_i(lut_addr_i), .lut_data_i(lut_data_i),
        .tile_start_i(tile_start), .tile_px_i(tile_px), .tile_oct_i(tile_oct), .tile_idx_i(tile_idx),
        .bank_full_i(bank_full), .ep_addr_o(ep_addr), .ep_re_o(ep_re), .ep_data_i(ep_data), .ep_release_o(ep_release),
        .res_valid_i(res_valid_i), .res_data_i(res_data_i), .res_ready_o(res_ready_o),
        .drain_start_o(drain_start_o), .drain_oct_o(drain_oct_o),
        .out_valid_o(out_valid_o), .out_data_o(out_data_o), .out_plane_o(out_plane_o), .out_px_o(out_px_o),
        .out_tile_o(out_tile_o), .out_last_o(out_last_o), .out_ready_i(out_ready_i), .busy_o(ep_busy)
    );

    assign busy_o = ag_busy || ep_busy || bank_full;
    assign done_o = ag_done;

endmodule
