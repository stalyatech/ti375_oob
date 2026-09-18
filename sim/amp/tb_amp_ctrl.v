// =============================================================================
// tb_amp_ctrl.v
//
// Self-checking testbench for rtl/amp_ctrl.v. Drives both APB ports with
// independent bus functional models, including accesses that land in the
// same clock cycle, and checks every register, permission rule, doorbell,
// interrupt and error response. Prints PASS/FAIL per check and a summary;
// exits non-zero via $fatal when anything fails.
// =============================================================================
`timescale 1ns / 1ps

module tb_amp_ctrl;

    localparam [11:0] A_ID = 12'h000, A_CTRL = 12'h004, A_BOOT = 12'h008,
                      A_STATUS = 12'h00C, A_SEND = 12'h010, A_PEND = 12'h014,
                      A_MASK = 12'h018, A_SYSRST = 12'h01C, A_SCR0 = 12'h020;
    localparam [31:0] RST_KEY = 32'h5253_5421;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #2.5 clk = ~clk;       // 200 MHz, the peripheral clock

    reg  [11:0] h_paddr = 0, f_paddr = 0;
    reg         h_psel = 0, h_penable = 0, h_pwrite = 0;
    reg         f_psel = 0, f_penable = 0, f_pwrite = 0;
    reg  [31:0] h_pwdata = 0, f_pwdata = 0;
    wire [31:0] h_prdata, f_prdata;
    wire        h_pready, f_pready, h_pslverr, f_pslverr;
    wire        fcu_hold, host_irq, fcu_irq, sys_reset;

    // Cycles sys_reset has been high since the last clear.
    integer sysrst_cycles = 0;
    always @(posedge clk) if (sys_reset) sysrst_cycles = sysrst_cycles + 1;

    amp_ctrl dut (
        .clk(clk), .rst(rst),
        .h_paddr(h_paddr), .h_psel(h_psel), .h_penable(h_penable), .h_pwrite(h_pwrite),
        .h_pwdata(h_pwdata), .h_prdata(h_prdata), .h_pready(h_pready), .h_pslverr(h_pslverr),
        .f_paddr(f_paddr), .f_psel(f_psel), .f_penable(f_penable), .f_pwrite(f_pwrite),
        .f_pwdata(f_pwdata), .f_prdata(f_prdata), .f_pready(f_pready), .f_pslverr(f_pslverr),
        .fcu_hold(fcu_hold), .host_irq(host_irq), .fcu_irq(fcu_irq), .sys_reset(sys_reset)
    );

    integer pass = 0, fail = 0;

    task check;
        input [255:0] what;
        input [31:0]  got;
        input [31:0]  want;
        begin
            if (got === want) begin
                pass = pass + 1;
            end else begin
                fail = fail + 1;
                $display("FAIL  %0s: got 0x%08h, want 0x%08h", what, got, want);
            end
        end
    endtask

    // ------------------------------------------------------------ APB BFMs
    // Setup phase on one edge, access phase on the next; the block has no
    // wait states, so the transfer completes on the access-phase edge.
    task h_xfer;
        input         wr;
        input  [11:0] a;
        input  [31:0] wd;
        output [31:0] rd;
        output        err;
        begin
            @(posedge clk);
            h_paddr <= a; h_pwrite <= wr; h_pwdata <= wd; h_psel <= 1'b1; h_penable <= 1'b0;
            @(posedge clk);
            h_penable <= 1'b1;
            @(negedge clk);
            rd = h_prdata; err = h_pslverr;
            @(posedge clk);
            h_psel <= 1'b0; h_penable <= 1'b0; h_pwrite <= 1'b0;
        end
    endtask

    task f_xfer;
        input         wr;
        input  [11:0] a;
        input  [31:0] wd;
        output [31:0] rd;
        output        err;
        begin
            @(posedge clk);
            f_paddr <= a; f_pwrite <= wr; f_pwdata <= wd; f_psel <= 1'b1; f_penable <= 1'b0;
            @(posedge clk);
            f_penable <= 1'b1;
            @(negedge clk);
            rd = f_prdata; err = f_pslverr;
            @(posedge clk);
            f_psel <= 1'b0; f_penable <= 1'b0; f_pwrite <= 1'b0;
        end
    endtask

    reg [31:0] rd, rd2;
    reg        err, err2;

    task settle; begin repeat (3) @(posedge clk); end endtask

    initial begin
        $dumpfile("tb_amp_ctrl.vcd");
        $dumpvars(0, tb_amp_ctrl);

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        settle;

        // --------------------------------------------------- reset values
        h_xfer(0, A_ID, 0, rd, err);      check("host ID", rd, 32'h414D5001);
                                          check("host ID err", err, 0);
        f_xfer(0, A_ID, 0, rd, err);      check("fcu ID", rd, 32'h414D5001);
        h_xfer(0, A_CTRL, 0, rd, err);    check("CTRL resets to hold", rd, 1);
        check("fcu_hold at reset", fcu_hold, 1);
        h_xfer(0, A_BOOT, 0, rd, err);    check("BOOT_ADDR reset", rd, 32'h0000_1000);
        h_xfer(0, A_STATUS, 0, rd, err);  check("STATUS reset", rd, 32'h1);
        check("host_irq idle", host_irq, 0);
        check("fcu_irq idle", fcu_irq, 0);

        // ------------------------------------------------ permission rules
        f_xfer(1, A_CTRL, 0, rd, err);    check("fcu write CTRL is an error", err, 1);
        settle;                           check("fcu cannot release itself", fcu_hold, 1);
        f_xfer(1, A_BOOT, 32'hDEAD_BEEF, rd, err);
                                          check("fcu write BOOT_ADDR is an error", err, 1);
        h_xfer(0, A_BOOT, 0, rd, err);    check("BOOT_ADDR unchanged by fcu", rd, 32'h0000_1000);
        f_xfer(1, A_ID, 0, rd, err);      check("fcu write ID is an error", err, 1);
        h_xfer(1, A_ID, 0, rd, err);      check("host write ID is an error", err, 1);
        h_xfer(1, A_STATUS, 0, rd, err);  check("host write STATUS is an error", err, 1);

        // --------------------------------------------- host-owned registers
        h_xfer(1, A_BOOT, 32'h9000_0000, rd, err);
                                          check("host write BOOT_ADDR ok", err, 0);
        f_xfer(0, A_BOOT, 0, rd, err);    check("fcu reads new BOOT_ADDR", rd, 32'h9000_0000);
        h_xfer(1, A_CTRL, 0, rd, err);    settle;
                                          check("host releases the FCU", fcu_hold, 0);
        f_xfer(0, A_STATUS, 0, rd, err);  check("STATUS shows release", rd[0], 0);
        h_xfer(1, A_CTRL, 1, rd, err);    settle;
                                          check("host holds the FCU again", fcu_hold, 1);

        // ---------------------------------------------- doorbell host -> FCU
        h_xfer(1, A_SEND, 32'h0000_0008, rd, err);
        f_xfer(0, A_PEND, 0, rd, err);    check("fcu sees host doorbell", rd, 32'h8);
        h_xfer(0, A_SEND, 0, rd, err);    check("host sees it still pending", rd, 32'h8);
        settle;                           check("masked out: no fcu irq", fcu_irq, 0);
        f_xfer(1, A_MASK, 32'h0000_0008, rd, err);
        settle;                           check("unmasked: fcu irq", fcu_irq, 1);
        h_xfer(0, A_STATUS, 0, rd, err);  check("STATUS shows fcu irq", rd[2], 1);
        f_xfer(1, A_PEND, 32'h0000_0008, rd, err);
        settle;                           check("fcu ack drops its irq", fcu_irq, 0);
        f_xfer(0, A_PEND, 0, rd, err);    check("pending cleared", rd, 0);

        // W1S accumulates, W1C is selective
        h_xfer(1, A_SEND, 32'h0000_0001, rd, err);
        h_xfer(1, A_SEND, 32'h0000_0002, rd, err);
        f_xfer(0, A_PEND, 0, rd, err);    check("doorbells accumulate", rd, 32'h3);
        f_xfer(1, A_PEND, 32'h0000_0001, rd, err);
        f_xfer(0, A_PEND, 0, rd, err);    check("W1C clears only its bits", rd, 32'h2);
        f_xfer(1, A_PEND, 32'hFFFF_FFFF, rd, err);

        // ---------------------------------------------- doorbell FCU -> host
        h_xfer(1, A_MASK, 32'h8000_0000, rd, err);
        f_xfer(1, A_SEND, 32'h0000_0100, rd, err);
        settle;                           check("unmasked bit: no host irq", host_irq, 0);
        h_xfer(0, A_PEND, 0, rd, err);    check("host sees fcu doorbell", rd, 32'h100);
        f_xfer(1, A_SEND, 32'h8000_0000, rd, err);
        settle;                           check("masked-in bit: host irq", host_irq, 1);
        h_xfer(1, A_PEND, 32'h8000_0100, rd, err);
        settle;                           check("host ack drops its irq", host_irq, 0);

        // ----------------------------- same-cycle set and clear: set wins
        h_xfer(1, A_SEND, 32'h0000_0010, rd, err);      // pending = 0x10
        fork
            h_xfer(1, A_SEND, 32'h0000_0010, rd,  err);  // ring again...
            f_xfer(1, A_PEND, 32'h0000_0010, rd2, err2); // ...while the FCU acks
        join
        f_xfer(0, A_PEND, 0, rd, err);    check("racing ring survives the ack", rd, 32'h10);
        f_xfer(1, A_PEND, 32'hFFFF_FFFF, rd, err);

        // -------------------------------------------------------- scratch
        h_xfer(1, A_SCR0 + 12'h00C, 32'hCAFE_0003, rd, err);
        f_xfer(0, A_SCR0 + 12'h00C, 0, rd, err);        check("fcu reads host scratch", rd, 32'hCAFE_0003);
        f_xfer(1, A_SCR0 + 12'h014, 32'hF00D_0005, rd, err);
        h_xfer(0, A_SCR0 + 12'h014, 0, rd, err);        check("host reads fcu scratch", rd, 32'hF00D_0005);
        fork
            h_xfer(1, A_SCR0, 32'h1111_1111, rd,  err);
            f_xfer(1, A_SCR0, 32'h2222_2222, rd2, err2);
        join
        h_xfer(0, A_SCR0, 0, rd, err);    check("scratch collision: host wins", rd, 32'h1111_1111);
        f_xfer(1, A_SCR0 + 12'h01C, 32'h7777_7777, rd, err);
                                          check("fcu may write scratch7", err, 0);

        // --------------------------------------------------------- errors
        // SYS_RESET: host only, and only the key.
        sysrst_cycles = 0;
        h_xfer(0, A_SYSRST, 0, rd, err);  check("sys_reset reads without error", err, 0);
                                          check("sys_reset reads 0", rd, 0);
        h_xfer(1, A_SYSRST, 32'h1234_5678, rd, err);
                                          check("sys_reset wrong key is an error", err, 1);
        f_xfer(1, A_SYSRST, RST_KEY, rd, err);
                                          check("fcu may not write sys_reset", err, 1);
        f_xfer(0, A_SYSRST, 0, rd, err);  check("fcu may not read sys_reset", err, 1);
        repeat (3) @(posedge clk);
        check("no reset from refused writes", sysrst_cycles, 0);
        h_xfer(1, A_SYSRST, RST_KEY, rd, err);
                                          check("sys_reset key accepted", err, 0);
        repeat (3) @(posedge clk);
        check("sys_reset pulses one cycle", sysrst_cycles, 1);
        h_xfer(0, 12'h040, 0, rd, err);   check("past the register file", err, 1);
        f_xfer(0, 12'h800, 0, rd, err);   check("far in the window", err, 1);
        h_xfer(0, A_MASK, 0, rd, err);    check("valid read has no error", err, 0);

        // No access: error must stay low.
        @(negedge clk);                   check("idle: no pslverr", h_pslverr | f_pslverr, 0);
        check("pready is always high", h_pready & f_pready, 1);

        // ----------------------------------------- reset returns to hold
        h_xfer(1, A_CTRL, 0, rd, err);    settle;
        rst <= 1'b1; settle; rst <= 1'b0; settle;
        check("reset re-holds the FCU", fcu_hold, 1);
        h_xfer(0, A_SCR0, 0, rd, err);    check("reset clears scratch", rd, 0);

        $display("");
        $display("tb_amp_ctrl: %0d passed, %0d failed", pass, fail);
        if (fail != 0) $fatal(1, "tb_amp_ctrl FAILED");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "tb_amp_ctrl: timeout");
    end

endmodule
