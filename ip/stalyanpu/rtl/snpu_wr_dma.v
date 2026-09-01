// =============================================================================
// snpu_wr_dma.v
//
// AXI4 write master for 32 byte words. Every input word carries its own
// byte address; each word becomes one write transaction of 32 / (AXI_DW/8)
// beats with all strobes set. Write responses are counted so idle_o tells
// the sequencer when every word landed in memory.
//
// One transaction at a time is presented on the address and data channels;
// several may be outstanding on the response channel.
// =============================================================================
`timescale 1ns / 1ps

module snpu_wr_dma #(
    parameter AXI_DW = 128
)(
    input  wire         clk,
    input  wire         rst,
    // word stream in
    input  wire         w_valid_i,
    input  wire [31:0]  w_addr_i,
    input  wire [255:0] w_data_i,
    output wire         w_ready_o,
    output wire         idle_o,
    // AXI4 write channels
    output reg          m_awvalid,
    input  wire         m_awready,
    output reg  [31:0]  m_awaddr,
    output wire [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire [3:0]   m_awid,
    output reg          m_wvalid,
    input  wire         m_wready,
    output wire [AXI_DW-1:0] m_wdata,
    output wire [AXI_DW/8-1:0] m_wstrb,
    output reg          m_wlast,
    input  wire         m_bvalid,
    output wire         m_bready,
    input  wire [1:0]   m_bresp,
    output reg          err_o
);

    localparam BEAT_BYTES = AXI_DW / 8;
    localparam BEATS = 32 / BEAT_BYTES;

    assign m_awlen   = BEATS - 1;
    assign m_awsize  = (AXI_DW == 256) ? 3'd5 : (AXI_DW == 128) ? 3'd4 : 3'd3;
    assign m_awburst = 2'b01;
    assign m_awid    = 4'd0;
    assign m_wstrb   = {(AXI_DW/8){1'b1}};
    assign m_bready  = 1'b1;

    reg [255:0] data;
    reg [2:0]   beat;
    reg         busy;
    reg [7:0]   pending;     // transactions waiting for a response

    assign w_ready_o = !busy;
    assign m_wdata = data[beat * AXI_DW +: AXI_DW];
    assign idle_o = !busy && (pending == 8'd0);

    wire aw_done_now = m_awvalid && m_awready;
    wire w_done_now  = m_wvalid && m_wready && m_wlast;
    reg  aw_done, w_done;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; beat <= 3'd0; data <= 256'd0; pending <= 8'd0;
            m_awvalid <= 1'b0; m_awaddr <= 32'd0; m_wvalid <= 1'b0; m_wlast <= 1'b0;
            aw_done <= 1'b0; w_done <= 1'b0; err_o <= 1'b0;
        end else begin
            if (m_bvalid) begin
                if (m_bresp[1]) err_o <= 1'b1;
            end
            pending <= pending + ((busy && aw_done_now) ? 8'd1 : 8'd0) - (m_bvalid ? 8'd1 : 8'd0);
            if (!busy) begin
                if (w_valid_i) begin
                    busy <= 1'b1;
                    data <= w_data_i;
                    m_awaddr <= w_addr_i;
                    m_awvalid <= 1'b1;
                    m_wvalid <= 1'b1;
                    beat <= 3'd0;
                    m_wlast <= (BEATS == 1);
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                end
            end else begin
                if (aw_done_now) begin
                    m_awvalid <= 1'b0;
                    aw_done <= 1'b1;
                end
                if (m_wvalid && m_wready) begin
                    if (m_wlast) begin
                        m_wvalid <= 1'b0;
                        w_done <= 1'b1;
                    end else begin
                        beat <= beat + 1'b1;
                        m_wlast <= (beat == BEATS - 2);
                    end
                end
                if ((aw_done || aw_done_now) && (w_done || w_done_now))
                    busy <= 1'b0;
            end
        end
    end

endmodule
