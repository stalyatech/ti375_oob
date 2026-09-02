// =============================================================================
// snpu_acc.v
//
// Two bank accumulator. The array side adds the partial sums of every pass
// into bank wr_bank at pixel index p_i; the first pass of a tile writes
// instead of adding. When the array signals tile_end_i (delayed through the
// array like the data) the bank is marked full and the array side moves to
// the other bank. The epilogue side reads a full bank at ep_addr_i and
// releases it with ep_release_i.
//
// Each bank is a simple dual port RAM: one write port for the read-modify-
// write result, one read port shared by the array (read side of the RMW)
// and the epilogue, whichever owns the bank.
//
// The RMW pipeline reads one cycle after stage 0, adds in stage 1 and
// writes the registered sum in stage 2, so a pixel index may only repeat
// after at least three cycles (tiles have at least four pixels).
// =============================================================================
`timescale 1ns / 1ps

module snpu_acc #(
    parameter N_OC  = 64,
    parameter P_MAX = 1024,
    parameter P_W   = 10
)(
    input  wire                 clk,
    input  wire                 rst,
    // array side
    input  wire [N_OC*24-1:0]   psum_i,
    input  wire                 v_i,
    input  wire                 first_i,
    input  wire                 tile_end_i,
    input  wire [P_W-1:0]       p_i,
    output wire                 wr_bank_free_o,
    output wire                 tile_done_o,   // pulse: a tile end reached the bank
    // epilogue side
    output wire                 rd_bank_full_o,
    input  wire [P_W-1:0]       ep_addr_i,
    input  wire                 ep_re_i,       // epilogue read enable, holds the data while it stalls
    output wire [N_OC*32-1:0]   ep_data_o,
    input  wire                 ep_release_i
);

    localparam DW = N_OC * 32;

    reg wr_bank, rd_bank;
    reg [1:0] full;

    // Bank RAMs.
    reg [DW-1:0] mem0 [0:P_MAX-1];
    reg [DW-1:0] mem1 [0:P_MAX-1];

    // Stage 0: register the incoming psum and issue the read.
    reg              s0_v, s0_first, s0_end;
    reg [P_W-1:0]    s0_p;
    reg [N_OC*24-1:0] s0_psum;
    reg              s0_bank;

    // Stage 1: RAM data available, add.
    reg              s1_v, s1_first, s1_end;
    reg [P_W-1:0]    s1_p;
    reg [N_OC*24-1:0] s1_psum;
    reg              s1_bank;
    reg [DW-1:0]     rd0, rd1;

    // Stage 2: registered sum and fresh value, write. The first pass
    // selection happens here so the flag only drives the write mux.
    reg              s2_v, s2_endf, s2_first;
    reg [P_W-1:0]    s2_p;
    reg              s2_bank;
    reg [DW-1:0]     s2_sum;
    reg [DW-1:0]     s2_fresh;
    wire [DW-1:0]    s2_wdata = s2_first ? s2_fresh : s2_sum;

    // Read port ownership. The array owns its write bank only once that
    // bank is no longer full: after a tile end the write bank may switch to
    // a bank the epilogue is still draining, and the epilogue keeps the
    // read port until it releases the bank. The array side reads with the
    // stage 0 pixel index so the RAM data arrives together with the psum in
    // stage 1.
    wire arr0 = (wr_bank == 1'b0) && !full[0];
    wire arr1 = (wr_bank == 1'b1) && !full[1];
    wire [P_W-1:0] ra0 = arr0 ? s0_p : ep_addr_i;
    wire [P_W-1:0] ra1 = arr1 ? s0_p : ep_addr_i;

    // Write data pieces: the running sum and the sign extended fresh psum.
    reg [DW-1:0] sum;
    reg [DW-1:0] fresh;
    reg [DW-1:0] rdsel;
    integer j;
    always @(*) begin
        rdsel = s1_bank ? rd1 : rd0;
        for (j = 0; j < N_OC; j = j + 1) begin
            fresh[j*32 +: 32] = {{8{s1_psum[j*24+23]}}, s1_psum[j*24 +: 24]};
            sum[j*32 +: 32] = rdsel[j*32 +: 32] + {{8{s1_psum[j*24+23]}}, s1_psum[j*24 +: 24]};
        end
    end

    wire we0 = s2_v && (s2_bank == 1'b0);
    wire we1 = s2_v && (s2_bank == 1'b1);

    // The read output of a bank owned by the epilogue only updates when
    // the epilogue advances, so stalls do not lose the word in flight.
    wire re0 = arr0 || ep_re_i;
    wire re1 = arr1 || ep_re_i;

    always @(posedge clk) begin
        if (we0) mem0[s2_p] <= s2_wdata;
        if (re0) rd0 <= mem0[ra0];
        if (we1) mem1[s2_p] <= s2_wdata;
        if (re1) rd1 <= mem1[ra1];
    end

    always @(posedge clk) begin
        if (rst) begin
            s0_v <= 1'b0; s0_first <= 1'b0; s0_end <= 1'b0; s0_p <= {P_W{1'b0}}; s0_bank <= 1'b0;
            s1_v <= 1'b0; s1_first <= 1'b0; s1_end <= 1'b0; s1_p <= {P_W{1'b0}}; s1_bank <= 1'b0;
            s2_v <= 1'b0; s2_endf <= 1'b0; s2_first <= 1'b0; s2_p <= {P_W{1'b0}}; s2_bank <= 1'b0;
        end else begin
            s0_v <= v_i; s0_first <= first_i; s0_end <= tile_end_i; s0_p <= p_i; s0_bank <= wr_bank;
            s1_v <= s0_v; s1_first <= s0_first; s1_end <= s0_end; s1_p <= s0_p; s1_bank <= s0_bank;
            s2_v <= s1_v; s2_endf <= s1_end; s2_first <= s1_first; s2_p <= s1_p; s2_bank <= s1_bank;
        end
    end

    // The wide data registers are plain pipeline stages without a reset;
    // their contents are qualified by the valid flags above.
    always @(posedge clk) begin
        s0_psum <= psum_i;
        s1_psum <= s0_psum;
        s2_sum <= sum;
        s2_fresh <= fresh;
    end

    // Bank bookkeeping. The tile end is honoured once its write landed.
    reg s3_end;
    always @(posedge clk) begin
        if (rst) begin
            wr_bank <= 1'b0;
            rd_bank <= 1'b0;
            full <= 2'b00;
            s3_end <= 1'b0;
        end else begin
            s3_end <= s2_v && s2_endf;
            if (s3_end) begin
                full[wr_bank] <= 1'b1;
                wr_bank <= ~wr_bank;
            end
            if (ep_release_i) begin
                full[rd_bank] <= 1'b0;
                rd_bank <= ~rd_bank;
            end
        end
    end

    assign wr_bank_free_o = ~full[wr_bank] && !s0_end && !s1_end && !s2_endf && !s3_end;
    assign tile_done_o = s3_end;
    assign rd_bank_full_o = full[rd_bank];
    assign ep_data_o = rd_bank ? rd1 : rd0;

endmodule
