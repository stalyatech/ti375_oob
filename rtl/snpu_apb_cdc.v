// =============================================================================
// snpu_apb_cdc.v
//
// APB3 clock domain bridge for the StalyaNPU CSR window. The source side
// lives in the peripheral clock domain of the hard SoC, the destination
// side in the accelerator clock domain. One transfer is in flight at a
// time: the source latches the command, toggles a request, holds PREADY
// low and completes when the acknowledge toggle returns with the captured
// read data. CSR accesses are rare, so the handshake latency is harmless.
// =============================================================================
`timescale 1ns / 1ps

module snpu_apb_cdc (
    // source side, peripheral clock
    input  wire        s_clk,
    input  wire        s_rst,
    input  wire [6:0]  s_paddr,
    input  wire        s_psel,
    input  wire        s_penable,
    input  wire        s_pwrite,
    input  wire [31:0] s_pwdata,
    output wire [31:0] s_prdata,
    output wire        s_pready,
    output wire        s_pslverr,
    // destination side, accelerator clock
    input  wire        d_clk,
    input  wire        d_rst,
    output reg  [6:0]  d_paddr,
    output reg         d_psel,
    output reg         d_penable,
    output reg         d_pwrite,
    output reg  [31:0] d_pwdata,
    input  wire [31:0] d_prdata,
    input  wire        d_pready,
    input  wire        d_pslverr
);

    // Source side. The command registers are stable from the request toggle
    // until the acknowledge comes back, so the destination samples them
    // safely after its two flop synchroniser.
    reg        req_t, busy;
    reg [6:0]  l_addr;
    reg        l_write;
    reg [31:0] l_wdata;
    reg [1:0]  ack_sync;
    wire       done = busy && (ack_sync[1] == req_t);

    always @(posedge s_clk) begin
        if (s_rst) begin
            req_t <= 1'b0; busy <= 1'b0;
            l_addr <= 7'd0; l_write <= 1'b0; l_wdata <= 32'd0;
        end else begin
            if (s_psel && s_penable && !busy) begin
                l_addr <= s_paddr;
                l_write <= s_pwrite;
                l_wdata <= s_pwdata;
                req_t <= ~req_t;
                busy <= 1'b1;
            end else if (done) begin
                busy <= 1'b0;
            end
        end
    end

    assign s_pready = done;

    // Destination side: one APB transaction per request edge.
    reg [1:0] req_sync;
    reg       ack_t, run;
    reg [31:0] cap_rdata;
    reg        cap_slverr;

    always @(posedge d_clk) begin
        if (d_rst) begin
            req_sync <= 2'b00; ack_t <= 1'b0; run <= 1'b0;
            d_psel <= 1'b0; d_penable <= 1'b0; d_pwrite <= 1'b0;
            d_paddr <= 7'd0; d_pwdata <= 32'd0;
            cap_rdata <= 32'd0; cap_slverr <= 1'b0;
        end else begin
            req_sync <= {req_sync[0], req_t};
            if (!run && (req_sync[1] != ack_t)) begin
                run <= 1'b1;
                d_psel <= 1'b1;
                d_penable <= 1'b0;
                d_paddr <= l_addr;
                d_pwrite <= l_write;
                d_pwdata <= l_wdata;
            end else if (run && !d_penable) begin
                d_penable <= 1'b1;
            end else if (run && d_penable && d_pready) begin
                cap_rdata <= d_prdata;
                cap_slverr <= d_pslverr;
                d_psel <= 1'b0;
                d_penable <= 1'b0;
                run <= 1'b0;
                ack_t <= ~ack_t;
            end
        end
    end

    // The captured read data is stable well before the acknowledge toggle
    // reaches the source synchroniser.
    always @(posedge s_clk) begin
        if (s_rst) ack_sync <= 2'b00;
        else ack_sync <= {ack_sync[0], ack_t};
    end

    assign s_prdata = cap_rdata;
    assign s_pslverr = cap_slverr;

endmodule
