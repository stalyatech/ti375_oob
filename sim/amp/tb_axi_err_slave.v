// =============================================================================
// tb_axi_err_slave.v
//
// Self-checking testbench for rtl/axi_err_slave.v: write and read bursts of
// several lengths with random back-pressure. Checks DECERR on every response,
// exactly ARLEN+1 read beats with RLAST only on the last, zero read data and
// echoed IDs, and that the slave returns to idle after each transaction.
// =============================================================================
`timescale 1ns / 1ps

module tb_axi_err_slave;

    reg clk = 0, rst = 1;
    always #2.5 clk = ~clk;

    reg        awvalid = 0, wvalid = 0, wlast = 0, bready = 0, arvalid = 0, rready = 0;
    reg  [7:0] awid = 0, arid = 0, arlen = 0;
    wire       awready, wready, bvalid, arready, rvalid, rlast;
    wire [7:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    axi_err_slave dut (
        .clk(clk), .rst(rst),
        .awvalid(awvalid), .awready(awready), .awid(awid),
        .wvalid(wvalid), .wready(wready), .wlast(wlast),
        .bvalid(bvalid), .bready(bready), .bid(bid), .bresp(bresp),
        .arvalid(arvalid), .arready(arready), .arid(arid), .arlen(arlen),
        .rvalid(rvalid), .rready(rready), .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast)
    );

    integer pass = 0, fail = 0, seed = 3;

    task check;
        input [255:0] what; input [31:0] got; input [31:0] want;
        begin
            if (got === want) pass = pass + 1;
            else begin fail = fail + 1; $display("FAIL  %0s: got 0x%0h, want 0x%0h", what, got, want); end
        end
    endtask

    task wr;
        input [7:0] id; input [7:0] len;
        integer b;
        begin
            @(posedge clk); awvalid <= 1; awid <= id;
            @(posedge clk); while (!awready) @(posedge clk);
            awvalid <= 0; awid <= $random(seed);
            for (b = 0; b <= len; b = b + 1) begin
                wvalid <= 1; wlast <= (b == len);
                @(posedge clk); while (!wready) @(posedge clk);
            end
            wvalid <= 0; wlast <= 0;
            while (!(bvalid && bready)) begin @(posedge clk); bready <= ($random(seed) % 2 == 0); end
            check("write DECERR", bresp, 2'b11);
            check("write BID echoed", bid, id);
            @(negedge clk); bready <= 0;
        end
    endtask

    task rd;
        input [7:0] id; input [7:0] len;
        integer beats;
        begin
            @(posedge clk); arvalid <= 1; arid <= id; arlen <= len;
            @(posedge clk); while (!arready) @(posedge clk);
            arvalid <= 0; arid <= $random(seed); arlen <= $random(seed);
            beats = 0;
            while (beats <= len) begin
                rready <= ($random(seed) % 3 != 0);
                @(posedge clk);
                if (rvalid && rready) begin
                    check("read DECERR", rresp, 2'b11);
                    check("read data is zero", rdata, 0);
                    check("read RID echoed", rid, id);
                    check("RLAST only on the last beat", rlast, beats == len);
                    beats = beats + 1;
                end
            end
            rready <= 0;
            repeat (3) @(posedge clk);
            check("no extra read beats", rvalid, 0);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk); rst <= 0; repeat (2) @(posedge clk);
        check("idle: AWREADY", awready, 1);
        check("idle: ARREADY", arready, 1);

        wr(8'h11, 0);  wr(8'h22, 3);  wr(8'h33, 15);
        rd(8'h44, 0);  rd(8'h55, 3);  rd(8'h66, 15); rd(8'h77, 255);

        fork wr(8'hA1, 7); rd(8'hB2, 7); join

        repeat (4) @(posedge clk);
        check("back to idle: AWREADY", awready, 1);
        check("back to idle: ARREADY", arready, 1);

        $display("");
        $display("tb_axi_err_slave: %0d passed, %0d failed", pass, fail);
        if (fail != 0) $fatal(1, "tb_axi_err_slave FAILED");
        $finish;
    end

    initial begin #500000; $fatal(1, "tb_axi_err_slave: timeout"); end

endmodule
