// =============================================================================
// snpu_csr.v
//
// APB3 control and status registers of the accelerator, register map in
// docs/stalyanpu/isa-descriptor.md (source: backend/isa.py). Runs in the
// accelerator clock domain; the clock domain crossing to the peripheral
// bus is added at the top level of the FPGA project.
// =============================================================================
`timescale 1ns / 1ps

module snpu_csr #(
    parameter [31:0] VERSION = 32'h00000100,
    parameter [31:0] GEOMETRY = 32'h0
)(
    input  wire        clk,
    input  wire        rst,
    // APB3
    input  wire [6:0]  paddr_i,
    input  wire        psel_i,
    input  wire        penable_i,
    input  wire        pwrite_i,
    input  wire [31:0] pwdata_i,
    output reg  [31:0] prdata_o,
    output wire        pready_o,
    output wire        pslverr_o,
    // control
    output reg         start_o,          // one cycle pulse
    output reg         abort_o,
    output reg         soft_rst_o,
    output reg  [31:0] desc_base_o,
    output reg  [31:0] desc_count_o,
    // status inputs
    input  wire        busy_i,
    input  wire [7:0]  err_code_i,
    input  wire [15:0] desc_idx_i,
    input  wire [31:0] tag_i,
    input  wire        done_i,           // pulse
    input  wire        desc_done_i,      // pulse
    input  wire        error_i,          // pulse
    input  wire        timeout_i,        // pulse
    input  wire        stall_ibuf_i,
    input  wire        stall_wgt_i,
    input  wire        stall_acc_i,
    input  wire        stall_wr_i,
    input  wire [31:0] dbg0_i,
    input  wire [31:0] dbg1_i,
    input  wire [31:0] dbg2_i,
    input  wire [31:0] dbg3_i,
    input  wire [31:0] dbg4_i,
    input  wire [31:0] dbg5_i,
    output wire        irq_o
);

    reg [3:0]  irq_status, irq_mask;
    reg [31:0] cycle_cnt, stall_ibuf, stall_wgt, stall_acc, stall_wr, desc_done_cnt;

    assign pready_o = 1'b1;
    assign pslverr_o = 1'b0;
    assign irq_o = |(irq_status & irq_mask);

    wire wr = psel_i && penable_i && pwrite_i;

    always @(posedge clk) begin
        if (rst) begin
            start_o <= 1'b0; abort_o <= 1'b0; soft_rst_o <= 1'b0;
            desc_base_o <= 32'd0; desc_count_o <= 32'd0;
            irq_status <= 4'd0; irq_mask <= 4'd0;
            cycle_cnt <= 32'd0; stall_ibuf <= 32'd0; stall_wgt <= 32'd0; stall_acc <= 32'd0; stall_wr <= 32'd0;
            desc_done_cnt <= 32'd0;
        end else begin
            start_o <= 1'b0;
            abort_o <= 1'b0;
            soft_rst_o <= 1'b0;
            // Sticky interrupt bits.
            if (done_i)      irq_status[0] <= 1'b1;
            if (desc_done_i) irq_status[1] <= 1'b1;
            if (error_i)     irq_status[2] <= 1'b1;
            if (timeout_i)   irq_status[3] <= 1'b1;
            // Counters.
            if (busy_i) begin
                cycle_cnt <= cycle_cnt + 1'b1;
                if (stall_ibuf_i) stall_ibuf <= stall_ibuf + 1'b1;
                if (stall_wgt_i)  stall_wgt <= stall_wgt + 1'b1;
                if (stall_acc_i)  stall_acc <= stall_acc + 1'b1;
                if (stall_wr_i)   stall_wr <= stall_wr + 1'b1;
            end
            if (desc_done_i) desc_done_cnt <= desc_done_cnt + 1'b1;
            if (wr) begin
                case (paddr_i)
                    7'h0C: begin
                        if (pwdata_i[0]) begin
                            start_o <= 1'b1;
                            cycle_cnt <= 32'd0; stall_ibuf <= 32'd0; stall_wgt <= 32'd0;
                            stall_acc <= 32'd0; stall_wr <= 32'd0; desc_done_cnt <= 32'd0;
                        end
                        abort_o <= pwdata_i[1];
                        soft_rst_o <= pwdata_i[2];
                    end
                    7'h14: desc_base_o <= pwdata_i;
                    7'h18: desc_count_o <= pwdata_i;
                    7'h1C: irq_status <= irq_status & ~pwdata_i[3:0];
                    7'h20: irq_mask <= pwdata_i[3:0];
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (paddr_i)
            7'h00: prdata_o = 32'h534E5055;
            7'h04: prdata_o = VERSION;
            7'h08: prdata_o = GEOMETRY;
            7'h0C: prdata_o = 32'd0;
            7'h10: prdata_o = {desc_idx_i, 8'd0, err_code_i[7:0]} | {31'd0, busy_i};
            7'h14: prdata_o = desc_base_o;
            7'h18: prdata_o = desc_count_o;
            7'h1C: prdata_o = {28'd0, irq_status};
            7'h20: prdata_o = {28'd0, irq_mask};
            7'h24: prdata_o = cycle_cnt;
            7'h28: prdata_o = stall_ibuf;
            7'h2C: prdata_o = stall_wgt;
            7'h30: prdata_o = stall_acc;
            7'h34: prdata_o = stall_wr;
            7'h38: prdata_o = desc_done_cnt;
            7'h3C: prdata_o = tag_i;
            7'h40: prdata_o = dbg0_i;
            7'h44: prdata_o = dbg1_i;
            7'h48: prdata_o = dbg2_i;
            7'h4C: prdata_o = dbg3_i;
            7'h50: prdata_o = dbg4_i;
            7'h54: prdata_o = dbg5_i;
            default: prdata_o = 32'd0;
        endcase
    end

endmodule
