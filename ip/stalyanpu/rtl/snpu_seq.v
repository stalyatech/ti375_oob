// =============================================================================
// snpu_seq.v
//
// Descriptor sequencer. Walks the descriptor list in DDR and, for every
// descriptor, drives the DMA and the engines:
//
//   CONV:     fetch descriptor, check CRC, load per channel parameters and
//             the activation table, then per spatial tile: fill the input
//             rows of the tile into the ibuf (sources 0 and 1, upsampled
//             sources row by row), stream the weights, run the conv unit
//             for that tile and, whenever the epilogue starts draining an
//             output channel tile, fetch the residual words of that tile.
//   MAXPOOL5: stream the input planes through the max pool engine.
//
// Output words of the engines are given their DDR address here (plane,
// row and column of the pixel) and go to the write DMA. A descriptor is
// complete when every output word has been acknowledged. The LAST flag or
// the descriptor count ends the list and raises the done interrupt.
//
// Descriptor field positions follow backend/isa.py.
// =============================================================================
`timescale 1ns / 1ps

module snpu_seq #(
    parameter N_CHAIN   = 32,
    parameter CHAIN_LEN = 32,
    parameter IBUF_AW   = 14
)(
    input  wire         clk,
    input  wire         rst,
    // control
    input  wire         start_i,
    input  wire         abort_i,
    input  wire [31:0]  desc_base_i,
    input  wire [31:0]  desc_count_i,
    output reg          busy_o,
    output reg          done_o,          // pulse: list finished
    output reg          desc_done_o,     // pulse: descriptor finished
    output reg          error_o,         // pulse
    output reg  [7:0]   err_code_o,
    output reg  [15:0]  desc_idx_o,
    output wire [31:0]  tag_o,
    // read DMA channel 0 (bulk) and 1 (weights)
    output reg  [1:0]   cmd_valid_o,
    input  wire [1:0]   cmd_ready_i,
    output reg  [63:0]  cmd_addr_o,
    output reg  [63:0]  cmd_len_o,
    output reg  [31:0]  cmd_n0_o,
    output reg  [63:0]  cmd_s0_o,
    output reg  [31:0]  cmd_n1_o,
    output reg  [63:0]  cmd_s1_o,
    output reg  [31:0]  cmd_n2_o,
    output reg  [63:0]  cmd_s2_o,
    output reg  [7:0]   cmd_dst_o,
    // descriptor words from the DMA (destination DESC)
    input  wire         desc_valid_i,
    input  wire [255:0] desc_data_i,
    // loader status
    input  wire         loaders_idle_i,  // prm, lut, ibuf writers idle
    input  wire [31:0]  ibuf_words_i,    // words written since the tile fill started
    // conv unit
    output reg  [15:0]  cfg_in_h_o, cfg_in_w_o, cfg_out_h_o, cfg_out_w_o,
    output reg  [7:0]   cfg_n_icg_o, cfg_n_oct_o, cfg_n_planes_o,
    output reg  [3:0]   cfg_k_o, cfg_stride_o, cfg_pad_o,
    output reg  [7:0]   cfg_zp_in_o, cfg_zp_out_o, cfg_zp_res_o, cfg_zp_out2_o,
    output reg  [15:0]  cfg_tile_rows_o,
    output reg  [IBUF_AW-1:0] cfg_plane_words_o,
    output reg  [15:0]  cfg_row_base_o, cfg_tile0_o, cfg_oy0_o, cfg_out_rows_o,
    output reg          cfg_silu_o, cfg_residual_o,
    output reg  [15:0]  cfg_res_mult_a_o, cfg_res_mult_b_o,
    output reg  [7:0]   cfg_res_shift_a_o, cfg_res_shift_b_o,
    output reg          unit_start_o,
    input  wire         unit_busy_i,
    input  wire         unit_done_i,
    input  wire         drain_start_i,
    input  wire [7:0]   drain_oct_i,
    output reg          ibuf_fill_rst_o,  // resets the ibuf write pointer
    // max pool engine
    output reg          mp_start_o,
    input  wire         mp_busy_i,
    // output address generation
    output reg  [31:0]  out_base_o,       // out_base + oy0 * out_rs for the current tile
    output reg  [31:0]  out_ps_o,
    output reg  [31:0]  out_rs_o,
    output reg  [15:0]  out_w_o,
    input  wire         wr_idle_i,
    // debug view of the state machine
    output wire [4:0]   dbg_state_o
);

    localparam N_OC = 2 * N_CHAIN;
    localparam SUBGROUPS = 32 / CHAIN_LEN;

    // Destination codes shared with the top level.
    localparam DST_DESC = 4'd0, DST_PRM = 4'd1, DST_LUT = 4'd2, DST_IBUF = 4'd3, DST_IBUF_DUP = 4'd4,
               DST_RES = 4'd5, DST_MP = 4'd6, DST_WFIFO = 4'd7, DST_MP_DUP = 4'd8;

    localparam OP_CONV = 8'h01, OP_MAXPOOL5 = 8'h02, OP_END = 8'hFF;
    localparam ISA_VERSION = 8'd1;

    // Descriptor registers.
    reg [31:0] d [0:31];
    wire [7:0]  op       = d[0][7:0];
    wire [15:0] flags    = d[0][23:8];
    wire        f_silu = flags[0], f_res = flags[1], f_irq = flags[2], f_last = flags[3];
    wire        f_ups0 = flags[4], f_ups1 = flags[5], f_two = flags[6];
    wire [15:0] in_h = d[1][15:0], in_w = d[1][31:16], out_h = d[2][15:0], out_w = d[2][31:16];
    wire [15:0] ic = d[3][15:0], oc = d[3][31:16];
    wire [15:0] src0_planes = d[7][15:0], src1_planes = d[7][31:16];
    wire [15:0] tile_rows = d[24][15:0];
    wire [15:0] n_tiles = d[25][15:0];
    wire [3:0]  k = d[27][3:0], stride = d[27][7:4];
    wire [7:0]  pad = d[26][7:0];
    assign tag_o = d[30];

    wire [15:0] n_icg = (ic + CHAIN_LEN - 1) / CHAIN_LEN;
    wire [15:0] n_oct = (oc + N_OC - 1) / N_OC;
    wire [15:0] n_planes = (oc + 31) / 32;

    // State machine.
    localparam S_IDLE = 5'd0, S_FETCH = 5'd1, S_FETCH_WAIT = 5'd2, S_CRC = 5'd3, S_DECODE = 5'd4,
               S_PRM = 5'd5, S_LUT = 5'd6, S_LOAD_WAIT = 5'd7, S_TILE = 5'd8, S_FILL = 5'd9,
               S_FILL_WAIT = 5'd10, S_WEIGHTS = 5'd11, S_RUN = 5'd12, S_RUN_WAIT = 5'd13,
               S_NEXT_TILE = 5'd14, S_DESC_END = 5'd15, S_MP = 5'd16, S_MP_WAIT = 5'd17, S_DONE = 5'd18,
               S_ERROR = 5'd19;
    reg [4:0] state;
    assign dbg_state_o = state;
    reg [31:0] desc_addr;
    reg [15:0] idx;
    reg [1:0]  fetch_words;
    // CRC.
    reg [31:0] crc;
    reg [6:0]  crc_byte;
    reg [2:0]  crc_bit;
    wire [7:0] crc_data = d[crc_byte[6:2]][crc_byte[1:0]*8 +: 8];
    wire [31:0] crc_cur = (crc_bit == 3'd0) ? (crc ^ {24'd0, crc_data}) : crc;
    // Tile geometry.
    reg [15:0] tile, oy0, rows, r_lo, r_hi, rows_in;
    reg [15:0] fill_plane, fill_row;
    reg        fill_src;
    reg [31:0] fill_words;
    reg [15:0] fill_planes_total;
    // Residual issue.
    reg        res_pending;
    reg [7:0]  res_oct;

    // Helpers.
    // The input row range of a tile is derived in three registered steps
    // (last output row, raw range, clamp) so no cycle holds a multiply and
    // the compares together.
    reg [15:0] oy_last_q;
    reg signed [17:0] rls_q, rhs_q;
    reg [2:0] rphase;
    // Products used by the command addresses, registered continuously so no
    // command issue cycle carries a multiplier. Every operand settles
    // several cycles before its product is consumed.
    reg [31:0] t_rl0, t_rl1, t_rlh0, t_rlh1, t_len0, t_len1, t_pw, t_ob, t_res_row, t_wlen, t_hw;
    // Running terms of the fill addresses and the residual commands.
    reg [31:0] f_pterm, f_rterm, res_term;
    reg [15:0] res_left, oy0_run;
    wire signed [17:0] r_lo_s = $signed({2'b0, oy0}) * $signed({14'b0, stride}) - $signed({10'b0, pad});
    wire signed [17:0] r_hi_s = $signed({2'b0, oy_last_q}) * $signed({14'b0, stride}) - $signed({10'b0, pad}) + $signed({14'b0, k});

    always @(posedge clk) begin
        t_rl0 <= r_lo * d[6];
        t_rl1 <= r_lo * d[10];
        t_rlh0 <= (r_lo >> 1) * d[6];
        t_rlh1 <= (r_lo >> 1) * d[10];
        t_len0 <= rows_in * d[6];
        t_len1 <= rows_in * d[10];
        t_pw <= rows_in * in_w;
        t_ob <= oy0 * d[17];
        t_res_row <= oy0 * d[20];
        t_wlen <= d[12] * n_oct;
        t_hw <= in_h * in_w;
    end

    task set_cmd;
        input       ch;
        input [31:0] addr;
        input [31:0] len;
        input [15:0] c0; input [31:0] st0;
        input [15:0] c1; input [31:0] st1;
        input [15:0] c2; input [31:0] st2;
        input [3:0] dst;
        begin
            cmd_valid_o[ch] <= 1'b1;
            cmd_addr_o[ch*32 +: 32] <= addr;
            cmd_len_o[ch*32 +: 32] <= len;
            cmd_n0_o[ch*16 +: 16] <= c0; cmd_s0_o[ch*32 +: 32] <= st0;
            cmd_n1_o[ch*16 +: 16] <= c1; cmd_s1_o[ch*32 +: 32] <= st1;
            cmd_n2_o[ch*16 +: 16] <= c2; cmd_s2_o[ch*32 +: 32] <= st2;
            cmd_dst_o[ch*4 +: 4] <= dst;
        end
    endtask

    integer j;
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; busy_o <= 1'b0; done_o <= 1'b0; desc_done_o <= 1'b0; error_o <= 1'b0;
            err_code_o <= 8'd0; desc_idx_o <= 16'd0; cmd_valid_o <= 2'b00;
            cmd_addr_o <= 64'd0; cmd_len_o <= 64'd0; cmd_n0_o <= 32'd0; cmd_s0_o <= 64'd0; cmd_n1_o <= 32'd0;
            cmd_s1_o <= 64'd0; cmd_n2_o <= 32'd0; cmd_s2_o <= 64'd0; cmd_dst_o <= 8'd0;
            unit_start_o <= 1'b0; mp_start_o <= 1'b0; ibuf_fill_rst_o <= 1'b0;
            desc_addr <= 32'd0; idx <= 16'd0; fetch_words <= 2'd0; crc <= 32'hFFFFFFFF; crc_byte <= 7'd0; crc_bit <= 3'd0;
            tile <= 16'd0; oy0 <= 16'd0; rows <= 16'd0; r_lo <= 16'd0; r_hi <= 16'd0; rows_in <= 16'd0;
            oy_last_q <= 16'd0; rls_q <= 18'sd0; rhs_q <= 18'sd0; rphase <= 3'd0;
            f_pterm <= 32'd0; f_rterm <= 32'd0; res_term <= 32'd0; res_left <= 16'd0; oy0_run <= 16'd0;
            fill_plane <= 16'd0; fill_row <= 16'd0; fill_src <= 1'b0; fill_words <= 32'd0; fill_planes_total <= 16'd0;
            res_pending <= 1'b0; res_oct <= 8'd0;
            cfg_in_h_o <= 16'd0; cfg_in_w_o <= 16'd0; cfg_out_h_o <= 16'd0; cfg_out_w_o <= 16'd0;
            cfg_n_icg_o <= 8'd0; cfg_n_oct_o <= 8'd0; cfg_n_planes_o <= 8'd0; cfg_k_o <= 4'd0; cfg_stride_o <= 4'd0;
            cfg_pad_o <= 4'd0; cfg_zp_in_o <= 8'd0; cfg_zp_out_o <= 8'd0; cfg_zp_res_o <= 8'd0; cfg_zp_out2_o <= 8'd0;
            cfg_tile_rows_o <= 16'd0; cfg_plane_words_o <= {IBUF_AW{1'b0}}; cfg_row_base_o <= 16'd0; cfg_tile0_o <= 16'd0;
            cfg_oy0_o <= 16'd0; cfg_out_rows_o <= 16'd0;
            cfg_silu_o <= 1'b0; cfg_residual_o <= 1'b0; cfg_res_mult_a_o <= 16'd0; cfg_res_mult_b_o <= 16'd0;
            cfg_res_shift_a_o <= 8'd0; cfg_res_shift_b_o <= 8'd0;
            out_base_o <= 32'd0; out_ps_o <= 32'd0; out_rs_o <= 32'd0; out_w_o <= 16'd0;
            for (j = 0; j < 32; j = j + 1) d[j] <= 32'd0;
        end else begin
            done_o <= 1'b0; desc_done_o <= 1'b0; error_o <= 1'b0;
            unit_start_o <= 1'b0; mp_start_o <= 1'b0; ibuf_fill_rst_o <= 1'b0;
            // Command handshakes.
            for (j = 0; j < 2; j = j + 1)
                if (cmd_valid_o[j] && cmd_ready_i[j])
                    cmd_valid_o[j] <= 1'b0;
            // Residual fetch request from the epilogue (queued, one at a time).
            if (drain_start_i && cfg_residual_o) begin
                res_pending <= 1'b1;
                res_oct <= drain_oct_i;
            end
            if (res_pending && !cmd_valid_o[0] && cmd_ready_i[0] && (state == S_RUN_WAIT)) begin
                // Words in emission order: planes of the oct, rows, columns.
                // A row of one plane is one contiguous chunk.
                set_cmd(1'b0, d[18] + res_term + t_res_row, {11'd0, out_w, 5'd0},
                        rows, d[20],
                        (res_left < (N_OC / 32)) ? res_left : (N_OC / 32), d[19],
                        16'd1, 32'd0, DST_RES);
                res_term <= res_term + (N_OC / 32) * d[19];
                res_left <= res_left - (N_OC / 32);
                res_pending <= 1'b0;
            end
            if (abort_i && state != S_IDLE) begin
                state <= S_IDLE;
                busy_o <= 1'b0;
            end else
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        busy_o <= 1'b1;
                        idx <= 16'd0;
                        desc_addr <= desc_base_i;
                        state <= (desc_count_i == 0) ? S_DONE : S_FETCH;
                    end
                end
                S_FETCH: begin
                    if (!cmd_valid_o[0] && cmd_ready_i[0]) begin
                        set_cmd(1'b0, desc_addr, 32'd128, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_DESC);
                        fetch_words <= 2'd0;
                        state <= S_FETCH_WAIT;
                    end
                end
                S_FETCH_WAIT: begin
                    if (desc_valid_i) begin
                        for (j = 0; j < 8; j = j + 1)
                            d[fetch_words * 8 + j] <= desc_data_i[j*32 +: 32];
                        fetch_words <= fetch_words + 1'b1;
                        if (fetch_words == 2'd3) begin
                            state <= S_CRC;
                            crc <= 32'hFFFFFFFF; crc_byte <= 7'd0; crc_bit <= 3'd0;
                        end
                    end
                end
                S_CRC: begin
                    // Bit serial CRC32 (reflected polynomial) over the 124 bytes of
                    // words 0..30: the byte enters the register once, then eight
                    // shift steps follow.
                    if (crc_cur[0])
                        crc <= (crc_cur >> 1) ^ 32'hEDB88320;
                    else
                        crc <= crc_cur >> 1;
                    if (crc_bit == 3'd7) begin
                        crc_bit <= 3'd0;
                        if (crc_byte == 7'd123)
                            state <= S_DECODE;
                        else
                            crc_byte <= crc_byte + 1'b1;
                    end else begin
                        crc_bit <= crc_bit + 1'b1;
                    end
                end
                S_DECODE: begin
                    desc_idx_o <= idx;
                    if ((crc ^ 32'hFFFFFFFF) != d[31]) begin
                        err_code_o <= 8'd2; state <= S_ERROR;
                    end else if (d[0][31:24] != ISA_VERSION) begin
                        err_code_o <= 8'd3; state <= S_ERROR;
                    end else if (op == OP_END) begin
                        state <= S_DONE;
                    end else if (op == OP_CONV) begin
                        cfg_in_h_o <= in_h; cfg_in_w_o <= in_w; cfg_out_h_o <= out_h; cfg_out_w_o <= out_w;
                        cfg_n_icg_o <= n_icg[7:0]; cfg_n_oct_o <= n_oct[7:0]; cfg_n_planes_o <= n_planes[7:0];
                        cfg_k_o <= k; cfg_stride_o <= stride; cfg_pad_o <= pad[3:0];
                        cfg_zp_in_o <= d[21][7:0]; cfg_zp_out_o <= d[21][15:8]; cfg_zp_res_o <= d[21][23:16]; cfg_zp_out2_o <= d[21][31:24];
                        cfg_tile_rows_o <= tile_rows;
                        cfg_silu_o <= f_silu; cfg_residual_o <= f_res;
                        cfg_res_mult_a_o <= d[22][15:0]; cfg_res_shift_a_o <= d[22][23:16];
                        cfg_res_mult_b_o <= d[23][15:0]; cfg_res_shift_b_o <= d[23][23:16];
                        out_ps_o <= d[16]; out_rs_o <= d[17]; out_w_o <= out_w;
                        state <= S_PRM;
                    end else if (op == OP_MAXPOOL5) begin
                        out_ps_o <= d[16]; out_rs_o <= d[17]; out_w_o <= out_w; out_base_o <= d[15];
                        state <= S_MP;
                    end else begin
                        err_code_o <= 8'd1; state <= S_ERROR;
                    end
                end
                S_PRM: begin
                    if (!cmd_valid_o[0] && cmd_ready_i[0]) begin
                        set_cmd(1'b0, d[13], n_oct * N_OC * 8, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_PRM);
                        state <= f_silu ? S_LUT : S_LOAD_WAIT;
                    end
                end
                S_LUT: begin
                    if (!cmd_valid_o[0] && cmd_ready_i[0]) begin
                        set_cmd(1'b0, d[14], 32'd256, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_LUT);
                        state <= S_LOAD_WAIT;
                    end
                end
                S_LOAD_WAIT: begin
                    if (!cmd_valid_o[0] && cmd_ready_i[0] && loaders_idle_i) begin
                        tile <= 16'd0;
                        oy0_run <= 16'd0;
                        state <= S_TILE;
                    end
                end
                S_TILE: begin
                    // Geometry of the tile; oy0_run tracks tile * tile_rows.
                    oy0 <= oy0_run;
                    rows <= ((out_h-oy0_run) < tile_rows) ? (out_h-oy0_run) : tile_rows;
                    fill_plane <= 16'd0; fill_row <= 16'd0; fill_src <= 1'b0; fill_words <= 32'd0;
                    fill_planes_total <= src0_planes + (f_two ? src1_planes : 16'd0);
                    ibuf_fill_rst_o <= 1'b1;
                    state <= S_FILL;
                    // r_lo and r_hi need oy0 and rows, computed over the
                    // next three cycles.
                    r_lo <= 16'd0; r_hi <= 16'd0; rphase <= 3'd0;
                end
                S_FILL: begin
                    // Derive the input row range from oy0 and rows first.
                    if (rphase == 3'd0) begin
                        oy_last_q <= oy0 + rows - 16'd1;
                        rphase <= 3'd1;
                    end else if (rphase == 3'd1) begin
                        rls_q <= r_lo_s;
                        rhs_q <= r_hi_s;
                        rphase <= 3'd2;
                    end else if (rphase == 3'd2) begin
                        r_lo <= (rls_q < 0) ? 16'd0 : rls_q[15:0];
                        r_hi <= (rhs_q > $signed({2'b0, in_h})) ? in_h : rhs_q[15:0];
                        rows_in <= ((rhs_q > $signed({2'b0, in_h})) ? in_h : rhs_q[15:0]) - ((rls_q < 0) ? 16'd0 : rls_q[15:0]);
                        rphase <= 3'd3;
                    end else if (rphase == 3'd3) begin
                        // One cycle for the continuous products to settle.
                        rphase <= 3'd4;
                    end else if (rphase == 3'd4) begin
                        f_pterm <= 32'd0;
                        f_rterm <= t_rlh0;
                        rphase <= 3'd5;
                    end else if (fill_plane == fill_planes_total) begin
                        state <= S_FILL_WAIT;
                    end else if (!cmd_valid_o[0] && cmd_ready_i[0]) begin
                        // One command per plane; upsampled sources go row by row
                        // (source row = ibuf row / 2, every word written twice).
                        if (fill_src == 1'b0 && fill_plane == src0_planes) begin
                            fill_src <= 1'b1;
                            f_pterm <= 32'd0;
                            f_rterm <= t_rlh1;
                        end else if (fill_src ? f_ups1 : f_ups0) begin
                            set_cmd(1'b0, (fill_src ? d[8] : d[4]) + f_pterm + f_rterm,
                                    (in_w >> 1) * 32, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_IBUF_DUP);
                            fill_words <= fill_words + in_w;
                            if (fill_row + 1 == rows_in) begin
                                fill_row <= 16'd0;
                                fill_plane <= fill_plane + 1'b1;
                                f_pterm <= f_pterm + (fill_src ? d[9] : d[5]);
                                f_rterm <= fill_src ? t_rlh1 : t_rlh0;
                            end else begin
                                fill_row <= fill_row + 1'b1;
                                if (r_lo[0] ^ fill_row[0])
                                    f_rterm <= f_rterm + (fill_src ? d[10] : d[6]);
                            end
                        end else begin
                            set_cmd(1'b0, (fill_src ? d[8] : d[4]) + f_pterm + (fill_src ? t_rl1 : t_rl0),
                                    fill_src ? t_len1 : t_len0, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_IBUF);
                            fill_words <= fill_words + t_pw;
                            fill_plane <= fill_plane + 1'b1;
                            f_pterm <= f_pterm + (fill_src ? d[9] : d[5]);
                        end
                    end
                end
                S_FILL_WAIT: begin
                    if (!cmd_valid_o[0] && cmd_ready_i[0] && (ibuf_words_i == fill_words))
                        state <= S_WEIGHTS;
                end
                S_WEIGHTS: begin
                    if (!cmd_valid_o[1] && cmd_ready_i[1]) begin
                        set_cmd(1'b1, d[11], t_wlen, 16'd1, 32'd0, 16'd1, 32'd0, 16'd1, 32'd0, DST_WFIFO);
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    cfg_row_base_o <= r_lo;
                    cfg_tile0_o <= tile;
                    cfg_oy0_o <= oy0;
                    cfg_out_rows_o <= rows;
                    cfg_plane_words_o <= t_pw[IBUF_AW-1:0];
                    out_base_o <= d[15] + t_ob;
                    res_term <= 32'd0;
                    res_left <= n_planes;
                    unit_start_o <= 1'b1;
                    state <= S_RUN_WAIT;
                end
                S_RUN_WAIT: begin
                    if (!unit_busy_i && !unit_start_o && !res_pending && wr_idle_i && cmd_ready_i[0] && cmd_ready_i[1]
                        && !cmd_valid_o[0] && !cmd_valid_o[1])
                        state <= S_NEXT_TILE;
                end
                S_NEXT_TILE: begin
                    if (tile + 1 == n_tiles) begin
                        state <= S_DESC_END;
                    end else begin
                        tile <= tile + 1'b1;
                        oy0_run <= oy0_run + tile_rows;
                        state <= S_TILE;
                    end
                end
                S_MP: begin
                    // Plain source: every plane is one contiguous chunk. Upsampled
                    // source: one chunk per output row, source row = row / 2, every
                    // word delivered twice (in_w = 2 * source width).
                    if (!cmd_valid_o[0] && cmd_ready_i[0]) begin
                        cfg_in_h_o <= in_h; cfg_in_w_o <= in_w; cfg_n_planes_o <= src0_planes[7:0];
                        mp_start_o <= 1'b1;
                        if (f_ups0) begin
                            set_cmd(1'b0, d[4], (in_w >> 1) * 32, 16'd2, 32'd0, in_h >> 1, d[6], src0_planes, d[5], DST_MP_DUP);
                        end else begin
                            set_cmd(1'b0, d[4], t_hw << 5, src0_planes, d[5], 16'd1, 32'd0, 16'd1, 32'd0, DST_MP);
                        end
                        state <= S_MP_WAIT;
                    end
                end
                S_MP_WAIT: begin
                    if (!mp_busy_i && !mp_start_o && wr_idle_i && cmd_ready_i[0] && !cmd_valid_o[0])
                        state <= S_DESC_END;
                end
                S_DESC_END: begin
                    desc_done_o <= 1'b1;
                    if (f_last || (idx + 1 >= desc_count_i)) begin
                        state <= S_DONE;
                    end else begin
                        idx <= idx + 1'b1;
                        desc_addr <= desc_addr + 32'd128;
                        state <= S_FETCH;
                    end
                end
                S_DONE: begin
                    done_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= S_IDLE;
                end
                S_ERROR: begin
                    error_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
