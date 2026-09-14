// =============================================================================
// snpu_wr_dma.v
//
// AXI4 write master for 32 byte words with burst coalescing. Every input
// word carries its own byte address. Words that continue an open burst are
// appended to it; a burst closes when it reaches SLOT_WORDS words, when it
// would cross a 4 KB boundary, when the input pauses, or when a new burst
// needs its slot. NSLOT bursts can be open at the same time, which covers
// the epilogue order (the planes of one pixel follow each other, so the
// words of one plane arrive interleaved with the other planes).
//
// Closed bursts wait in a queue and go out one at a time as a single AXI
// transaction of SLOT_WORDS * 32 / (AXI_DW/8) beats at most, all strobes
// set. Write responses are counted so idle_o tells the sequencer when every
// word landed in memory. Word data sits in one small RAM indexed by slot
// and word; the data channel reads it through a two stage prefetch.
// =============================================================================
`timescale 1ns / 1ps

module snpu_wr_dma #(
    parameter AXI_DW = 128,
    parameter NSLOT = 8,
    parameter SLOT_WORDS = 128,
    parameter IDLE_CYCLES = 16
)(
    input  wire         clk,
    input  wire         rst,
    // word stream in
    input  wire         w_valid_i,
    input  wire [31:0]  w_addr_i,
    input  wire [255:0] w_data_i,
    output wire         w_ready_o,
    output wire         idle_o,
    output wire [7:0]   dbg_pending_o,
    // measurement counters: AW wait cycles, W wait cycles after the AW was
    // accepted, bursts finished, beats sent
    output reg  [31:0]  dbg_aw_wait_o,
    output reg  [31:0]  dbg_w_wait_o,
    output reg  [31:0]  dbg_bursts_o,
    output reg  [31:0]  dbg_beats_o,
    // AXI4 write channels
    output reg          m_awvalid,
    input  wire         m_awready,
    output reg  [31:0]  m_awaddr,
    output reg  [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire [3:0]   m_awid,
    output wire         m_wvalid,
    input  wire         m_wready,
    output wire [AXI_DW-1:0] m_wdata,
    output wire [AXI_DW/8-1:0] m_wstrb,
    output wire         m_wlast,
    input  wire         m_bvalid,
    output wire         m_bready,
    input  wire [1:0]   m_bresp,
    output reg          err_o
);

    localparam BEAT_BYTES = AXI_DW / 8;
    localparam BEATS = 32 / BEAT_BYTES;          // beats per word
    localparam SW = $clog2(NSLOT);
    localparam WW = $clog2(SLOT_WORDS);
    localparam S_FREE = 2'd0, S_OPEN = 2'd1, S_QUEUED = 2'd2;

    assign m_awsize  = (AXI_DW == 256) ? 3'd5 : (AXI_DW == 128) ? 3'd4 : 3'd3;
    assign m_awburst = 2'b01;
    assign m_awid    = 4'd0;
    assign m_wstrb   = {(AXI_DW/8){1'b1}};
    assign m_bready  = 1'b1;

    // ---- slots
    reg [1:0]   sstate [0:NSLOT-1];
    reg [31:0]  sbase  [0:NSLOT-1];
    reg [31:0]  snext  [0:NSLOT-1];   // address the next word of the burst must have
    reg [WW:0]  slen   [0:NSLOT-1];
    reg [255:0] mem [0:NSLOT*SLOT_WORDS-1];

    // Two entry input FIFO so w_ready_o comes straight from a register; the
    // slot match below works on the head entry.
    reg [1:0]   in_cnt;
    reg         in_wp, in_rp;
    reg [31:0]  in_addr [0:1];
    reg [255:0] in_data [0:1];
    wire        in_v = (in_cnt != 2'd0);
    wire [31:0] cur_addr = in_addr[in_rp];
    wire [255:0] cur_data = in_data[in_rp];
    assign w_ready_o = (in_cnt != 2'd2);
    wire in_push = w_valid_i && w_ready_o;

    // Match the head word against the open slots.
    reg        hit;
    reg [SW-1:0] hit_s, free_s, open_s;
    reg        has_free, has_open;
    integer k;
    always @(*) begin
        hit = 1'b0; hit_s = 0; has_free = 1'b0; free_s = 0; has_open = 1'b0; open_s = 0;
        for (k = NSLOT - 1; k >= 0; k = k - 1) begin
            if ((sstate[k] == S_OPEN) && (slen[k] < SLOT_WORDS) &&
                (snext[k] == cur_addr) && (cur_addr[11:0] != 12'd0)) begin
                hit = 1'b1; hit_s = k[SW-1:0];
            end
            if (sstate[k] == S_FREE) begin
                has_free = 1'b1; free_s = k[SW-1:0];
            end
            if (sstate[k] == S_OPEN) begin
                has_open = 1'b1; open_s = k[SW-1:0];
            end
        end
    end

    wire accept = in_v && (hit || has_free);
    wire [SW-1:0] acc_s = hit ? hit_s : free_s;
    wire [WW:0]   acc_len = hit ? slen[hit_s] : {(WW+1){1'b0}};

    reg        s_busy, aw_done;   // sender state, declared early for the idle rule

    // Idle timer: close open bursts when the input pauses and nothing is
    // waiting to go out. While the sender is busy the open bursts keep
    // collecting words; closing them on a short pause would turn back
    // pressure from the memory port into single word bursts.
    reg [5:0] idle_cnt;
    wire idle_close = (idle_cnt >= IDLE_CYCLES) && has_open && !in_v && !s_busy && (q_cnt == 0);
    // A word that fits no open burst and finds no free slot evicts an open
    // one, but only while nothing is in flight: with the sender busy a slot
    // frees soon anyway, and evicting would cut the interleaved plane
    // streams into single word bursts.
    wire evict_close = in_v && !hit && !has_free && has_open && !s_busy && (q_cnt == 0);
    // The burst that reaches its full length closes at once.
    wire full_close = accept && (acc_len + 1 == SLOT_WORDS);

    // ---- send queue of closed slots
    reg [SW-1:0] q_mem [0:NSLOT-1];
    reg [SW:0]   q_wp, q_rp, q_cnt;
    wire q_push = full_close || idle_close || evict_close;
    wire [SW-1:0] q_slot = full_close ? acc_s : open_s;

    // ---- sender
    reg [SW-1:0] s_slot;
    reg [WW:0]   s_n;          // words in the burst
    reg [WW:0]   f_idx;        // next word to fetch from the RAM
    reg [WW:0]   sent;         // words fully sent
    reg          pq_valid, wq_valid;
    reg [255:0]  pq, wq;
    reg [2:0]    beat;
    reg [7:0]    pending;

    wire consume   = wq_valid && m_wready;
    wire word_done = consume && (beat == BEATS - 1);
    wire pq_take   = pq_valid && (!wq_valid || word_done);
    wire do_fetch  = s_busy && (f_idx < s_n) && (!pq_valid || pq_take);
    wire burst_done = word_done && (sent + 1 == s_n);
    wire q_pop = !s_busy && (q_cnt != 0);
    reg  w_done;   // every beat of the burst went out, AW may still be pending
    wire finish = s_busy && (w_done || burst_done) && (aw_done || aw_done_now);

    assign m_wvalid = wq_valid;
    assign m_wdata  = wq[beat * AXI_DW +: AXI_DW];
    assign m_wlast  = (beat == BEATS - 1) && (sent + 1 == s_n);
    assign idle_o = !s_busy && (q_cnt == 0) && !has_open && (pending == 8'd0) && !in_v;
    assign dbg_pending_o = pending;

    wire aw_done_now = m_awvalid && m_awready;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NSLOT; i = i + 1) begin
                sstate[i] <= S_FREE; sbase[i] <= 32'd0; snext[i] <= 32'd0; slen[i] <= 0;
            end
            idle_cnt <= 6'd0;
            in_cnt <= 2'd0; in_wp <= 1'b0; in_rp <= 1'b0;
            q_wp <= 0; q_rp <= 0; q_cnt <= 0;
            s_busy <= 1'b0; aw_done <= 1'b0; w_done <= 1'b0; s_slot <= 0; s_n <= 0; f_idx <= 0; sent <= 0;
            pq_valid <= 1'b0; wq_valid <= 1'b0; beat <= 3'd0; pending <= 8'd0;
            m_awvalid <= 1'b0; m_awaddr <= 32'd0; m_awlen <= 8'd0; err_o <= 1'b0;
            dbg_aw_wait_o <= 32'd0; dbg_w_wait_o <= 32'd0; dbg_bursts_o <= 32'd0; dbg_beats_o <= 32'd0;
        end else begin
            if (m_awvalid && !m_awready) dbg_aw_wait_o <= dbg_aw_wait_o + 1'b1;
            if (aw_done && wq_valid && !m_wready) dbg_w_wait_o <= dbg_w_wait_o + 1'b1;
            if (finish) dbg_bursts_o <= dbg_bursts_o + 1'b1;
            if (consume) dbg_beats_o <= dbg_beats_o + 1'b1;
            // ---- input side
            if (in_push) begin
                in_addr[in_wp] <= w_addr_i;
                in_data[in_wp] <= w_data_i;
                in_wp <= ~in_wp;
            end
            if (accept)
                in_rp <= ~in_rp;
            in_cnt <= in_cnt + {1'b0, in_push} - {1'b0, accept};
            if (in_v)
                idle_cnt <= 6'd0;
            else if (idle_cnt < 6'd63)
                idle_cnt <= idle_cnt + 6'd1;
            if (accept) begin
                mem[{acc_s, acc_len[WW-1:0]}] <= cur_data;
                slen[acc_s] <= acc_len + 1;
                snext[acc_s] <= cur_addr + 32'd32;
                if (!hit) begin
                    sstate[acc_s] <= S_OPEN;
                    sbase[acc_s] <= cur_addr;
                end
            end
            if (q_push) begin
                sstate[q_slot] <= S_QUEUED;
                q_mem[q_wp[SW-1:0]] <= q_slot;
                q_wp <= q_wp + 1'b1;
            end
            // ---- sender
            if (q_pop) begin
                s_busy <= 1'b1;
                s_slot <= q_mem[q_rp[SW-1:0]];
                s_n <= slen[q_mem[q_rp[SW-1:0]]];
                q_rp <= q_rp + 1'b1;
                m_awaddr <= sbase[q_mem[q_rp[SW-1:0]]];
                m_awlen <= slen[q_mem[q_rp[SW-1:0]]] * BEATS - 1;
                m_awvalid <= 1'b1;
                aw_done <= 1'b0;
                f_idx <= 0; sent <= 0;
                pq_valid <= 1'b0; wq_valid <= 1'b0; beat <= 3'd0;
            end
            if (aw_done_now) begin
                m_awvalid <= 1'b0;
                aw_done <= 1'b1;
            end
            if (do_fetch) begin
                pq <= mem[{s_slot, f_idx[WW-1:0]}];
                pq_valid <= 1'b1;
                f_idx <= f_idx + 1'b1;
            end else if (pq_take) begin
                pq_valid <= 1'b0;
            end
            if (pq_take) begin
                wq <= pq;
                wq_valid <= 1'b1;
                beat <= 3'd0;
            end else if (word_done) begin
                wq_valid <= 1'b0;
            end else if (consume) begin
                beat <= beat + 1'b1;
            end
            if (word_done)
                sent <= sent + 1'b1;
            if (burst_done)
                w_done <= 1'b1;
            if (q_pop)
                w_done <= 1'b0;
            if (finish) begin
                s_busy <= 1'b0;
                sstate[s_slot] <= S_FREE;
                slen[s_slot] <= 0;
            end
            q_cnt <= q_cnt + {{SW{1'b0}}, q_push} - {{SW{1'b0}}, q_pop};
            // ---- responses
            if (m_bvalid && m_bresp[1])
                err_o <= 1'b1;
            pending <= pending + (finish ? 8'd1 : 8'd0) - (m_bvalid ? 8'd1 : 8'd0);
        end
    end

endmodule
