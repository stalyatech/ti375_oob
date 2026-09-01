// =============================================================================
// axi4_mem_model.sv
//
// Behavioural AXI4 slave memory for the StalyaNPU benches: two address
// windows (blob and scratch) backed by flat arrays of 128-bit words, random
// latency and backpressure on every channel (seeded), one read burst and
// one write burst in flight at a time. Bursts are INCR; accesses outside
// the windows return SLVERR and are counted.
//
// The bench fills the windows through the load_word task and inspects them
// through the peek_byte function.
// =============================================================================
`timescale 1ns / 1ps

module axi4_mem_model #(
    parameter AXI_DW = 128,
    parameter [31:0] WIN0_BASE = 32'h20000000,
    parameter WIN0_WORDS = 1 << 16,
    parameter [31:0] WIN1_BASE = 32'h28000000,
    parameter WIN1_WORDS = 1 << 16
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         bp_i,
    input  wire         arvalid,
    output reg          arready,
    input  wire [31:0]  araddr,
    input  wire [7:0]   arlen,
    input  wire [3:0]   arid,
    output reg          rvalid,
    input  wire         rready,
    output reg  [AXI_DW-1:0] rdata,
    output reg  [3:0]   rid,
    output reg          rlast,
    output reg  [1:0]   rresp,
    input  wire         awvalid,
    output reg          awready,
    input  wire [31:0]  awaddr,
    input  wire [7:0]   awlen,
    input  wire         wvalid,
    output reg          wready,
    input  wire [AXI_DW-1:0] wdata,
    input  wire [AXI_DW/8-1:0] wstrb,
    input  wire         wlast,
    output reg          bvalid,
    input  wire         bready,
    output reg  [1:0]   bresp,
    output integer      errors
);

    localparam BEAT_BYTES = AXI_DW / 8;
    localparam WORDS_PER_BEAT = BEAT_BYTES / 16;

    reg [127:0] win0 [0:WIN0_WORDS-1];
    reg [127:0] win1 [0:WIN1_WORDS-1];

    function in_win0; input [31:0] a; in_win0 = (a >= WIN0_BASE) && (a < WIN0_BASE + WIN0_WORDS * 16); endfunction
    function in_win1; input [31:0] a; in_win1 = (a >= WIN1_BASE) && (a < WIN1_BASE + WIN1_WORDS * 16); endfunction

    function [127:0] get_word;
        input [31:0] a;
        begin
            if (in_win0(a)) get_word = win0[(a - WIN0_BASE) >> 4];
            else if (in_win1(a)) get_word = win1[(a - WIN1_BASE) >> 4];
            else get_word = 128'hDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;
        end
    endfunction

    task set_word;
        input [31:0] a;
        input [127:0] v;
        begin
            if (in_win0(a)) win0[(a - WIN0_BASE) >> 4] = v;
            else if (in_win1(a)) win1[(a - WIN1_BASE) >> 4] = v;
        end
    endtask

    task load_word;
        input [31:0] a;
        input [127:0] v;
        begin
            set_word(a, v);
        end
    endtask

    function [7:0] peek_byte;
        input [31:0] a;
        reg [127:0] w;
        begin
            w = get_word(a);
            peek_byte = w[a[3:0] * 8 +: 8];
        end
    endfunction

    // Random helpers.
    integer seed = 1;
    function stall; input integer p; stall = bp_i && (($urandom % 100) < p); endfunction

    // ---- read side
    reg [31:0] r_addr;
    reg [7:0]  r_left;
    reg        r_busy;
    integer    r_lat;
    reg [3:0]  r_id;

    always @(posedge clk) begin
        if (rst) begin
            arready <= 1'b0; rvalid <= 1'b0; rdata <= 0; rid <= 4'd0; rlast <= 1'b0; rresp <= 2'b00;
            r_busy <= 1'b0; r_left <= 8'd0; r_addr <= 32'd0; r_lat <= 0; r_id <= 4'd0;
        end else begin
            arready <= !r_busy && !arready && !stall(30);
            if (arvalid && arready) begin
                r_busy <= 1'b1; r_addr <= araddr; r_left <= arlen; r_id <= arid;
                r_lat <= bp_i ? 2 + ($urandom % 12) : 1;
                arready <= 1'b0;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                if (rlast) r_busy <= 1'b0;
            end
            if (r_busy && (!rvalid || rready) && !(rvalid && rready && rlast)) begin
                if (r_lat > 0) begin
                    r_lat <= r_lat - 1;
                end else if (!stall(20) || rvalid) begin
                    if (!rvalid || rready) begin
                        rvalid <= 1'b1;
                        rid <= r_id;
                        rlast <= (r_left == 8'd0);
                        rresp <= (in_win0(r_addr) || in_win1(r_addr)) ? 2'b00 : 2'b10;
                        if (!(in_win0(r_addr) || in_win1(r_addr))) errors = errors + 1;
                        if (WORDS_PER_BEAT == 1)
                            rdata <= get_word(r_addr);
                        else
                            rdata <= {get_word(r_addr + 16), get_word(r_addr)};
                        r_addr <= r_addr + BEAT_BYTES;
                        r_left <= r_left - 1'b1;
                    end
                end
            end
        end
    end

    // ---- write side
    reg [31:0] w_addr;
    reg        aw_got, w_done;
    reg [7:0]  w_beats;
    integer    b_lat;
    reg [127:0] tmp;
    integer k;

    always @(posedge clk) begin
        if (rst) begin
            awready <= 1'b0; wready <= 1'b0; bvalid <= 1'b0; bresp <= 2'b00;
            aw_got <= 1'b0; w_done <= 1'b0; w_addr <= 32'd0; w_beats <= 8'd0; b_lat <= 0;
        end else begin
            awready <= !aw_got && !awready && !stall(30);
            if (awvalid && awready) begin
                aw_got <= 1'b1; w_addr <= awaddr; w_beats <= awlen; awready <= 1'b0; w_done <= 1'b0;
            end
            wready <= aw_got && !w_done && !stall(20);
            if (wvalid && wready) begin
                if (in_win0(w_addr) || in_win1(w_addr)) begin
                    for (k = 0; k < WORDS_PER_BEAT; k = k + 1) begin
                        tmp = get_word(w_addr + k * 16);
                        tmp = (tmp & ~strb_mask(wstrb[k*16 +: 16])) | (wdata[k*128 +: 128] & strb_mask(wstrb[k*16 +: 16]));
                        set_word(w_addr + k * 16, tmp);
                    end
                end else begin
                    errors = errors + 1;
                end
                w_addr <= w_addr + BEAT_BYTES;
                if (wlast) begin
                    w_done <= 1'b1;
                    wready <= 1'b0;
                    b_lat <= bp_i ? 1 + ($urandom % 6) : 1;
                end
            end
            if (aw_got && w_done && !bvalid) begin
                if (b_lat > 0) b_lat <= b_lat - 1;
                else begin
                    bvalid <= 1'b1;
                    bresp <= 2'b00;
                end
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                aw_got <= 1'b0;
                w_done <= 1'b0;
            end
        end
    end

    function [127:0] strb_mask;
        input [15:0] s;
        integer b;
        begin
            for (b = 0; b < 16; b = b + 1)
                strb_mask[b*8 +: 8] = {8{s[b]}};
        end
    endfunction

    initial errors = 0;

endmodule
