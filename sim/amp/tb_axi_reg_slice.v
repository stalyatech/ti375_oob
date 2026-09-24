// =============================================================================
// tb_axi_reg_slice.v
//
// Self-checking testbench for the skid buffer of rtl/axi_reg_slice.v, which
// every channel of the slice is built from. A counting stream goes in with
// random valid and comes out against random ready; every word must arrive
// once and in order, the skid entry may only fill behind a full output, and
// with both sides always willing the stream must pass at one word per cycle. A last pass drives the whole slice once per channel.
// =============================================================================
`timescale 1ns / 1ps

module tb_axi_reg_slice;

    reg clk = 0, rst = 1;
    always #2.5 clk = ~clk;

    localparam N = 20000;

    reg         s_valid = 0, m_ready = 0;
    reg  [15:0] s_data = 0;
    wire        s_ready, m_valid;
    wire [15:0] m_data;

    axi_skid #(.W(16)) dut (
        .clk(clk), .rst(rst),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data)
    );

    integer errors = 0, sent = 0, got = 0, cycles = 0, mode = 0;
    reg [15:0] expect_d = 0;

    // Random stimulus; mode 1 keeps both sides always willing.
    always @(posedge clk) begin
        if (!rst) begin
            cycles <= cycles + 1;
            if (s_valid && s_ready) begin
                sent   <= sent + 1;
                s_data <= s_data + 16'd1;
            end
            if (!(s_valid && !s_ready))
                s_valid <= (sent + (s_valid && s_ready) < N) && (mode == 1 || ($random & 3) != 0);
            m_ready <= (mode == 1) || (($random & 3) != 0);
            if (m_valid && m_ready) begin
                if (m_data !== expect_d) begin
                    errors = errors + 1;
                    if (errors < 10) $display("FAIL: got %h expected %h", m_data, expect_d);
                end
                expect_d <= expect_d + 16'd1;
                got <= got + 1;
            end
        end
    end

    // The skid entry may only hold a word while the output holds one.
    always @(posedge clk)
        if (!rst && dut.skid_v && !dut.out_v) begin
            errors = errors + 1;
            $display("FAIL: skid entry full with the output empty");
        end

    // ---- whole slice, one beat per channel
    reg  [31:0] ar_a = 32'h1000_0040, aw_a = 32'h2000_0080;
    reg  [127:0] wd = {4{32'hA5A5_5A5A}}, rd = {4{32'h0F0F_F0F0}};
    wire [31:0] m_araddr, m_awaddr;
    wire [127:0] s_rdata, m_wdata;
    wire [15:0] m_wstrb;
    wire [7:0] m_arlen, m_awlen;
    wire [2:0] m_arsize, m_awsize;
    wire [1:0] m_arburst, m_awburst, s_rresp, s_bresp;
    wire m_arvalid, m_awvalid, m_wvalid, m_wlast, s_rvalid, s_rlast, s_bvalid;
    wire s_arready, s_awready, s_wready, m_rready, m_bready;
    reg  go = 0;

    axi_reg_slice #(.DW(128), .AW(32)) slice (
        .clk(clk), .rst(rst),
        .s_arvalid(go), .s_arready(s_arready), .s_araddr(ar_a), .s_arlen(8'd7), .s_arsize(3'd4), .s_arburst(2'd1),
        .s_rvalid(s_rvalid), .s_rready(1'b1), .s_rdata(s_rdata), .s_rlast(s_rlast), .s_rresp(s_rresp),
        .s_awvalid(go), .s_awready(s_awready), .s_awaddr(aw_a), .s_awlen(8'd3), .s_awsize(3'd4), .s_awburst(2'd1),
        .s_wvalid(go), .s_wready(s_wready), .s_wdata(wd), .s_wstrb(16'hFFFF), .s_wlast(1'b1),
        .s_bvalid(s_bvalid), .s_bready(1'b1), .s_bresp(s_bresp),
        .m_arvalid(m_arvalid), .m_arready(1'b1), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize), .m_arburst(m_arburst),
        .m_rvalid(go), .m_rready(m_rready), .m_rdata(rd), .m_rlast(1'b1), .m_rresp(2'd0),
        .m_awvalid(m_awvalid), .m_awready(1'b1), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_wvalid(m_wvalid), .m_wready(1'b1), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(go), .m_bready(m_bready), .m_bresp(2'd2)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;

        // Random handshakes on both sides.
        wait (got == N);
        repeat (4) @(posedge clk);
        if (sent != N) begin errors = errors + 1; $display("FAIL: sent %0d of %0d", sent, N); end

        // Both sides always willing: one word per cycle after the first.
        @(posedge clk);
        mode = 1; sent = 0; got = 0; cycles = 0;
        wait (got == N);
        if (cycles > N + 4) begin
            errors = errors + 1;
            $display("FAIL: %0d words took %0d cycles", N, cycles);
        end

        // Whole slice: each channel carries its beat through.
        @(posedge clk); go <= 1;
        @(posedge clk); go <= 0;
        repeat (3) @(posedge clk);
        if (m_araddr !== ar_a || m_arlen !== 8'd7 || m_arsize !== 3'd4 || m_arburst !== 2'd1) begin
            errors = errors + 1; $display("FAIL: AR payload");
        end
        if (m_awaddr !== aw_a || m_awlen !== 8'd3 || m_wdata !== wd || m_wstrb !== 16'hFFFF || m_wlast !== 1'b1) begin
            errors = errors + 1; $display("FAIL: AW/W payload");
        end
        if (s_rdata !== rd || s_rlast !== 1'b1 || s_bresp !== 2'd2) begin
            errors = errors + 1; $display("FAIL: R/B payload");
        end

        if (errors == 0) $display("tb_axi_reg_slice: %0d words each way, passed", 2 * N);
        else $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
