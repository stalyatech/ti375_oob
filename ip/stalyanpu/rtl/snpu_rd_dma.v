// =============================================================================
// snpu_rd_dma.v
//
// AXI4 read master with two command channels. Channel 0 serves the bulk
// transfers of the sequencer (descriptors, parameters, tables, input rows,
// residual words), channel 1 streams weights. A command describes a three
// level nest of chunks:
//
//     for i2 < n2: for i1 < n1: for i0 < n0:
//         read len bytes at addr + i0*s0 + i1*s1 + i2*s2
//
// and delivers the data as 256-bit words in order, with the destination
// code of the command and a last flag on the final word.
//
// Addresses and lengths are multiples of 32 bytes. Chunks are split into
// bursts of at most BURST_BYTES that never cross a 4 KB boundary. Up to
// MAX_OUTSTANDING bursts per channel are in flight; the AXI ID carries the
// channel so returning data is routed by RID. The read data channel is
// held (rready low) while the destination of the head word is not ready.
// =============================================================================
`timescale 1ns / 1ps

module snpu_rd_dma #(
    parameter AXI_DW = 128,
    parameter BURST_BYTES = 256,
    parameter MAX_OUTSTANDING = 4
)(
    input  wire         clk,
    input  wire         rst,
    // command channels, fields packed {ch1, ch0}
    input  wire [1:0]   cmd_valid_i,
    output wire [1:0]   cmd_ready_o,
    input  wire [63:0]  cmd_addr_i,
    input  wire [63:0]  cmd_len_i,       // bytes per chunk
    input  wire [31:0]  cmd_n0_i,        // 16 bits per channel
    input  wire [63:0]  cmd_s0_i,
    input  wire [31:0]  cmd_n1_i,
    input  wire [63:0]  cmd_s1_i,
    input  wire [31:0]  cmd_n2_i,
    input  wire [63:0]  cmd_s2_i,
    input  wire [7:0]   cmd_dst_i,       // 4 bits per channel
    // data channels
    output wire [1:0]   d_valid_o,
    output wire [511:0] d_data_o,
    output wire [7:0]   d_dst_o,
    output wire [1:0]   d_last_o,
    input  wire [1:0]   d_ready_i,
    output wire [1:0]   busy_o,
    // AXI4 read address and data
    output reg          m_arvalid,
    input  wire         m_arready,
    output reg  [31:0]  m_araddr,
    output reg  [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output reg  [3:0]   m_arid,
    input  wire         m_rvalid,
    output wire         m_rready,
    input  wire [AXI_DW-1:0] m_rdata,
    input  wire [3:0]   m_rid,
    input  wire         m_rlast,
    input  wire [1:0]   m_rresp,
    output reg          err_o
);

    localparam BEAT_BYTES = AXI_DW / 8;
    localparam BEATS_PER_WORD = 32 / BEAT_BYTES;

    assign m_arsize  = (AXI_DW == 256) ? 3'd5 : (AXI_DW == 128) ? 3'd4 : 3'd3;
    assign m_arburst = 2'b01;

    // Per channel command state.
    reg        active   [0:1];
    reg [31:0] base     [0:1];
    reg [31:0] len      [0:1];
    reg [15:0] n0 [0:1], n1 [0:1], n2 [0:1];
    reg [31:0] s0 [0:1], s1 [0:1], s2 [0:1];
    reg [3:0]  dst      [0:1];
    // issue side
    reg [15:0] i0 [0:1], i1 [0:1], i2 [0:1];
    reg [31:0] chunk_addr [0:1];
    reg [31:0] chunk_left [0:1];
    reg        issue_done [0:1];
    reg [3:0]  outstanding [0:1];
    // receive side
    reg [31:0] r_total [0:1];      // bytes still to be received for the command
    reg [2:0]  beat_cnt [0:1];
    reg [255:0] word_acc [0:1];

    genvar c;
    generate
        for (c = 0; c < 2; c = c + 1) begin : g_ch
            assign cmd_ready_o[c] = !active[c];
            assign busy_o[c] = active[c];
        end
    endgenerate

    function [31:0] burst_bytes;
        input [31:0] addr;
        input [31:0] left;
        reg [31:0] to_boundary;
        begin
            to_boundary = 32'd4096 - {20'd0, addr[11:0]};
            burst_bytes = left;
            if (burst_bytes > BURST_BYTES) burst_bytes = BURST_BYTES;
            if (burst_bytes > to_boundary) burst_bytes = to_boundary;
        end
    endfunction

    // Address issue: round robin between channels with pending bursts.
    reg rr;
    wire can0 = active[0] && !issue_done[0] && (outstanding[0] < MAX_OUTSTANDING);
    wire can1 = active[1] && !issue_done[1] && (outstanding[1] < MAX_OUTSTANDING);
    wire pick = (can0 && can1) ? rr : can1;
    wire issue = (can0 || can1) && !m_arvalid;
    wire [31:0] pick_bytes = burst_bytes(chunk_addr[pick], chunk_left[pick]);
    reg issue_ch;

    // Read data routing.
    wire rch = m_rid[0];
    wire word_done = (beat_cnt[rch] == BEATS_PER_WORD - 1);
    reg [1:0] dv;
    reg [511:0] dd;
    reg [1:0] dl;
    reg [7:0] ddst;
    wire out_free0 = !dv[0] || d_ready_i[0];
    wire out_free1 = !dv[1] || d_ready_i[1];
    assign m_rready = rch ? out_free1 : out_free0;
    assign d_valid_o = dv;
    assign d_data_o = dd;
    assign d_last_o = dl;
    assign d_dst_o = ddst;

    wire burst_end = m_rvalid && m_rready && m_rlast;
    wire ar_go = m_arvalid && m_arready;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 2; i = i + 1) begin
                active[i] <= 1'b0; base[i] <= 32'd0; len[i] <= 32'd0; dst[i] <= 4'd0;
                n0[i] <= 16'd0; n1[i] <= 16'd0; n2[i] <= 16'd0; s0[i] <= 32'd0; s1[i] <= 32'd0; s2[i] <= 32'd0;
                i0[i] <= 16'd0; i1[i] <= 16'd0; i2[i] <= 16'd0; chunk_addr[i] <= 32'd0; chunk_left[i] <= 32'd0;
                issue_done[i] <= 1'b0; outstanding[i] <= 4'd0; r_total[i] <= 32'd0; beat_cnt[i] <= 3'd0;
                word_acc[i] <= 256'd0;
            end
            m_arvalid <= 1'b0; m_araddr <= 32'd0; m_arlen <= 8'd0; m_arid <= 4'd0;
            rr <= 1'b0; issue_ch <= 1'b0;
            dv <= 2'b00; dd <= 512'd0; dl <= 2'b00; ddst <= 8'd0; err_o <= 1'b0;
        end else begin
            // Command acceptance.
            for (i = 0; i < 2; i = i + 1) begin
                if (cmd_valid_i[i] && !active[i]) begin
                    active[i] <= 1'b1;
                    base[i] <= cmd_addr_i[i*32 +: 32];
                    len[i] <= cmd_len_i[i*32 +: 32];
                    n0[i] <= cmd_n0_i[i*16 +: 16]; n1[i] <= cmd_n1_i[i*16 +: 16]; n2[i] <= cmd_n2_i[i*16 +: 16];
                    s0[i] <= cmd_s0_i[i*32 +: 32]; s1[i] <= cmd_s1_i[i*32 +: 32]; s2[i] <= cmd_s2_i[i*32 +: 32];
                    dst[i] <= cmd_dst_i[i*4 +: 4];
                    i0[i] <= 16'd0; i1[i] <= 16'd0; i2[i] <= 16'd0;
                    chunk_addr[i] <= cmd_addr_i[i*32 +: 32];
                    chunk_left[i] <= cmd_len_i[i*32 +: 32];
                    issue_done[i] <= 1'b0;
                    r_total[i] <= cmd_len_i[i*32 +: 32] * cmd_n0_i[i*16 +: 16] * cmd_n1_i[i*16 +: 16] * cmd_n2_i[i*16 +: 16];
                    beat_cnt[i] <= 3'd0;
                end
            end
            // Address channel.
            if (ar_go)
                m_arvalid <= 1'b0;
            if (issue) begin
                m_arvalid <= 1'b1;
                m_araddr <= chunk_addr[pick];
                m_arlen <= (pick_bytes / BEAT_BYTES) - 1;
                m_arid <= {3'd0, pick};
                issue_ch <= pick;
                rr <= ~pick;
                if (chunk_left[pick] == pick_bytes) begin
                    // Chunk complete: advance the nest.
                    if (i0[pick] + 1 < n0[pick]) begin
                        i0[pick] <= i0[pick] + 1'b1;
                        chunk_addr[pick] <= base[pick] + (i0[pick] + 1) * s0[pick] + i1[pick] * s1[pick] + i2[pick] * s2[pick];
                    end else if (i1[pick] + 1 < n1[pick]) begin
                        i0[pick] <= 16'd0;
                        i1[pick] <= i1[pick] + 1'b1;
                        chunk_addr[pick] <= base[pick] + (i1[pick] + 1) * s1[pick] + i2[pick] * s2[pick];
                    end else if (i2[pick] + 1 < n2[pick]) begin
                        i0[pick] <= 16'd0;
                        i1[pick] <= 16'd0;
                        i2[pick] <= i2[pick] + 1'b1;
                        chunk_addr[pick] <= base[pick] + (i2[pick] + 1) * s2[pick];
                    end else begin
                        issue_done[pick] <= 1'b1;
                    end
                    chunk_left[pick] <= len[pick];
                end else begin
                    chunk_addr[pick] <= chunk_addr[pick] + pick_bytes;
                    chunk_left[pick] <= chunk_left[pick] - pick_bytes;
                end
            end
            // Outstanding counters.
            for (i = 0; i < 2; i = i + 1)
                outstanding[i] <= outstanding[i] + ((ar_go && (issue_ch == i)) ? 4'd1 : 4'd0)
                                                 - ((burst_end && (rch == i)) ? 4'd1 : 4'd0);
            // Data channel.
            for (i = 0; i < 2; i = i + 1)
                if (dv[i] && d_ready_i[i])
                    dv[i] <= 1'b0;
            if (m_rvalid && m_rready) begin
                if (m_rresp[1])
                    err_o <= 1'b1;
                word_acc[rch][beat_cnt[rch] * AXI_DW +: AXI_DW] <= m_rdata;
                r_total[rch] <= r_total[rch] - BEAT_BYTES;
                if (word_done) begin
                    beat_cnt[rch] <= 3'd0;
                    dv[rch] <= 1'b1;
                    if (BEATS_PER_WORD == 1)
                        dd[rch*256 +: 256] <= m_rdata;
                    else
                        dd[rch*256 +: 256] <= {m_rdata, word_acc[rch][255-AXI_DW:0]};
                    dl[rch] <= (r_total[rch] == BEAT_BYTES);
                    ddst[rch*4 +: 4] <= dst[rch];
                    if (r_total[rch] == BEAT_BYTES)
                        active[rch] <= 1'b0;
                end else begin
                    beat_cnt[rch] <= beat_cnt[rch] + 1'b1;
                end
            end
        end
    end

endmodule
