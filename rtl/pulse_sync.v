// =============================================================================
// pulse_sync.v
//
// Moves a single-cycle pulse from one clock domain to another with a toggle
// register and a three-stage synchronizer. Used to carry the write-1-to-clear
// request for the DNN done interrupt from the peripheral clock into the DNN
// clock domain. Source pulses must be at least one destination clock period
// apart, which APB register writes easily satisfy.
//
// Language: Verilog 2001. Resets: active-low async, one per domain.
// =============================================================================
`timescale 1ns / 1ps

module pulse_sync (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse
);

    reg       src_toggle;
    reg [2:0] dst_sync;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n)
            src_toggle <= 1'b0;
        else if (src_pulse)
            src_toggle <= ~src_toggle;
    end

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n)
            dst_sync <= 3'b000;
        else
            dst_sync <= {dst_sync[1:0], src_toggle};
    end

    assign dst_pulse = dst_sync[2] ^ dst_sync[1];

endmodule
