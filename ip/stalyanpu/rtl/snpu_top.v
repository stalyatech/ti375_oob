// =============================================================================
// snpu_top.v
//
// StalyaNPU top level: CSR (APB3), descriptor sequencer, read and write
// DMA (one AXI4 master), convolution engine and max pool engine, plus the
// loaders that route DMA words to their destinations and the output address
// generator that turns tagged output words into DDR writes.
//
// Everything runs on one clock; the clock domain crossing of the APB bus
// and of the interrupt is done in the FPGA top level.
// =============================================================================
`timescale 1ns / 1ps

module snpu_top #(
    parameter N_CHAIN     = 32,
    parameter CHAIN_LEN   = 32,
    parameter P_MAX       = 1024,
    parameter P_W         = 10,
    parameter IBUF_WORDS  = 16384,
    parameter IBUF_AW     = 14,
    parameter WFIFO_WORDS = 1024,
    parameter WFIFO_AW    = 10,
    parameter OC_MAX      = 512,
    parameter AXI_DW      = 128,
    parameter MP_MAX_W    = 128,
    parameter MP_W_AW     = 7
)(
    input  wire         clk,
    input  wire         rst,
    // APB3 control
    input  wire [5:0]   paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    output wire [31:0]  prdata_o,
    output wire         pready_o,
    output wire         pslverr_o,
    output wire         irq_o,
    // AXI4 master
    output wire         m_arvalid,
    input  wire         m_arready,
    output wire [31:0]  m_araddr,
    output wire [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output wire [3:0]   m_arid,
    input  wire         m_rvalid,
    output wire         m_rready,
    input  wire [AXI_DW-1:0] m_rdata,
    input  wire [3:0]   m_rid,
    input  wire         m_rlast,
    input  wire [1:0]   m_rresp,
    output wire         m_awvalid,
    input  wire         m_awready,
    output wire [31:0]  m_awaddr,
    output wire [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire [3:0]   m_awid,
    output wire         m_wvalid,
    input  wire         m_wready,
    output wire [AXI_DW-1:0] m_wdata,
    output wire [AXI_DW/8-1:0] m_wstrb,
    output wire         m_wlast,
    input  wire         m_bvalid,
    output wire         m_bready,
    input  wire [1:0]   m_bresp
);

    localparam N_OC = 2 * N_CHAIN;
    localparam DST_DESC = 4'd0, DST_PRM = 4'd1, DST_LUT = 4'd2, DST_IBUF = 4'd3, DST_IBUF_DUP = 4'd4,
               DST_RES = 4'd5, DST_MP = 4'd6, DST_WFIFO = 4'd7, DST_MP_DUP = 4'd8;

    function integer clog2;
        input integer v;
        integer t;
        begin
            t = v - 1;
            for (clog2 = 0; t > 0; clog2 = clog2 + 1)
                t = t >> 1;
        end
    endfunction

    localparam [31:0] GEOMETRY = (((IBUF_WORDS * 32) / 1024) << 20) | (clog2(P_MAX) << 16) | (CHAIN_LEN << 8) | N_CHAIN;

    // ---- CSR
    wire start, abort, soft_rst;
    wire [31:0] desc_base, desc_count;
    wire seq_busy, seq_done, seq_desc_done, seq_error;
    wire [7:0] err_code;
    wire [15:0] desc_idx;
    wire [31:0] tag;

    snpu_csr #(.VERSION(32'h00000100), .GEOMETRY(GEOMETRY)) u_csr (
        .clk(clk), .rst(rst),
        .paddr_i(paddr_i), .psel_i(psel_i), .penable_i(penable_i), .pwrite_i(pwrite_i), .pwdata_i(pwdata_i),
        .prdata_o(prdata_o), .pready_o(pready_o), .pslverr_o(pslverr_o),
        .start_o(start), .abort_o(abort), .soft_rst_o(soft_rst), .desc_base_o(desc_base), .desc_count_o(desc_count),
        .busy_i(seq_busy), .err_code_i(err_code), .desc_idx_i(desc_idx), .tag_i(tag),
        .done_i(seq_done), .desc_done_i(seq_desc_done), .error_i(seq_error), .timeout_i(1'b0),
        .stall_ibuf_i(1'b0), .stall_wgt_i(1'b0), .stall_acc_i(1'b0), .stall_wr_i(1'b0),
        .irq_o(irq_o)
    );

    wire rst_all = rst || soft_rst;

    // ---- read DMA
    wire [1:0]   cmd_valid, cmd_ready;
    wire [63:0]  cmd_addr, cmd_len, cmd_s0, cmd_s1, cmd_s2;
    wire [31:0]  cmd_n0, cmd_n1, cmd_n2;
    wire [7:0]   cmd_dst;
    wire [1:0]   d_valid, d_last, d_ready, rd_busy;
    wire [511:0] d_data;
    wire [7:0]   d_dst;
    wire rd_err;

    snpu_rd_dma #(.AXI_DW(AXI_DW)) u_rd (
        .clk(clk), .rst(rst_all),
        .cmd_valid_i(cmd_valid), .cmd_ready_o(cmd_ready), .cmd_addr_i(cmd_addr), .cmd_len_i(cmd_len),
        .cmd_n0_i(cmd_n0), .cmd_s0_i(cmd_s0), .cmd_n1_i(cmd_n1), .cmd_s1_i(cmd_s1), .cmd_n2_i(cmd_n2), .cmd_s2_i(cmd_s2),
        .cmd_dst_i(cmd_dst),
        .d_valid_o(d_valid), .d_data_o(d_data), .d_dst_o(d_dst), .d_last_o(d_last), .d_ready_i(d_ready), .busy_o(rd_busy),
        .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arid(m_arid), .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rdata(m_rdata),
        .m_rid(m_rid), .m_rlast(m_rlast), .m_rresp(m_rresp), .err_o(rd_err)
    );

    // ---- channel 0 destinations
    wire [255:0] d0 = d_data[255:0];
    wire [3:0]   dst0 = d_dst[3:0];
    wire         v0 = d_valid[0];

    // Parameter loader: four 64-bit entries per word.
    reg        prm_busy;
    reg [1:0]  prm_sub;
    reg [255:0] prm_word;
    reg [9:0]  prm_ptr;
    wire prm_take = v0 && (dst0 == DST_PRM) && !prm_busy;
    // Table loader: 32 bytes per word.
    reg        lut_busy;
    reg [4:0]  lut_sub;
    reg [255:0] lut_word;
    reg [7:0]  lut_ptr;
    wire lut_take = v0 && (dst0 == DST_LUT) && !lut_busy;
    // ibuf writer.
    reg        dup_pending;
    reg [255:0] dup_word;
    reg [IBUF_AW-1:0] ibuf_wptr;
    reg [31:0] ibuf_words;
    wire ibuf_fill_rst;
    wire ibuf_take = v0 && ((dst0 == DST_IBUF) || (dst0 == DST_IBUF_DUP)) && !dup_pending;
    // Residual FIFO (depth 32).
    reg [255:0] rfifo [0:31];
    reg [5:0] rf_wp, rf_rp;
    wire rf_empty = (rf_wp == rf_rp);
    wire rf_full = (rf_wp[4:0] == rf_rp[4:0]) && (rf_wp[5] != rf_rp[5]);
    wire res_take = v0 && (dst0 == DST_RES) && !rf_full;
    // Max pool input, with a holding register for duplicated words.
    wire mp_in_ready;
    reg  mp_dup_pending;
    reg  [255:0] mp_dup_word;
    wire mp_take = v0 && ((dst0 == DST_MP) || (dst0 == DST_MP_DUP)) && mp_in_ready && !mp_dup_pending;
    wire mp_in_valid = mp_take || mp_dup_pending;
    wire [255:0] mp_in_data = mp_dup_pending ? mp_dup_word : d0;
    // Descriptor words.
    wire desc_take = v0 && (dst0 == DST_DESC);

    assign d_ready[0] = (dst0 == DST_DESC) ? 1'b1 :
                        (dst0 == DST_PRM) ? !prm_busy :
                        (dst0 == DST_LUT) ? !lut_busy :
                        (dst0 == DST_IBUF || dst0 == DST_IBUF_DUP) ? !dup_pending :
                        (dst0 == DST_RES) ? !rf_full :
                        (dst0 == DST_MP || dst0 == DST_MP_DUP) ? (mp_in_ready && !mp_dup_pending) : 1'b1;

    wire loaders_idle = !prm_busy && !lut_busy && !dup_pending;

    reg prm_we, lut_we, ibuf_we;
    reg [9:0] prm_addr;
    reg [63:0] prm_data;
    reg [7:0] lut_addr, lut_data;
    reg [IBUF_AW-1:0] ibuf_waddr;
    reg [255:0] ibuf_wdata;

    always @(posedge clk) begin
        if (rst_all) begin
            prm_busy <= 1'b0; prm_sub <= 2'd0; prm_word <= 256'd0; prm_ptr <= 10'd0; prm_we <= 1'b0; prm_addr <= 10'd0; prm_data <= 64'd0;
            lut_busy <= 1'b0; lut_sub <= 5'd0; lut_word <= 256'd0; lut_ptr <= 8'd0; lut_we <= 1'b0; lut_addr <= 8'd0; lut_data <= 8'd0;
            dup_pending <= 1'b0; dup_word <= 256'd0; ibuf_wptr <= {IBUF_AW{1'b0}}; ibuf_words <= 32'd0;
            ibuf_we <= 1'b0; ibuf_waddr <= {IBUF_AW{1'b0}}; ibuf_wdata <= 256'd0;
            rf_wp <= 6'd0; rf_rp <= 6'd0; mp_dup_pending <= 1'b0; mp_dup_word <= 256'd0;
        end else begin
            // Max pool duplicate: the held word is presented once more.
            if (mp_take && dst0 == DST_MP_DUP) begin
                mp_dup_pending <= 1'b1; mp_dup_word <= d0;
            end else if (mp_dup_pending && mp_in_ready) begin
                mp_dup_pending <= 1'b0;
            end
            // Parameters: the pointer restarts after the last word of a block.
            prm_we <= 1'b0;
            if (prm_take) begin
                prm_busy <= 1'b1; prm_sub <= 2'd0; prm_word <= d0;
                if (d_last[0]) prm_ptr <= prm_ptr; // pointer handled below
            end
            if (prm_busy) begin
                prm_we <= 1'b1;
                prm_addr <= prm_ptr;
                prm_data <= prm_word[prm_sub * 64 +: 64];
                prm_ptr <= prm_ptr + 1'b1;
                prm_sub <= prm_sub + 1'b1;
                if (prm_sub == 2'd3) prm_busy <= 1'b0;
            end
            if (desc_take) prm_ptr <= 10'd0;
            // Table.
            lut_we <= 1'b0;
            if (lut_take) begin
                lut_busy <= 1'b1; lut_sub <= 5'd0; lut_word <= d0;
            end
            if (lut_busy) begin
                lut_we <= 1'b1;
                lut_addr <= lut_ptr;
                lut_data <= lut_word[lut_sub * 8 +: 8];
                lut_ptr <= lut_ptr + 1'b1;
                lut_sub <= lut_sub + 1'b1;
                if (lut_sub == 5'd31) lut_busy <= 1'b0;
            end
            if (desc_take) lut_ptr <= 8'd0;
            // ibuf.
            ibuf_we <= 1'b0;
            if (ibuf_fill_rst) begin
                ibuf_wptr <= {IBUF_AW{1'b0}};
                ibuf_words <= 32'd0;
            end
            if (ibuf_take) begin
                ibuf_we <= 1'b1; ibuf_waddr <= ibuf_wptr; ibuf_wdata <= d0;
                ibuf_wptr <= ibuf_wptr + 1'b1;
                ibuf_words <= ibuf_words + 1'b1;
                if (dst0 == DST_IBUF_DUP) begin
                    dup_pending <= 1'b1; dup_word <= d0;
                end
            end else if (dup_pending) begin
                ibuf_we <= 1'b1; ibuf_waddr <= ibuf_wptr; ibuf_wdata <= dup_word;
                ibuf_wptr <= ibuf_wptr + 1'b1;
                ibuf_words <= ibuf_words + 1'b1;
                dup_pending <= 1'b0;
            end
            // Residual FIFO.
            if (res_take) begin
                rfifo[rf_wp[4:0]] <= d0;
                rf_wp <= rf_wp + 1'b1;
            end
            if (res_pop)
                rf_rp <= rf_rp + 1'b1;
        end
    end

    wire res_valid = !rf_empty;
    wire [255:0] res_data = rfifo[rf_rp[4:0]];
    wire res_ready;
    wire res_pop = res_valid && res_ready;

    // ---- sequencer
    wire [15:0] cfg_in_h, cfg_in_w, cfg_out_h, cfg_out_w, cfg_tile_rows, cfg_row_base, cfg_tile0, cfg_oy0, cfg_out_rows;
    wire [7:0]  cfg_n_icg, cfg_n_oct, cfg_n_planes, cfg_zp_in, cfg_zp_out, cfg_zp_res, cfg_zp_out2;
    wire [3:0]  cfg_k, cfg_stride, cfg_pad;
    wire [IBUF_AW-1:0] cfg_plane_words;
    wire cfg_silu, cfg_residual;
    wire [15:0] cfg_res_mult_a, cfg_res_mult_b;
    wire [7:0]  cfg_res_shift_a, cfg_res_shift_b;
    wire unit_start, unit_busy, unit_done, drain_start;
    wire [7:0] drain_oct;
    wire mp_start, mp_busy;
    wire [31:0] out_base, out_ps, out_rs;
    wire [15:0] out_w;
    wire wr_idle;

    snpu_seq #(.N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .IBUF_AW(IBUF_AW)) u_seq (
        .clk(clk), .rst(rst_all),
        .start_i(start), .abort_i(abort), .desc_base_i(desc_base), .desc_count_i(desc_count),
        .busy_o(seq_busy), .done_o(seq_done), .desc_done_o(seq_desc_done), .error_o(seq_error),
        .err_code_o(err_code), .desc_idx_o(desc_idx), .tag_o(tag),
        .cmd_valid_o(cmd_valid), .cmd_ready_i(cmd_ready), .cmd_addr_o(cmd_addr), .cmd_len_o(cmd_len),
        .cmd_n0_o(cmd_n0), .cmd_s0_o(cmd_s0), .cmd_n1_o(cmd_n1), .cmd_s1_o(cmd_s1), .cmd_n2_o(cmd_n2), .cmd_s2_o(cmd_s2),
        .cmd_dst_o(cmd_dst),
        .desc_valid_i(desc_take), .desc_data_i(d0),
        .loaders_idle_i(loaders_idle), .ibuf_words_i(ibuf_words),
        .cfg_in_h_o(cfg_in_h), .cfg_in_w_o(cfg_in_w), .cfg_out_h_o(cfg_out_h), .cfg_out_w_o(cfg_out_w),
        .cfg_n_icg_o(cfg_n_icg), .cfg_n_oct_o(cfg_n_oct), .cfg_n_planes_o(cfg_n_planes),
        .cfg_k_o(cfg_k), .cfg_stride_o(cfg_stride), .cfg_pad_o(cfg_pad),
        .cfg_zp_in_o(cfg_zp_in), .cfg_zp_out_o(cfg_zp_out), .cfg_zp_res_o(cfg_zp_res), .cfg_zp_out2_o(cfg_zp_out2),
        .cfg_tile_rows_o(cfg_tile_rows), .cfg_plane_words_o(cfg_plane_words),
        .cfg_row_base_o(cfg_row_base), .cfg_tile0_o(cfg_tile0), .cfg_oy0_o(cfg_oy0), .cfg_out_rows_o(cfg_out_rows),
        .cfg_silu_o(cfg_silu), .cfg_residual_o(cfg_residual),
        .cfg_res_mult_a_o(cfg_res_mult_a), .cfg_res_mult_b_o(cfg_res_mult_b),
        .cfg_res_shift_a_o(cfg_res_shift_a), .cfg_res_shift_b_o(cfg_res_shift_b),
        .unit_start_o(unit_start), .unit_busy_i(unit_busy), .unit_done_i(unit_done),
        .drain_start_i(drain_start), .drain_oct_i(drain_oct), .ibuf_fill_rst_o(ibuf_fill_rst),
        .mp_start_o(mp_start), .mp_busy_i(mp_busy),
        .out_base_o(out_base), .out_ps_o(out_ps), .out_rs_o(out_rs), .out_w_o(out_w), .wr_idle_i(wr_idle)
    );

    // ---- convolution engine
    wire cu_out_valid, cu_out_last, cu_out_ready;
    wire [255:0] cu_out_data;
    wire [7:0] cu_out_plane;
    wire [15:0] cu_out_px, cu_out_tile;
    wire w_ready;
    wire ovfl;

    snpu_conv_unit #(
        .N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .P_MAX(P_MAX), .P_W(P_W), .IBUF_WORDS(IBUF_WORDS), .IBUF_AW(IBUF_AW),
        .WFIFO_WORDS(WFIFO_WORDS), .WFIFO_AW(WFIFO_AW), .OC_MAX(OC_MAX)
    ) u_unit (
        .clk(clk), .rst(rst_all),
        .cfg_in_h_i(cfg_in_h), .cfg_in_w_i(cfg_in_w), .cfg_out_h_i(cfg_out_h), .cfg_out_w_i(cfg_out_w),
        .cfg_n_icg_i(cfg_n_icg), .cfg_n_oct_i(cfg_n_oct), .cfg_n_planes_i(cfg_n_planes),
        .cfg_k_i(cfg_k), .cfg_stride_i(cfg_stride), .cfg_pad_i(cfg_pad), .cfg_zp_in_i(cfg_zp_in),
        .cfg_tile_rows_i(cfg_tile_rows), .cfg_n_tiles_i(16'd1),
        .cfg_ibuf_base_i({IBUF_AW{1'b0}}), .cfg_plane_words_i(cfg_plane_words),
        .cfg_row_base_i(cfg_row_base), .cfg_tile0_i(cfg_tile0), .cfg_oy0_i(cfg_oy0), .cfg_out_rows_i(cfg_out_rows),
        .cfg_silu_i(cfg_silu), .cfg_residual_i(cfg_residual),
        .cfg_zp_out_i(cfg_zp_out), .cfg_zp_res_i(cfg_zp_res), .cfg_zp_out2_i(cfg_zp_out2),
        .cfg_res_mult_a_i(cfg_res_mult_a), .cfg_res_shift_a_i(cfg_res_shift_a),
        .cfg_res_mult_b_i(cfg_res_mult_b), .cfg_res_shift_b_i(cfg_res_shift_b),
        .start_i(unit_start), .busy_o(unit_busy), .done_o(unit_done),
        .ibuf_we_i(ibuf_we), .ibuf_waddr_i(ibuf_waddr), .ibuf_wdata_i(ibuf_wdata),
        .w_valid_i(d_valid[1] && (d_dst[7:4] == DST_WFIFO)), .w_data_i(d_data[511:256]), .w_ready_o(w_ready),
        .prm_we_i(prm_we), .prm_addr_i(prm_addr), .prm_data_i(prm_data),
        .lut_we_i(lut_we), .lut_addr_i(lut_addr), .lut_data_i(lut_data),
        .res_valid_i(res_valid), .res_data_i(res_data), .res_ready_o(res_ready),
        .drain_start_o(drain_start), .drain_oct_o(drain_oct),
        .out_valid_o(cu_out_valid), .out_data_o(cu_out_data), .out_plane_o(cu_out_plane), .out_px_o(cu_out_px),
        .out_tile_o(cu_out_tile), .out_last_o(cu_out_last), .out_ready_i(cu_out_ready), .ovfl_o(ovfl)
    );
    assign d_ready[1] = w_ready;

    // ---- max pool engine
    wire mp_out_valid, mp_out_ready;
    wire [255:0] mp_out_data;
    wire [7:0] mp_out_plane;
    wire [15:0] mp_out_px;

    snpu_maxpool5 #(.MAX_W(MP_MAX_W), .W_AW(MP_W_AW)) u_mp (
        .clk(clk), .rst(rst_all),
        .cfg_h_i(cfg_in_h), .cfg_w_i(cfg_in_w), .cfg_planes_i(cfg_n_planes),
        .start_i(mp_start), .busy_o(mp_busy),
        .in_valid_i(mp_in_valid), .in_data_i(mp_in_data), .in_ready_o(mp_in_ready),
        .out_valid_o(mp_out_valid), .out_data_o(mp_out_data), .out_plane_o(mp_out_plane), .out_px_o(mp_out_px),
        .out_ready_i(mp_out_ready)
    );

    // ---- output address generation and write DMA
    wire        o_valid = mp_busy ? mp_out_valid : cu_out_valid;
    wire [255:0] o_data = mp_busy ? mp_out_data : cu_out_data;
    wire [7:0]  o_plane = mp_busy ? mp_out_plane : cu_out_plane;
    wire [15:0] o_px = mp_busy ? mp_out_px : cu_out_px;
    wire        o_ready;
    // The busy select is registered before it reaches the epilogue clock
    // enables. Conv and maxpool never produce output in the same descriptor,
    // so the one cycle skew at a descriptor boundary is harmless and it keeps
    // the maxpool state out of the epilogue enable path.
    reg mp_busy_q;
    always @(posedge clk) begin
        if (rst) mp_busy_q <= 1'b0;
        else     mp_busy_q <= mp_busy;
    end
    assign mp_out_ready = mp_busy_q && o_ready;
    assign cu_out_ready = !mp_busy_q && o_ready;

    reg [15:0] t_px, t_row, t_col;
    // Row and column of the word on the bus, derived from the tracked pixel.
    wire px_new = (o_px != t_px);
    wire [15:0] n_col = !px_new ? t_col : (o_px == 16'd0) ? 16'd0 : ((t_col + 1 == out_w) ? 16'd0 : t_col + 1);
    wire [15:0] n_row = !px_new ? t_row : (o_px == 16'd0) ? 16'd0 : ((t_col + 1 == out_w) ? t_row + 1 : t_row);

    // The plane term p * out_ps comes from a table that a walker rebuilds
    // whenever out_ps changes; the walker finishes long before the first
    // output word because the input rows are fetched first. The row term
    // is a running sum advanced with the tracked row, so the address is a
    // plain sum of registered values.
    reg [31:0] pt [0:15];
    reg [31:0] pt_acc, out_ps_q;
    reg [4:0]  pt_i;
    integer pk;
    always @(posedge clk) begin
        if (rst_all) begin
            out_ps_q <= 32'hFFFFFFFF; pt_acc <= 32'd0; pt_i <= 5'd16;
            for (pk = 0; pk < 16; pk = pk + 1)
                pt[pk] <= 32'd0;
        end else if (out_ps_q != out_ps) begin
            out_ps_q <= out_ps;
            pt_acc <= 32'd0;
            pt_i <= 5'd0;
        end else if (pt_i < 5'd16) begin
            pt[pt_i[3:0]] <= pt_acc;
            pt_acc <= pt_acc + out_ps;
            pt_i <= pt_i + 5'd1;
        end
    end

    reg [31:0] t_rowt;
    wire [31:0] n_rowt = !px_new ? t_rowt : (o_px == 16'd0) ? 32'd0 : ((t_col + 1 == out_w) ? t_rowt + out_rs : t_rowt);
    wire [31:0] o_addr = out_base + pt[o_plane[3:0]] + n_rowt + {n_col, 5'd0};

    always @(posedge clk) begin
        if (rst_all) begin
            t_px <= 16'hFFFF; t_row <= 16'd0; t_col <= 16'd0; t_rowt <= 32'd0;
        end else if (o_valid && o_ready) begin
            t_px <= o_px; t_row <= n_row; t_col <= n_col; t_rowt <= n_rowt;
        end
    end

    wire wr_err;
    snpu_wr_dma #(.AXI_DW(AXI_DW)) u_wr (
        .clk(clk), .rst(rst_all),
        .w_valid_i(o_valid), .w_addr_i(o_addr), .w_data_i(o_data), .w_ready_o(o_ready), .idle_o(wr_idle),
        .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awid(m_awid), .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata),
        .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp), .err_o(wr_err)
    );

endmodule
