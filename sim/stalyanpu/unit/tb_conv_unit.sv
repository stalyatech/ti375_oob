// =============================================================================
// tb_conv_unit.sv
//
// Layer level test of snpu_conv_unit. The vector directory (plusarg
// +VEC=<dir>) written by stalyanpu.golden.unit holds the configuration,
// the ibuf image, the weight stream, parameters, table, residual words and
// the expected output words in emission order.
//
// The weight and residual streams see random valid gaps, the output sees
// random ready stalls (+BACKPRESSURE=1). Every output word is compared with
// the golden word and its plane / pixel / tile tags with the expected
// emission order.
// =============================================================================
`timescale 1ns / 1ps
`include "tb_util.svh"

module tb_conv_unit;

    parameter N_CHAIN    = 16;
    parameter CHAIN_LEN  = 16;
    parameter P_MAX      = 256;
    parameter P_W        = 8;
    parameter IBUF_WORDS = 2048;
    parameter IBUF_AW    = 11;
    parameter WFIFO_WORDS = 256;
    parameter WFIFO_AW   = 8;

    localparam N_OC = 2 * N_CHAIN;
    localparam MAXW = 1 << 16;

    reg clk = 1'b0;
    always #2.0 clk = ~clk;
    reg rst = 1'b1;

    // Vector storage.
    reg [31:0]  cfg [0:31];
    reg [255:0] ibuf_img [0:MAXW-1];
    reg [255:0] w_img [0:MAXW-1];
    reg [63:0]  prm_img [0:1023];
    reg [7:0]   lut_img [0:255];
    reg [255:0] res_img [0:MAXW-1];
    reg [255:0] gold [0:MAXW-1];

    // DUT ports.
    reg  ibuf_we = 0; reg [IBUF_AW-1:0] ibuf_waddr = 0; reg [255:0] ibuf_wdata = 0;
    reg  w_valid = 0; reg [255:0] w_data = 0; wire w_ready;
    reg  prm_we = 0; reg [9:0] prm_addr = 0; reg [63:0] prm_data = 0;
    reg  lut_we = 0; reg [7:0] lut_addr = 0; reg [7:0] lut_data = 0;
    reg  res_valid = 0; reg [255:0] res_data = 0; wire res_ready;
    wire out_valid; wire [255:0] out_data; wire [7:0] out_plane; wire [15:0] out_px, out_tile; wire out_last;
    reg  out_ready = 0;
    reg  start = 0;
    wire busy, done, ovfl;

    snpu_conv_unit #(
        .N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .P_MAX(P_MAX), .P_W(P_W),
        .IBUF_WORDS(IBUF_WORDS), .IBUF_AW(IBUF_AW), .WFIFO_WORDS(WFIFO_WORDS), .WFIFO_AW(WFIFO_AW)
    ) u_dut (
        .clk(clk), .rst(rst),
        .cfg_in_h_i(cfg[0][15:0]), .cfg_in_w_i(cfg[1][15:0]), .cfg_out_h_i(cfg[2][15:0]), .cfg_out_w_i(cfg[3][15:0]),
        .cfg_n_icg_i(cfg[10][7:0]), .cfg_n_oct_i(cfg[11][7:0]), .cfg_n_planes_i(cfg[12][7:0]),
        .cfg_k_i(cfg[6][3:0]), .cfg_stride_i(cfg[7][3:0]), .cfg_pad_i(cfg[8][3:0]), .cfg_zp_in_i(cfg[9][7:0]),
        .cfg_tile_rows_i(cfg[22][15:0]), .cfg_n_tiles_i(cfg[23][15:0]),
        .cfg_ibuf_base_i({IBUF_AW{1'b0}}), .cfg_plane_words_i(cfg[28][IBUF_AW-1:0]),
        .cfg_row_base_i(16'd0), .cfg_tile0_i(16'd0), .cfg_oy0_i(16'd0), .cfg_out_rows_i(cfg[2][15:0]),
        .cfg_silu_i(cfg[13][0]), .cfg_residual_i(cfg[14][0]),
        .cfg_zp_out_i(cfg[15][7:0]), .cfg_zp_res_i(cfg[16][7:0]), .cfg_zp_out2_i(cfg[17][7:0]),
        .cfg_res_mult_a_i(cfg[18][15:0]), .cfg_res_shift_a_i(cfg[19][7:0]),
        .cfg_res_mult_b_i(cfg[20][15:0]), .cfg_res_shift_b_i(cfg[21][7:0]),
        .start_i(start), .busy_o(busy), .done_o(done),
        .ibuf_we_i(ibuf_we), .ibuf_waddr_i(ibuf_waddr), .ibuf_wdata_i(ibuf_wdata),
        .w_valid_i(w_valid), .w_data_i(w_data), .w_ready_o(w_ready),
        .prm_we_i(prm_we), .prm_addr_i(prm_addr), .prm_data_i(prm_data),
        .lut_we_i(lut_we), .lut_addr_i(lut_addr), .lut_data_i(lut_data),
        .res_valid_i(res_valid), .res_data_i(res_data), .res_ready_o(res_ready),
        .out_valid_o(out_valid), .out_data_o(out_data), .out_plane_o(out_plane), .out_px_o(out_px),
        .out_tile_o(out_tile), .out_last_o(out_last), .out_ready_i(out_ready), .ovfl_o(ovfl)
    );

    integer errors = 0, checks = 0;
    integer seed = 1, bp = 0;
    integer n_out, n_w, n_res, n_ibuf, n_prm;
    integer wi = 0, ri = 0, oi = 0;
    reg [1023:0] vec;

    // Expected emission order bookkeeping.
    integer e_tile, e_oct, e_px, e_win, e_rows_left, e_rows, e_plane;
    integer out_h, out_w, tile_rows, n_oct, n_planes, wins;

    task next_expected;
        begin
            // advance (tile, oct, px, win) skipping invalid planes
            e_win = e_win + 1;
            while (e_win < wins && (e_oct * wins + e_win) >= n_planes) e_win = e_win + 1;
            if (e_win >= wins) begin
                e_win = 0;
                if (e_px == e_rows * out_w - 1) begin
                    e_px = 0;
                    if (e_oct == n_oct - 1) begin
                        e_oct = 0;
                        e_tile = e_tile + 1;
                        e_rows_left = e_rows_left-e_rows;
                        e_rows = (e_rows_left < tile_rows) ? e_rows_left : tile_rows;
                    end else begin
                        e_oct = e_oct + 1;
                    end
                end else begin
                    e_px = e_px + 1;
                end
            end
        end
    endtask

    // Weight stream driver.
    always @(posedge clk) begin
        if (!rst) begin
            if (w_valid && w_ready) begin
                wi <= wi + 1;
            end
            if (!w_valid || w_ready) begin
                if (wi + (w_valid && w_ready ? 1 : 0) < n_w && ($urandom % 4 != 0 || !bp)) begin
                    w_valid <= 1'b1;
                    w_data <= w_img[wi + (w_valid && w_ready ? 1 : 0)];
                end else begin
                    w_valid <= 1'b0;
                end
            end
        end
    end

    // Residual stream driver.
    always @(posedge clk) begin
        if (!rst) begin
            if (res_valid && res_ready)
                ri <= ri + 1;
            if (!res_valid || res_ready) begin
                if (ri + (res_valid && res_ready ? 1 : 0) < n_res && ($urandom % 3 != 0 || !bp)) begin
                    res_valid <= 1'b1;
                    res_data <= res_img[ri + (res_valid && res_ready ? 1 : 0)];
                end else begin
                    res_valid <= 1'b0;
                end
            end
        end
    end

    // Output checker.
    always @(posedge clk) begin
        if (!rst) begin
            out_ready <= bp ? ($urandom % 3 != 0) : 1'b1;
            if (out_valid && out_ready) begin
                `TB_CHECK(out_data == gold[oi], "output word mismatch")
                `TB_CHECK(out_tile == e_tile, "tile tag mismatch")
                `TB_CHECK(out_plane == e_oct * wins + e_win, "plane tag mismatch")
                `TB_CHECK(out_px == e_px, "pixel tag mismatch")
                if (out_data != gold[oi] && errors <= 40)
                    $display("  mismatch word %0d (tile %0d plane %0d px %0d)", oi, out_tile, out_plane, out_px);
                if (errors == 1 && out_data != gold[oi])
                    $display("  word %0d tile %0d plane %0d px %0d\n  got %h\n  exp %h", oi, out_tile, out_plane, out_px, out_data, gold[oi]);
                if (errors == 1 && (out_tile != e_tile || out_plane != e_oct * wins + e_win || out_px != e_px))
                    $display("  word %0d tags got t%0d p%0d px%0d exp t%0d p%0d px%0d", oi, out_tile, out_plane, out_px, e_tile, e_oct * wins + e_win, e_px);
                oi <= oi + 1;
                next_expected();
            end
        end
    end

    // Debug trace of the accumulator input for pixel 0 (+DEBUG=1).
    integer dbg = 0;
    always @(posedge clk) begin
        if (dbg && u_dut.u_acc.v_i && u_dut.u_acc.p_i == 0)
            $display("DBG acc p0 first=%0d end=%0d psum0=%0d psum1=%0d psum2=%0d", u_dut.u_acc.first_i, u_dut.u_acc.tile_end_i,
                     $signed(u_dut.u_acc.psum_i[23:0]), $signed(u_dut.u_acc.psum_i[47:24]), $signed(u_dut.u_acc.psum_i[71:48]));
        if (dbg && u_dut.d_v && u_dut.d_p == 0)
            $display("DBG x p0 gate=%0d first=%0d x0=%0d x1=%0d x15=%0d latch=%0d", u_dut.d_gate, u_dut.d_first,
                     $signed(u_dut.x_vec[7:0]), $signed(u_dut.x_vec[15:8]), $signed(u_dut.x_vec[127:120]), u_dut.d_latch);
        if (dbg && u_dut.u_ep.out_valid_o && u_dut.u_ep.out_ready_i && u_dut.u_ep.out_px_o == 0)
            $display("DBG ep p0 plane=%0d acc0=%0d acc1=%0d", u_dut.u_ep.out_plane_o, 0, 0);
    end

    always @(posedge clk) begin
        if (dbg > 1 && u_dut.u_wfifo.fill_we_o)
            $display("DBG fill t=%0t chain=%0d sel=%0d data_lo=%h wp=%0d rp=%0d", $time, u_dut.u_wfifo.fill_chain_o, u_dut.u_wfifo.fill_sel_o,
                     u_dut.u_wfifo.fill_data_o[63:0], u_dut.u_wfifo.wp, u_dut.u_wfifo.rp);
        if (dbg > 1 && u_dut.u_array.latch_i)
            $display("DBG latch t=%0t shadow c0: %h %h %h %h  c1: %h", $time,
                     u_dut.u_array.g_chain[0].u_chain.u_shadow.shadow[0], u_dut.u_array.g_chain[0].u_chain.u_shadow.shadow[1],
                     u_dut.u_array.g_chain[0].u_chain.u_shadow.shadow[2], u_dut.u_array.g_chain[0].u_chain.u_shadow.shadow[3],
                     u_dut.u_array.g_chain[1].u_chain.u_shadow.shadow[0]);
        if (dbg > 1 && w_valid && w_ready)
            $display("DBG wpush t=%0t idx=%0d data_lo=%h", $time, wi, w_data[63:0]);
    end

`ifdef SNPU_SIM_BEHAV
    integer dbg_win = 0;
    always @(posedge clk) begin
        if (dbg > 2 && u_dut.u_array.latch_i) dbg_win <= 40;
        if (dbg > 2 && dbg_win > 0) begin
            dbg_win <= dbg_win - 1;
            $display("DBG dsp t=%0t d0: we=%0d a=%0d b=%0d p=%0d | d1: we=%0d a=%0d b=%0d p=%0d | d15: we=%0d a=%0d b=%0d p=%0d casc_lo=%0d | out_lo=%0d v_o=%0d p_o=%0d",
                     $time,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[0].u_mac.w_we_i, u_dut.u_array.g_chain[0].u_chain.g_dsp[0].u_mac.a_lo_q,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[0].u_mac.b_lo_q, u_dut.u_array.g_chain[0].u_chain.g_dsp[0].u_mac.p_lo_q,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[1].u_mac.w_we_i, u_dut.u_array.g_chain[0].u_chain.g_dsp[1].u_mac.a_lo_q,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[1].u_mac.b_lo_q, u_dut.u_array.g_chain[0].u_chain.g_dsp[1].u_mac.p_lo_q,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[15].u_mac.w_we_i, u_dut.u_array.g_chain[0].u_chain.g_dsp[15].u_mac.a_lo_q,
                     u_dut.u_array.g_chain[0].u_chain.g_dsp[15].u_mac.b_lo_q, u_dut.u_array.g_chain[0].u_chain.g_dsp[15].u_mac.p_lo_q,
                     $signed(u_dut.u_array.g_chain[0].u_chain.g_dsp[15].u_mac.casc_i[23:0]),
                     $signed(u_dut.u_array.g_chain[0].u_chain.psum_lo_o), u_dut.u_array.v_o, u_dut.u_array.p_o);
        end
    end
`endif

    always @(posedge clk) begin
        if (dbg == 4) begin
            if (u_dut.u_acc.s2_end)
                $display("DBG t=%0t acc tile_done: wr_bank=%0d full=%b", $time, u_dut.u_acc.wr_bank, u_dut.u_acc.full);
            if (u_dut.u_acc.ep_release_i)
                $display("DBG t=%0t acc release: rd_bank=%0d full=%b", $time, u_dut.u_acc.rd_bank, u_dut.u_acc.full);
            if (u_dut.tile_start)
                $display("DBG t=%0t tile_start oct=%0d px=%0d bank_free=%0d wr_bank=%0d", $time, u_dut.tile_oct, u_dut.tile_px, u_dut.bank_free, u_dut.u_acc.wr_bank);
            if (u_dut.u_acc.s1_v && u_dut.u_acc.s1_end)
                $display("DBG t=%0t acc last write: bank=%0d p=%0d first=%0d sum0=%0d", $time, u_dut.u_acc.s1_bank, u_dut.u_acc.s1_p, u_dut.u_acc.s1_first, $signed(u_dut.u_acc.sum[31:0]));
            if (u_dut.u_acc.s1_v && u_dut.u_acc.s1_p == 0)
                $display("DBG t=%0t acc write p0: bank=%0d first=%0d sum0=%0d", $time, u_dut.u_acc.s1_bank, u_dut.u_acc.s1_first, $signed(u_dut.u_acc.sum[31:0]));
            if (u_dut.u_ep.s0_v && u_dut.u_ep.s0_last)
                $display("DBG t=%0t ep last read px=%0d plane=%0d rd_bank=%0d", $time, u_dut.u_ep.s0_px, u_dut.u_ep.s0_plane, u_dut.u_acc.rd_bank);
            if (u_dut.u_ep.s0_v && u_dut.u_ep.s0_px == 0)
                $display("DBG t=%0t ep first read plane=%0d rd_bank=%0d bank_full=%0d", $time, u_dut.u_ep.s0_plane, u_dut.u_acc.rd_bank, u_dut.u_acc.rd_bank_full_o);
        end
    end

    integer wd_cycles = 400000;
    initial begin
        if ($value$plusargs("WATCHDOG=%d", wd_cycles)) ;
    end
    `TB_WATCHDOG("tb_conv_unit", wd_cycles, clk)

    integer i;
    initial begin
        if (!$value$plusargs("VEC=%s", vec)) vec = "sim/stalyanpu/stim/conv3x3";
        if ($value$plusargs("SEED=%d", seed)) ;
        if ($value$plusargs("BACKPRESSURE=%d", bp)) ;
        if ($value$plusargs("DEBUG=%d", dbg)) ;
        i = $urandom(seed);
        $readmemh({vec, "/cfg.hex"}, cfg);
        $readmemh({vec, "/ibuf.hex"}, ibuf_img);
        $readmemh({vec, "/w.hex"}, w_img);
        $readmemh({vec, "/prm.hex"}, prm_img);
        $readmemh({vec, "/lut.hex"}, lut_img);
        $readmemh({vec, "/res.hex"}, res_img);
        $readmemh({vec, "/golden.hex"}, gold);
        n_ibuf = cfg[24]; n_w = cfg[25]; n_out = cfg[26]; n_res = cfg[27]; n_prm = cfg[29];
        out_h = cfg[2]; out_w = cfg[3]; tile_rows = cfg[22]; n_oct = cfg[11]; n_planes = cfg[12];
        wins = N_OC / 32;
        e_tile = 0; e_oct = 0; e_px = 0; e_win = 0; e_rows_left = out_h;
        e_rows = (e_rows_left < tile_rows) ? e_rows_left : tile_rows;
        $display("vectors %0s: in %0dx%0d ic %0d oc %0d k %0d s %0d tiles %0d out words %0d w words %0d",
                 vec, cfg[0], cfg[1], cfg[4], cfg[5], cfg[6], cfg[7], cfg[23], n_out, n_w);
        if (n_ibuf > IBUF_WORDS) begin
            $display("FAIL: ibuf image %0d words exceeds IBUF_WORDS %0d", n_ibuf, IBUF_WORDS);
            `TB_FINISH("tb_conv_unit")
        end

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // Load ibuf, parameters and table.
        for (i = 0; i < n_ibuf; i = i + 1) begin
            @(negedge clk);
            ibuf_we = 1'b1; ibuf_waddr = i; ibuf_wdata = ibuf_img[i];
        end
        @(negedge clk); ibuf_we = 1'b0;
        for (i = 0; i < n_prm; i = i + 1) begin
            @(negedge clk);
            prm_we = 1'b1; prm_addr = i; prm_data = prm_img[i];
        end
        @(negedge clk); prm_we = 1'b0;
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            lut_we = 1'b1; lut_addr = i; lut_data = lut_img[i];
        end
        @(negedge clk); lut_we = 1'b0;

        // Go. Weights and residual words stream on their own.
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Wait for the last output word.
        while (oi < n_out) @(posedge clk);
        repeat (20) @(posedge clk);
        `TB_CHECK(!busy, "unit still busy after the last word")
        `TB_CHECK(wi == n_w, "weight words not fully consumed")
        `TB_CHECK(ri == n_res, "residual words not fully consumed")
        repeat (50) @(posedge clk);
        `TB_CHECK(!out_valid, "extra output words")
        `TB_FINISH("tb_conv_unit")
    end

endmodule
