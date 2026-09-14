// Unit test of the write DMA burst coalescing. Feeds the epilogue word
// order (the planes of one pixel follow each other) against an always
// ready AXI slave and checks the burst count and the data order.
`timescale 1ns / 1ps

module tb_wr_dma;
    reg clk = 0, rst = 1;
    always #2 clk = ~clk;

    reg         w_valid = 0;
    reg  [31:0] w_addr = 0;
    reg  [255:0] w_data = 0;
    wire        w_ready, idle;
    wire        awvalid, wvalid, wlast;
    wire [31:0] awaddr;
    wire [7:0]  awlen;
    wire [127:0] wdata;
    reg         awready = 1, wready = 1, bvalid = 0;
    wire        bready;
    wire [7:0]  pending;
    wire [31:0] aw_wait, w_wait, bursts, beats;

    snpu_wr_dma #(.NSLOT(8), .SLOT_WORDS(8)) u_wr (
        .clk(clk), .rst(rst),
        .w_valid_i(w_valid), .w_addr_i(w_addr), .w_data_i(w_data), .w_ready_o(w_ready), .idle_o(idle),
        .dbg_pending_o(pending), .dbg_aw_wait_o(aw_wait), .dbg_w_wait_o(w_wait), .dbg_bursts_o(bursts), .dbg_beats_o(beats),
        .m_awvalid(awvalid), .m_awready(awready), .m_awaddr(awaddr), .m_awlen(awlen), .m_awsize(), .m_awburst(), .m_awid(),
        .m_wvalid(wvalid), .m_wready(wready), .m_wdata(wdata), .m_wstrb(), .m_wlast(wlast),
        .m_bvalid(bvalid), .m_bready(bready), .m_bresp(2'b00), .err_o()
    );

    // Response one cycle after the last beat.
    always @(posedge clk) bvalid <= wvalid && wready && wlast;

    // Scoreboard: every beat must land at the expected address.
    reg [31:0] cur_aw;
    reg [7:0]  cur_beat;
    integer errors = 0, nbursts = 0;
    always @(posedge clk) begin
        if (awvalid && awready) begin
            cur_aw <= awaddr; nbursts <= nbursts + 1;
            if (u_wr.s_n * 2 != awlen + 1) begin
                $display("FAIL: awlen %0d for %0d words", awlen, u_wr.s_n); errors = errors + 1;
            end
        end
        // W may run ahead of the AW handshake, so the expected address comes
        // from the address register of the burst being sent.
        if (wvalid && wready) begin
            if (wdata[31:0] != u_wr.m_awaddr + cur_beat * 16) begin
                $display("FAIL: beat tag %08x expected %08x", wdata[31:0], u_wr.m_awaddr + cur_beat * 16); errors = errors + 1;
            end
            cur_beat <= wlast ? 0 : cur_beat + 1;
        end
    end

    // Trace of the first accepts and burst closes.
    integer ev = 0;
    always @(posedge clk) begin
        if (!rst && ev < 0 && u_wr.q_push) begin
            ev = ev + 1;
            $display("t=%0t accept=%b addr=%08x hit=%b hit_s=%0d acc_s=%0d acc_len=%0d | push=%b full=%b idle=%b evict=%b q_slot=%0d | st=%0d%0d%0d%0d len=%0d,%0d,%0d,%0d has_free=%b has_open=%b s_busy=%b q_cnt=%0d",
                     $time, u_wr.accept, u_wr.cur_addr, u_wr.hit, u_wr.hit_s, u_wr.acc_s, u_wr.acc_len,
                     u_wr.q_push, u_wr.full_close, u_wr.idle_close, u_wr.evict_close, u_wr.q_slot,
                     u_wr.sstate[0], u_wr.sstate[1], u_wr.sstate[2], u_wr.sstate[3],
                     u_wr.slen[0], u_wr.slen[1], u_wr.slen[2], u_wr.slen[3], u_wr.has_free, u_wr.has_open, u_wr.s_busy, u_wr.q_cnt);
        end
    end
    reg done;
    task send(input [31:0] addr);
        begin
            w_valid = 1; w_addr = addr; w_data = {8{addr}};
            w_data[255:128] = {4{addr + 32'd16}};
            done = 0;
            while (!done) begin
                @(negedge clk);
                if (w_ready) begin
                    @(posedge clk); #1 done = 1;
                end
            end
            w_valid = 0;
        end
    endtask

    integer px, pl, i;
    initial begin
        repeat (3) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
        // Two planes, 40 pixels per row, 4 rows, plane stride 64 KB.
        for (px = 0; px < 160; px = px + 1)
            for (pl = 0; pl < 2; pl = pl + 1)
                send(32'h2800_0000 + pl * 32'h1_0000 + (px / 40) * 32'h2000 + (px % 40) * 32);
        i = 0; while (!idle && i < 5000) begin @(posedge clk); i = i + 1; end
        $display("two planes: words 320, bursts %0d (expect 40), beats %0d, errors %0d", bursts, beats, errors);
        if (bursts != 40 || beats != 640 || errors != 0) errors = errors + 1;
        // Slow slave: AW accepted every 40 cycles, one plane, sparse input.
        slow = 1;
        // Bursts must still fill up to 8 words while the sender is busy.
        for (px = 0; px < 64; px = px + 1) begin
            send(32'h3000_0000 + px * 32);
            repeat (3) @(posedge clk);
        end
        i = 0; while (!idle && i < 20000) begin @(posedge clk); i = i + 1; end
        $display("sparse input: words 64, bursts total %0d (expect 48), beats %0d, errors %0d", bursts, beats, errors);
        if (bursts != 48 || errors != 0) errors = errors + 1;
        if (errors == 0) $display("tb_wr_dma: PASS");
        else $display("tb_wr_dma: FAIL");
        $finish;
    end

    // Slow AW acceptance for the second phase.
    integer aw_cnt = 0;
    reg slow = 0;
    always @(posedge clk) begin
        if (slow) begin
            aw_cnt <= aw_cnt + 1;
            awready <= (aw_cnt % 40 == 39);
        end
    end
endmodule
