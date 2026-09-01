// =============================================================================
// tb_npu_net.sv
//
// Descriptor driven test of snpu_top. A vector set written by the golden
// generator (+VEC=<dir>) holds mem.hex (blob, input tensor), golden.hex
// (expected output regions) and regions.txt ("base bytes" per region). The
// bench loads memory, programs the CSR through APB, starts the list, waits
// for the done interrupt and compares every golden region byte by byte.
//
// Memory windows (blob and scratch) are parameters; +BP=0 removes the
// random AXI stalls.
// =============================================================================
`timescale 1ns / 1ps
`include "tb_util.svh"

module tb_npu_net;

    parameter N_CHAIN    = 16;
    parameter CHAIN_LEN  = 16;
    parameter P_MAX      = 256;
    parameter P_W        = 8;
    parameter IBUF_WORDS = 4096;
    parameter IBUF_AW    = 12;
    parameter WFIFO_WORDS = 256;
    parameter WFIFO_AW   = 8;
    parameter AXI_DW     = 128;
    parameter [31:0] WIN0_BASE = 32'h20000000;
    parameter WIN0_WORDS = 1 << 15;
    parameter [31:0] WIN1_BASE = 32'h28000000;
    parameter WIN1_WORDS = 1 << 15;
    parameter MP_MAX_W = 64;
    parameter MP_W_AW = 6;

    reg clk = 1'b0;
    always #2.0 clk = ~clk;
    reg rst = 1'b1;

    // APB.
    reg [5:0] paddr = 0; reg psel = 0, penable = 0, pwrite = 0; reg [31:0] pwdata = 0;
    wire [31:0] prdata; wire pready, pslverr, irq;
    // AXI.
    wire arvalid, arready, rvalid, rready, rlast, awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire [31:0] araddr, awaddr; wire [7:0] arlen, awlen; wire [2:0] arsize, awsize; wire [1:0] arburst, awburst, rresp, bresp;
    wire [3:0] arid, rid, awid; wire [AXI_DW-1:0] rdata, wdata; wire [AXI_DW/8-1:0] wstrb;
    integer mem_errors;

    snpu_top #(
        .N_CHAIN(N_CHAIN), .CHAIN_LEN(CHAIN_LEN), .P_MAX(P_MAX), .P_W(P_W), .IBUF_WORDS(IBUF_WORDS), .IBUF_AW(IBUF_AW),
        .WFIFO_WORDS(WFIFO_WORDS), .WFIFO_AW(WFIFO_AW), .AXI_DW(AXI_DW), .MP_MAX_W(MP_MAX_W), .MP_W_AW(MP_W_AW)
    ) u_dut (
        .clk(clk), .rst(rst),
        .paddr_i(paddr), .psel_i(psel), .penable_i(penable), .pwrite_i(pwrite), .pwdata_i(pwdata),
        .prdata_o(prdata), .pready_o(pready), .pslverr_o(pslverr), .irq_o(irq),
        .m_arvalid(arvalid), .m_arready(arready), .m_araddr(araddr), .m_arlen(arlen), .m_arsize(arsize), .m_arburst(arburst),
        .m_arid(arid), .m_rvalid(rvalid), .m_rready(rready), .m_rdata(rdata), .m_rid(rid), .m_rlast(rlast), .m_rresp(rresp),
        .m_awvalid(awvalid), .m_awready(awready), .m_awaddr(awaddr), .m_awlen(awlen), .m_awsize(awsize), .m_awburst(awburst),
        .m_awid(awid), .m_wvalid(wvalid), .m_wready(wready), .m_wdata(wdata), .m_wstrb(wstrb), .m_wlast(wlast),
        .m_bvalid(bvalid), .m_bready(bready), .m_bresp(bresp)
    );

    integer bp = 1;
    axi4_mem_model #(.AXI_DW(AXI_DW), .WIN0_BASE(WIN0_BASE), .WIN0_WORDS(WIN0_WORDS), .WIN1_BASE(WIN1_BASE), .WIN1_WORDS(WIN1_WORDS)) u_mem (
        .clk(clk), .rst(rst), .bp_i(bp != 0),
        .arvalid(arvalid), .arready(arready), .araddr(araddr), .arlen(arlen), .arid(arid),
        .rvalid(rvalid), .rready(rready), .rdata(rdata), .rid(rid), .rlast(rlast), .rresp(rresp),
        .awvalid(awvalid), .awready(awready), .awaddr(awaddr), .awlen(awlen),
        .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .bvalid(bvalid), .bready(bready), .bresp(bresp), .errors(mem_errors)
    );

    integer errors = 0, checks = 0;
    integer seed = 1;
    reg [1023:0] vec;
    reg [2047:0] line;
    integer fd, rc, n, i, j;
    reg [31:0] word_addr, addr;
    reg [127:0] w128;

    // Load a 128-bit word hex file with @ address lines into the memory model.
    task load_hex;
        input [1023:0] path;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("FAIL: cannot open %0s", path);
                `TB_FINISH("tb_npu_net")
            end
            addr = 32'd0;
            n = 0;
            while (!$feof(fd)) begin
                rc = $fgets(line, fd);
                if (rc > 0) begin
                    if (line[8*(rc-1) +: 8] == "@" || (rc >= 2 && line[8*(rc-1) +: 8] == "@")) begin
                        rc = $sscanf(line, "@%h", word_addr);
                        addr = word_addr * 16;
                    end else begin
                        rc = $sscanf(line, "%h", w128);
                        if (rc == 1) begin
                            u_mem.load_word(addr, w128);
                            addr = addr + 16;
                            n = n + 1;
                        end
                    end
                end
            end
            $fclose(fd);
            $display("loaded %0d words from %0s", n, path);
        end
    endtask

    task apb_write;
        input [5:0] a;
        input [31:0] v;
        begin
            @(negedge clk);
            paddr = a; pwdata = v; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            @(negedge clk);
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        end
    endtask

    task apb_read;
        input [5:0] a;
        output [31:0] v;
        begin
            @(negedge clk);
            paddr = a; pwrite = 1'b0; psel = 1'b1; penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            #1 v = prdata;
            @(negedge clk);
            psel = 1'b0; penable = 1'b0;
        end
    endtask

    // Golden regions: regions.txt lines "base bytes", golden.hex holds the data in the same order.
    reg [31:0] reg_base [0:63];
    reg [31:0] reg_bytes [0:63];
    integer n_regions;
    reg [127:0] gold_words [0:(1<<20)-1];
    integer gold_n;

    task load_golden;
        input [1023:0] dir;
        integer gi;
        reg [31:0] gaddr;
        begin
            fd = $fopen({dir, "/regions.txt"}, "r");
            if (fd == 0) begin
                $display("FAIL: cannot open regions.txt");
                `TB_FINISH("tb_npu_net")
            end
            n_regions = 0;
            while (!$feof(fd)) begin
                rc = $fscanf(fd, "%h %d\n", reg_base[n_regions], reg_bytes[n_regions]);
                if (rc == 2) n_regions = n_regions + 1;
            end
            $fclose(fd);
            fd = $fopen({dir, "/golden.hex"}, "r");
            gold_n = 0;
            while (!$feof(fd)) begin
                rc = $fgets(line, fd);
                if (rc > 0 && line[8*(rc-1) +: 8] != "@") begin
                    rc = $sscanf(line, "%h", w128);
                    if (rc == 1) begin
                        gold_words[gold_n] = w128;
                        gold_n = gold_n + 1;
                    end
                end
            end
            $fclose(fd);
            $display("golden: %0d regions, %0d words", n_regions, gold_n);
        end
    endtask

    integer dbg = 0;
    reg [4:0] seq_state_q = 0;
    always @(posedge clk) begin
        if (dbg) begin
            if (u_dut.unit_start) $display("DBG t=%0t unit_start tile0=%0d row_base=%0d plane_words=%0d", $time, u_dut.cfg_tile0, u_dut.cfg_row_base, u_dut.cfg_plane_words);
            if (u_dut.drain_start) $display("DBG t=%0t drain_start oct=%0d", $time, u_dut.drain_oct);
            if (u_dut.u_unit.u_acc.s2_end) $display("DBG t=%0t tile_done wr_bank=%0d full=%b", $time, u_dut.u_unit.u_acc.wr_bank, u_dut.u_unit.u_acc.full);
            if (u_dut.u_unit.u_acc.ep_release_i) $display("DBG t=%0t release rd_bank=%0d", $time, u_dut.u_unit.u_acc.rd_bank);
            if (u_dut.ibuf_fill_rst) $display("DBG t=%0t ibuf_fill_rst", $time);
            if (dbg > 2 && u_dut.u_seq.state != seq_state_q)
                $display("DBG t=%0t seq state %0d -> %0d idx=%0d tile=%0d unit_busy=%0d ep_busy=%0d bank_full=%0d wr_idle=%0d rd_busy=%b ibuf_words=%0d fill_words=%0d wfifo=%0d",
                         $time, seq_state_q, u_dut.u_seq.state, u_dut.u_seq.idx, u_dut.u_seq.tile, u_dut.unit_busy, u_dut.u_unit.ep_busy,
                         u_dut.u_unit.bank_full, u_dut.wr_idle, u_dut.rd_busy, u_dut.ibuf_words, u_dut.u_seq.fill_words, u_dut.u_unit.u_wfifo.state);
            seq_state_q <= u_dut.u_seq.state;
            if (dbg > 3 && (u_dut.cmd_valid[0] && u_dut.cmd_ready[0]))
                $display("DBG t=%0t cmd0 addr=%h len=%0d n=%0d,%0d,%0d dst=%0d", $time, u_dut.cmd_addr[31:0], u_dut.cmd_len[31:0],
                         u_dut.cmd_n0[15:0], u_dut.cmd_n1[15:0], u_dut.cmd_n2[15:0], u_dut.cmd_dst[3:0]);
            if (dbg > 3 && (u_dut.cmd_valid[1] && u_dut.cmd_ready[1]))
                $display("DBG t=%0t cmd1 addr=%h len=%0d", $time, u_dut.cmd_addr[63:32], u_dut.cmd_len[63:32]);
            if (dbg > 3 && arvalid && arready)
                $display("DBG t=%0t AR addr=%h len=%0d id=%0d out0=%0d out1=%0d", $time, araddr, arlen, arid, u_dut.u_rd.outstanding[0], u_dut.u_rd.outstanding[1]);
            if (dbg > 3 && rvalid && rready && rlast)
                $display("DBG t=%0t R last id=%0d r_total=%0d active=%0d,%0d", $time, rid, u_dut.u_rd.r_total[rid[0]], u_dut.u_rd.active[0], u_dut.u_rd.active[1]);
            if (dbg > 3 && u_dut.d_valid[0] && u_dut.d_ready[0] && u_dut.d_dst[3:0] == 0)
                $display("DBG t=%0t desc word", $time);
            if (dbg > 4 && rvalid)
                $display("DBG t=%0t R valid rid=%0d rready=%0d rlast=%0d dv=%b dready=%b ddst=%h beat=%0d r_left=%0d r_busy=%0d", $time, rid, rready, rlast,
                         u_dut.d_valid, u_dut.d_ready, u_dut.d_dst, u_dut.u_rd.beat_cnt[0], u_mem.r_left, u_mem.r_busy);
            if (dbg > 1 && u_dut.u_unit.u_acc.v_i && u_dut.u_unit.u_acc.p_i == 0)
                $display("DBG t=%0t acc p0 first=%0d psum_oc0=%0d psum_oc1=%0d", $time, u_dut.u_unit.u_acc.first_i,
                         $signed(u_dut.u_unit.u_acc.psum_i[23:0]), $signed(u_dut.u_unit.u_acc.psum_i[47:24]));
            if (dbg > 1 && u_dut.u_unit.d_v && u_dut.u_unit.d_p == 0)
                $display("DBG t=%0t x p0 gate=%0d addr=%0d x0=%0d x1=%0d x2=%0d x3=%0d", $time, u_dut.u_unit.d_gate, u_dut.u_unit.u_agen.addr_o,
                         $signed(u_dut.u_unit.x_vec[7:0]), $signed(u_dut.u_unit.x_vec[15:8]), $signed(u_dut.u_unit.x_vec[23:16]), $signed(u_dut.u_unit.x_vec[31:24]));
            if (dbg > 1 && u_dut.u_unit.u_ep.s1_v && u_dut.u_unit.u_ep.s1_px < 2 && u_dut.u_unit.u_ep.adv)
                $display("DBG t=%0t ep s1 plane=%0d px=%0d rd_bank=%0d full=%b wr_bank=%0d acc_lane0=%0d acc_lane1=%0d prm0=%h", $time,
                         u_dut.u_unit.u_ep.s1_plane, u_dut.u_unit.u_ep.s1_px, u_dut.u_unit.u_acc.rd_bank, u_dut.u_unit.u_acc.full,
                         u_dut.u_unit.u_acc.wr_bank, $signed(u_dut.u_unit.u_ep.ep_data_i[31:0]), $signed(u_dut.u_unit.u_ep.ep_data_i[63:32]),
                         u_dut.u_unit.u_ep.s1_prm[0]);
            if (dbg > 1 && u_dut.u_unit.u_acc.s1_v && u_dut.u_unit.u_acc.s1_p == 0 && u_dut.u_unit.u_acc.s1_end)
                $display("DBG t=%0t acc final write p0 bank=%0d sum0=%0d", $time, u_dut.u_unit.u_acc.s1_bank, $signed(u_dut.u_unit.u_acc.sum[31:0]));
            if (dbg > 1 && u_dut.u_unit.u_acc.s1_v && u_dut.u_unit.u_acc.s1_p == 0 && !u_dut.u_unit.u_acc.s1_first)
                $display("DBG t=%0t acc rmw p0 bank=%0d rd=%0d psum=%0d sum=%0d", $time, u_dut.u_unit.u_acc.s1_bank,
                         $signed(u_dut.u_unit.u_acc.rdsel[31:0]), $signed(u_dut.u_unit.u_acc.s1_psum[23:0]), $signed(u_dut.u_unit.u_acc.sum[31:0]));
            if (dbg > 1 && u_dut.u_unit.u_ep.out_valid_o && u_dut.u_unit.u_ep.out_ready_i && u_dut.u_unit.u_ep.out_plane_o == 1 && u_dut.u_unit.u_ep.out_px_o < 2)
                $display("DBG t=%0t ep out plane1 px=%0d tile=%0d data_lo=%h silu=%0d", $time, u_dut.u_unit.u_ep.out_px_o, u_dut.u_unit.u_ep.out_tile_o,
                         u_dut.u_unit.u_ep.out_data_o[31:0], u_dut.cfg_silu);
            if (dbg > 1 && u_dut.m_awvalid && u_dut.m_awready && (u_dut.m_awaddr - 32'h28040000) >= 16384 && (u_dut.m_awaddr - 32'h28040000) < 16384 + 64)
                $display("DBG t=%0t AW addr=%h", $time, u_dut.m_awaddr);
            if (dbg > 1 && u_dut.m_wvalid && u_dut.m_wready && u_dut.u_wr.m_awaddr >= 32'h28044000 && u_dut.u_wr.m_awaddr < 32'h28044040)
                $display("DBG t=%0t W data_lo=%h last=%0d", $time, u_dut.m_wdata[31:0], u_dut.m_wlast);
            if (dbg > 1 && u_dut.ibuf_we && u_dut.ibuf_waddr < 3)
                $display("DBG t=%0t ibuf write addr=%0d data_lo=%h", $time, u_dut.ibuf_waddr, u_dut.ibuf_wdata[31:0]);
            if (u_dut.u_seq.state == 5'd11 && u_dut.cmd_valid[1]) $display("DBG t=%0t weights cmd len=%0d", $time, u_dut.cmd_len[63:32]);
        end
    end

    integer wd_cycles = 3000000;
    initial begin
        if ($value$plusargs("WATCHDOG=%d", wd_cycles)) ;
    end
    `TB_WATCHDOG("tb_npu_net", wd_cycles, clk)

    reg [31:0] v, status, cycles;
    reg [1023:0] dump_path;
    integer dfd;
    integer gi, gw, byte_errors, region_errors;
    reg [7:0] got_b, exp_b;
    integer t0;

    initial begin
        if (!$value$plusargs("VEC=%s", vec)) vec = "sim/stalyanpu/stim/demo_net";
        if ($value$plusargs("SEED=%d", seed)) ;
        if ($value$plusargs("BP=%d", bp)) ;
        if ($value$plusargs("DEBUG=%d", dbg)) ;
        i = $urandom(seed);
        load_hex({vec, "/mem.hex"});
        load_golden(vec);

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);

        apb_read(6'h00, v);
        `TB_CHECK(v == 32'h534E5055, "ID register")
        apb_read(6'h08, v);
        $display("GEOMETRY %h", v);
        // The descriptor list address and count come from the vector meta
        // (desc_base = blob base + 4096, count = descriptors).
        apb_write(6'h14, desc_base_plus);
        apb_write(6'h18, desc_count_plus);
        apb_write(6'h20, 32'h00000005);   // done and error interrupts only
        t0 = $time;
        apb_write(6'h0C, 32'h1);

        // Wait for the interrupt.
        while (!irq) @(posedge clk);
        apb_read(6'h1C, v);
        $display("IRQ_STATUS %h after %0d ns", v, $time-t0);
        `TB_CHECK(v[0] == 1'b1, "done interrupt")
        `TB_CHECK(v[2] == 1'b0, "error interrupt")
        apb_read(6'h10, status);
        $display("STATUS %h", status);
        apb_read(6'h24, cycles);
        $display("CYCLE_CNT %0d", cycles);
        apb_write(6'h1C, 32'hF);
        `TB_CHECK(mem_errors == 0, "memory model saw accesses outside the windows")

        // Optional dump of the produced regions (+DUMP_REGION=<file>): one 32 byte line per word.
        if ($value$plusargs("DUMP_REGION=%s", dump_path)) begin
            dfd = $fopen(dump_path, "w");
            for (gi = 0; gi < n_regions; gi = gi + 1)
                for (j = 0; j < reg_bytes[gi]; j = j + 1) begin
                    $fwrite(dfd, "%02x", u_mem.peek_byte(reg_base[gi] + j));
                    if ((j & 31) == 31) $fwrite(dfd, "\n");
                end
            $fclose(dfd);
        end
        // Compare regions.
        gw = 0;
        for (gi = 0; gi < n_regions; gi = gi + 1) begin
            byte_errors = 0;
            for (j = 0; j < reg_bytes[gi]; j = j + 1) begin
                got_b = u_mem.peek_byte(reg_base[gi] + j);
                exp_b = gold_words[gw + (j >> 4)][(j & 15) * 8 +: 8];
                if (got_b !== exp_b) begin
                    if (byte_errors < 4)
                        $display("  region %0d byte %0d @%h got %h exp %h", gi, j, reg_base[gi] + j, got_b, exp_b);
                    if ((j & 31) == 0 || byte_errors == 0)
                        $display("  bad word %0d", j >> 5);
                    byte_errors = byte_errors + 1;
                end
            end
            gw = gw + ((reg_bytes[gi] + 15) >> 4);
            `TB_CHECK(byte_errors == 0, "region mismatch")
            $display("region %0d base %h bytes %0d: %0d byte errors", gi, reg_base[gi], reg_bytes[gi], byte_errors);
        end
        `TB_FINISH("tb_npu_net")
    end

    // Descriptor base and count from plusargs (written by the generator into the run command).
    reg [31:0] desc_base_plus = 32'h20001000;
    reg [31:0] desc_count_plus = 32'd1;
    initial begin
        if ($value$plusargs("DESC_BASE=%h", desc_base_plus)) ;
        if ($value$plusargs("DESC_COUNT=%d", desc_count_plus)) ;
    end

endmodule
