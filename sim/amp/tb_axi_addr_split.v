// =============================================================================
// tb_axi_addr_split.v
//
// Self-checking testbench for rtl/axi_addr_split.v.
//
// Two memory slave models sit behind the router, each with random ready and
// response back-pressure and its own background pattern, so a transaction that
// goes to the wrong slave shows up as data in the wrong memory. The master
// drives AW and W at the same time, which exercises the path where write data
// has to wait for its address to be routed. Reads and writes to different
// slaves run concurrently. Every run uses a fixed seed, so a failure repeats.
// =============================================================================
`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// AXI4 memory slave with random back-pressure. INCR bursts, 32 bit data,
// 256-word memory indexed by address bits [9:2]. Returns SLVERR when a
// transaction starts at an address ending in 0xC00, so error propagation can
// be tested without colliding with the window-edge addresses.
// ---------------------------------------------------------------------------
module axi_mem_slave #(
    parameter [31:0] BACKGROUND = 32'h0,
    parameter        SEED       = 1,
    // 1: accept write data before the write address, as AXI allows. Beats are
    // buffered and committed once the address arrives. A router that forwards
    // data too early deadlocks against a slave like this.
    parameter        EAGER_W    = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        awvalid, output reg  awready,
    input  wire [31:0] awaddr,  input  wire [7:0] awlen,
    input  wire        wvalid,  output reg  wready,
    input  wire [31:0] wdata,   input  wire [3:0] wstrb, input wire wlast,
    output reg         bvalid,  input  wire bready, output reg [1:0] bresp,
    input  wire        arvalid, output reg  arready,
    input  wire [31:0] araddr,  input  wire [7:0] arlen,
    output reg         rvalid,  input  wire rready,
    output reg  [31:0] rdata,   output reg  [1:0] rresp, output reg rlast
);
    reg [31:0] mem [0:255];
    integer k, seed;
    initial begin
        seed = SEED;
        for (k = 0; k < 256; k = k + 1) mem[k] = BACKGROUND ^ k;
    end

    function [1:0] resp_for; input [31:0] a;
        begin resp_for = (a[11:0] == 12'hC00) ? 2'b10 : 2'b00; end
    endfunction

    // writes: incoming beats go through a small FIFO so the same code serves
    // both the polite (data after address) and the eager ordering.
    reg        w_busy;          // address accepted, beats still to commit
    reg [31:0] w_addr;
    reg [1:0]  w_resp;
    reg        w_wait_b;
    reg [36:0] wf [0:31];       // {last, strb, data}
    reg [5:0]  wf_wr, wf_rd;
    reg        w_got_last;      // this burst's last beat has been taken
    wire [5:0] wf_cnt = wf_wr - wf_rd;
    wire       may_take_w = EAGER_W ? (!w_got_last && !w_wait_b && wf_cnt < 30)
                                    : (w_busy && !w_got_last);
    always @(posedge clk) begin
        if (rst) begin
            awready <= 0; wready <= 0; bvalid <= 0; w_busy <= 0; w_wait_b <= 0;
            wf_wr <= 0; wf_rd <= 0; w_got_last <= 0;
        end else begin
            awready <= !w_busy && !w_wait_b && ($random(seed) % 3 != 0);
            if (awvalid && awready) begin
                w_busy <= 1; w_addr <= awaddr; w_resp <= resp_for(awaddr); awready <= 0;
            end

            wready <= may_take_w && ($random(seed) % 3 != 0);
            if (wvalid && wready) begin
                wf[wf_wr[4:0]] <= {wlast, wstrb, wdata};
                wf_wr <= wf_wr + 1;
                if (wlast) begin w_got_last <= 1; wready <= 0; end
            end

            // commit one buffered beat per cycle once the address is known
            if (w_busy && wf_cnt != 0) begin
                if (wf[wf_rd[4:0]][32]) mem[w_addr[9:2]][7:0]   <= wf[wf_rd[4:0]][7:0];
                if (wf[wf_rd[4:0]][33]) mem[w_addr[9:2]][15:8]  <= wf[wf_rd[4:0]][15:8];
                if (wf[wf_rd[4:0]][34]) mem[w_addr[9:2]][23:16] <= wf[wf_rd[4:0]][23:16];
                if (wf[wf_rd[4:0]][35]) mem[w_addr[9:2]][31:24] <= wf[wf_rd[4:0]][31:24];
                w_addr <= w_addr + 4;
                wf_rd  <= wf_rd + 1;
                if (wf[wf_rd[4:0]][36]) begin w_busy <= 0; w_wait_b <= 1; end
            end

            if (w_wait_b && !bvalid && ($random(seed) % 2 == 0)) begin
                bvalid <= 1; bresp <= w_resp;
            end
            if (bvalid && bready) begin bvalid <= 0; w_wait_b <= 0; w_got_last <= 0; end
        end
    end

    // reads
    reg        r_busy;
    reg [31:0] r_addr;
    reg [7:0]  r_left;
    always @(posedge clk) begin
        if (rst) begin
            arready <= 0; rvalid <= 0; r_busy <= 0;
        end else begin
            arready <= !r_busy && ($random(seed) % 3 != 0);
            if (arvalid && arready) begin
                r_busy <= 1; r_addr <= araddr; r_left <= arlen; arready <= 0;
            end
            if (r_busy && (!rvalid || rready)) begin
                if (rvalid && rready && rlast) begin
                    rvalid <= 0; r_busy <= 0;
                end else if (rvalid && rready) begin
                    rvalid <= 0;                       // one idle cycle between beats
                end else if ($random(seed) % 2 == 0) begin
                    rvalid <= 1;
                    rdata  <= mem[r_addr[9:2]];
                    rresp  <= resp_for(r_addr);
                    rlast  <= (r_left == 0);
                    r_addr <= r_addr + 4;
                    r_left <= r_left - 1;
                end
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
module tb_axi_addr_split;

    reg clk = 0, rst = 1;
    always #2.5 clk = ~clk;

    // master side
    reg         m_awvalid = 0; wire m_awready; reg [31:0] m_awaddr = 0; reg [7:0] m_awlen = 0;
    reg         m_wvalid = 0;  wire m_wready;  reg [31:0] m_wdata = 0;  reg [3:0] m_wstrb = 4'hF;
    reg         m_wlast = 0;
    wire        m_bvalid;      reg  m_bready = 0; wire [1:0] m_bresp;
    reg         m_arvalid = 0; wire m_arready; reg [31:0] m_araddr = 0; reg [7:0] m_arlen = 0;
    wire        m_rvalid;      reg  m_rready = 0; wire [31:0] m_rdata; wire [1:0] m_rresp; wire m_rlast;

    // shared slave payload
    wire [31:0] s_awaddr, s_araddr, s_wdata; wire [7:0] s_awlen, s_arlen;
    wire [3:0]  s_wstrb; wire s_wlast;

    wire s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_bvalid, s0_bready;
    wire s0_arvalid, s0_arready, s0_rvalid, s0_rready, s0_rlast;
    wire [1:0] s0_bresp, s0_rresp; wire [31:0] s0_rdata;
    wire s1_awvalid, s1_awready, s1_wvalid, s1_wready, s1_bvalid, s1_bready;
    wire s1_arvalid, s1_arready, s1_rvalid, s1_rready, s1_rlast;
    wire [1:0] s1_bresp, s1_rresp; wire [31:0] s1_rdata;

    axi_addr_split dut (
        .clk(clk), .rst(rst),
        .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(3'd2), .m_awburst(2'b01), .m_awlock(1'b0), .m_awcache(4'd0), .m_awprot(3'd0),
        .m_awqos(4'd0), .m_awregion(4'd0),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp),
        .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(3'd2), .m_arburst(2'b01), .m_arlock(1'b0), .m_arcache(4'd0), .m_arprot(3'd0),
        .m_arqos(4'd0), .m_arregion(4'd0),
        .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(), .s_awburst(), .s_awlock(), .s_awcache(),
        .s_awprot(), .s_awqos(), .s_awregion(),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arsize(), .s_arburst(), .s_arlock(), .s_arcache(),
        .s_arprot(), .s_arqos(), .s_arregion(),
        .s0_awvalid(s0_awvalid), .s0_awready(s0_awready), .s0_wvalid(s0_wvalid), .s0_wready(s0_wready),
        .s0_bvalid(s0_bvalid), .s0_bready(s0_bready), .s0_bresp(s0_bresp),
        .s0_arvalid(s0_arvalid), .s0_arready(s0_arready), .s0_rvalid(s0_rvalid), .s0_rready(s0_rready),
        .s0_rdata(s0_rdata), .s0_rresp(s0_rresp), .s0_rlast(s0_rlast),
        .s1_awvalid(s1_awvalid), .s1_awready(s1_awready), .s1_wvalid(s1_wvalid), .s1_wready(s1_wready),
        .s1_bvalid(s1_bvalid), .s1_bready(s1_bready), .s1_bresp(s1_bresp),
        .s1_arvalid(s1_arvalid), .s1_arready(s1_arready), .s1_rvalid(s1_rvalid), .s1_rready(s1_rready),
        .s1_rdata(s1_rdata), .s1_rresp(s1_rresp), .s1_rlast(s1_rlast)
    );

    axi_mem_slave #(.BACKGROUND(32'hA0A0_0000), .SEED(11), .EAGER_W(1)) slv0 (
        .clk(clk), .rst(rst),
        .awvalid(s0_awvalid), .awready(s0_awready), .awaddr(s_awaddr), .awlen(s_awlen),
        .wvalid(s0_wvalid), .wready(s0_wready), .wdata(s_wdata), .wstrb(s_wstrb), .wlast(s_wlast),
        .bvalid(s0_bvalid), .bready(s0_bready), .bresp(s0_bresp),
        .arvalid(s0_arvalid), .arready(s0_arready), .araddr(s_araddr), .arlen(s_arlen),
        .rvalid(s0_rvalid), .rready(s0_rready), .rdata(s0_rdata), .rresp(s0_rresp), .rlast(s0_rlast));

    axi_mem_slave #(.BACKGROUND(32'hB1B1_0000), .SEED(29)) slv1 (
        .clk(clk), .rst(rst),
        .awvalid(s1_awvalid), .awready(s1_awready), .awaddr(s_awaddr), .awlen(s_awlen),
        .wvalid(s1_wvalid), .wready(s1_wready), .wdata(s_wdata), .wstrb(s_wstrb), .wlast(s_wlast),
        .bvalid(s1_bvalid), .bready(s1_bready), .bresp(s1_bresp),
        .arvalid(s1_arvalid), .arready(s1_arready), .araddr(s_araddr), .arlen(s_arlen),
        .rvalid(s1_rvalid), .rready(s1_rready), .rdata(s1_rdata), .rresp(s1_rresp), .rlast(s1_rlast));

    // ------------------------------------------------ protocol assertions
    // A slave may only see valid while the router has picked it; both may
    // never be driven at once.
    always @(posedge clk) if (!rst) begin
        if (s0_awvalid && s1_awvalid) begin $display("FAIL  AW driven to both slaves"); fail = fail + 1; end
        if (s0_wvalid  && s1_wvalid)  begin $display("FAIL  W driven to both slaves");  fail = fail + 1; end
        if (s0_arvalid && s1_arvalid) begin $display("FAIL  AR driven to both slaves"); fail = fail + 1; end
    end

    // AXI: once valid is high it must stay high, with a stable address,
    // until the handshake.
    reg        aw0_hold, aw1_hold, ar0_hold, ar1_hold;
    reg [31:0] aw_addr_q, ar_addr_q;
    always @(posedge clk) if (rst) begin
        aw0_hold <= 0; aw1_hold <= 0; ar0_hold <= 0; ar1_hold <= 0;
    end else begin
        if (aw0_hold && !s0_awvalid) begin $display("FAIL  s0 AWVALID dropped before AWREADY"); fail = fail + 1; end
        if (aw1_hold && !s1_awvalid) begin $display("FAIL  s1 AWVALID dropped before AWREADY"); fail = fail + 1; end
        if (ar0_hold && !s0_arvalid) begin $display("FAIL  s0 ARVALID dropped before ARREADY"); fail = fail + 1; end
        if (ar1_hold && !s1_arvalid) begin $display("FAIL  s1 ARVALID dropped before ARREADY"); fail = fail + 1; end
        if ((aw0_hold || aw1_hold) && s_awaddr !== aw_addr_q) begin $display("FAIL  AWADDR changed while valid"); fail = fail + 1; end
        if ((ar0_hold || ar1_hold) && s_araddr !== ar_addr_q) begin $display("FAIL  ARADDR changed while valid"); fail = fail + 1; end
        aw0_hold <= s0_awvalid && !s0_awready;  aw1_hold <= s1_awvalid && !s1_awready;
        ar0_hold <= s0_arvalid && !s0_arready;  ar1_hold <= s1_arvalid && !s1_arready;
        aw_addr_q <= s_awaddr; ar_addr_q <= s_araddr;
    end

    integer pass = 0, fail = 0;
    integer seed = 7;

    task check;
        input [255:0] what; input [31:0] got; input [31:0] want;
        begin
            if (got === want) pass = pass + 1;
            else begin fail = fail + 1; $display("FAIL  %0s: got 0x%08h, want 0x%08h", what, got, want); end
        end
    endtask

    // ------------------------------------------------------- master BFM
    reg [31:0] wbuf [0:15];
    reg [31:0] rbuf [0:15];
    reg [1:0]  last_bresp, last_rresp;

    // AW and W are driven concurrently: W must wait inside the router until
    // its address has been routed.
    task axi_write;
        input [31:0] addr; input [7:0] len;
        integer b;
        begin
            fork
                begin
                    @(posedge clk); m_awvalid <= 1; m_awaddr <= addr; m_awlen <= len;
                    @(posedge clk); while (!m_awready) @(posedge clk);
                    // AXI lets the master change the payload once valid drops;
                    // a router that does not hold its copy passes this garbage on.
                    m_awvalid <= 0; m_awaddr <= $random(seed); m_awlen <= $random(seed);
                end
                begin
                    for (b = 0; b <= len; b = b + 1) begin
                        @(posedge clk); m_wvalid <= 1; m_wdata <= wbuf[b]; m_wlast <= (b == len);
                        @(posedge clk); while (!m_wready) @(posedge clk);
                        m_wvalid <= 0; m_wlast <= $random(seed); m_wdata <= $random(seed);
                    end
                end
            join
            // random response back-pressure
            m_bready <= 0;
            while (!(m_bvalid && m_bready)) begin
                @(posedge clk); m_bready <= ($random(seed) % 2 == 0);
            end
            last_bresp = m_bresp;
            @(negedge clk); m_bready <= 0;
        end
    endtask

    task axi_read;
        input [31:0] addr; input [7:0] len;
        integer b;
        begin
            @(posedge clk); m_arvalid <= 1; m_araddr <= addr; m_arlen <= len;
            @(posedge clk); while (!m_arready) @(posedge clk);
            m_arvalid <= 0; m_araddr <= $random(seed); m_arlen <= $random(seed);
            b = 0;
            last_rresp = 2'b00;
            while (b <= len) begin
                m_rready <= ($random(seed) % 3 != 0);
                @(posedge clk);
                if (m_rvalid && m_rready) begin
                    rbuf[b] = m_rdata;
                    if (m_rresp != 2'b00) last_rresp = m_rresp;
                    if (m_rlast !== (b == len)) begin
                        $display("FAIL  RLAST wrong on beat %0d of %0d", b, len); fail = fail + 1;
                    end
                    b = b + 1;
                end
            end
            m_rready <= 0;
        end
    endtask

    // Write a burst, then confirm it landed in the intended slave's memory and
    // left the other slave's memory untouched.
    task write_and_check_routing;
        input [31:0]  addr; input [7:0] len; input to_s1;
        input [255:0] name;
        integer b, idx;
        reg [31:0] other_bg;
        begin
            for (b = 0; b <= len; b = b + 1) wbuf[b] = {addr[31:16], 8'h00, b[7:0]} ^ 32'h0000_5A00;
            axi_write(addr, len);
            check({name, " bresp"}, last_bresp, 2'b00);
            for (b = 0; b <= len; b = b + 1) begin
                idx = addr[9:2] + b;
                if (to_s1) begin
                    check({name, " landed in slave 1"}, slv1.mem[idx], wbuf[b]);
                    check({name, " slave 0 untouched"}, slv0.mem[idx], 32'hA0A0_0000 ^ idx);
                end else begin
                    check({name, " landed in slave 0"}, slv0.mem[idx], wbuf[b]);
                    check({name, " slave 1 untouched"}, slv1.mem[idx], 32'hB1B1_0000 ^ idx);
                end
            end
            // read it back through the router
            axi_read(addr, len);
            for (b = 0; b <= len; b = b + 1)
                check({name, " read back"}, rbuf[b], wbuf[b]);
        end
    endtask

    // restore both memories between routing tests
    task reset_mems;
        integer k;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                slv0.mem[k] = 32'hA0A0_0000 ^ k;
                slv1.mem[k] = 32'hB1B1_0000 ^ k;
            end
        end
    endtask

    integer b;

    initial begin
        $dumpfile("tb_axi_addr_split.vcd");
        $dumpvars(0, tb_axi_addr_split);
        repeat (4) @(posedge clk);
        rst <= 0;
        repeat (4) @(posedge clk);

        // ----------------------------------------------- routing by address
        reset_mems; write_and_check_routing(32'hE801_0000, 0, 0, "slb UART0 single");
        reset_mems; write_and_check_routing(32'hEA00_0100, 3, 1, "TSE window burst4");
        reset_mems; write_and_check_routing(32'hEB00_0040, 7, 1, "SDHC window burst8");
        reset_mems; write_and_check_routing(32'hE810_4000, 1, 0, "NPU APB burst2");

        // window edges: 0xEA00_0000 .. 0xEBFF_FFFF goes to slave 1
        reset_mems; write_and_check_routing(32'hE9FF_FFFC, 0, 0, "just below window");
        reset_mems; write_and_check_routing(32'hEA00_0000, 0, 1, "window start");
        reset_mems; write_and_check_routing(32'hEBFF_FF00, 0, 1, "window end");
        reset_mems; write_and_check_routing(32'hEC00_0000, 0, 0, "just above window");
        reset_mems; write_and_check_routing(32'hF000_0000, 0, 0, "far above window");

        // longest burst the 16-entry buffer holds
        reset_mems; write_and_check_routing(32'hEA00_0200, 15, 1, "TSE burst16");

        // --------------------------------------------- byte strobes pass through
        reset_mems;
        wbuf[0] = 32'hDDCC_BBAA; m_wstrb <= 4'b0101;
        axi_write(32'hEB00_0010, 0);
        m_wstrb <= 4'hF;
        // background 0xB1B1_0004; lanes 0 and 2 take 0xAA and 0xCC, lanes 1 and 3 keep 0x00 and 0xB1
        check("strobes: only lanes 0 and 2 written", slv1.mem[4], 32'hB1CC_00AA);

        // ------------------------------- concurrent read and write, different slaves
        reset_mems;
        for (b = 0; b < 4; b = b + 1) wbuf[b] = 32'hC0DE_0000 + b;
        fork
            axi_write(32'hEA00_0080, 3);   // slave 1
            axi_read (32'hE800_0080, 3);   // slave 0, background data
        join
        for (b = 0; b < 4; b = b + 1) begin
            check("concurrent: write reached slave 1", slv1.mem[32 + b], 32'hC0DE_0000 + b);
            check("concurrent: read came from slave 0", rbuf[b], 32'hA0A0_0000 ^ (32 + b));
        end

        // -------------------------------------------------- error propagation
        wbuf[0] = 32'h1234_5678;
        axi_write(32'hEA00_0C00, 0);       // ends in 0xC00 -> SLVERR in the model
        check("write error reaches the master", last_bresp, 2'b10);
        axi_read(32'hE800_0C00, 2);
        check("read error reaches the master", last_rresp, 2'b10);

        // ------------------------------------ back-to-back traffic, both slaves
        reset_mems;
        for (b = 0; b < 32; b = b + 1) begin
            wbuf[0] = 32'hF00D_0000 + b;
            axi_write(((b % 2) ? 32'hEA00_0000 : 32'hE800_0000) + (b * 4), 0);
        end
        for (b = 0; b < 32; b = b + 1)
            if (b % 2) check("interleaved -> slave 1", slv1.mem[b], 32'hF00D_0000 + b);
            else       check("interleaved -> slave 0", slv0.mem[b], 32'hF00D_0000 + b);

        repeat (10) @(posedge clk);
        check("router idle: AWREADY", m_awready, 1);
        check("router idle: ARREADY", m_arready, 1);

        $display("");
        $display("tb_axi_addr_split: %0d passed, %0d failed", pass, fail);
        if (fail != 0) $fatal(1, "tb_axi_addr_split FAILED");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "tb_axi_addr_split: timeout (a handshake never completed)");
    end

endmodule
