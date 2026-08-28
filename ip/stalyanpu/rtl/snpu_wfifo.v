// =============================================================================
// snpu_wfifo.v
//
// Weight FIFO and shadow fill sequencer. Weight words arrive in consumption
// order on the stream input. One pass needs N_CHAIN * WORDS_PER_CHAIN words;
// the sequencer moves them into the chain shadows one word per cycle and
// then reports shadow_ready_o. A latch pulse consumes the shadow; the next
// fill starts CHAIN_LEN + 1 cycles later, once the last block of the chain
// has latched, so a shadow is never overwritten early.
// =============================================================================
`timescale 1ns / 1ps

module snpu_wfifo #(
    parameter N_CHAIN     = 32,
    parameter CHAIN_LEN   = 32,
    parameter FILL_W      = 256,
    parameter FIFO_WORDS  = 1024,
    parameter FIFO_AW     = 10
)(
    input  wire              clk,
    input  wire              rst,
    // stream in
    input  wire              w_valid_i,
    input  wire [FILL_W-1:0] w_data_i,
    output wire              w_ready_o,
    // control
    input  wire              start_i,        // begin filling the first pass
    input  wire              latch_i,        // shadow consumed by the array
    output reg               shadow_ready_o,
    // fill port
    output reg               fill_we_o,
    output reg  [7:0]        fill_chain_o,
    output reg  [3:0]        fill_sel_o,
    output reg  [FILL_W-1:0] fill_data_o
);

    localparam WORDS_PER_CHAIN = (CHAIN_LEN * 16 + FILL_W - 1) / FILL_W;

    // FIFO.
    reg [FILL_W-1:0] mem [0:FIFO_WORDS-1];
    reg [FIFO_AW:0] wp, rp;
    wire empty = (wp == rp);
    wire fullf = (wp[FIFO_AW-1:0] == rp[FIFO_AW-1:0]) && (wp[FIFO_AW] != rp[FIFO_AW]);
    assign w_ready_o = !fullf;

    always @(posedge clk) begin
        if (w_valid_i && !fullf)
            mem[wp[FIFO_AW-1:0]] <= w_data_i;
    end

    // Sequencer.
    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_FILL = 2'd2, S_READY = 2'd3;
    reg [1:0] state;
    reg [7:0] chain;
    reg [3:0] sel;
    reg [7:0] hold;

    wire pop = (state == S_FILL) && !empty;

    always @(posedge clk) begin
        if (rst) begin
            wp <= 0;
            rp <= 0;
            state <= S_IDLE;
            chain <= 8'd0;
            sel <= 4'd0;
            hold <= 8'd0;
            shadow_ready_o <= 1'b0;
            fill_we_o <= 1'b0;
            fill_chain_o <= 8'd0;
            fill_sel_o <= 4'd0;
            fill_data_o <= {FILL_W{1'b0}};
        end else begin
            if (w_valid_i && !fullf)
                wp <= wp + 1'b1;
            fill_we_o <= pop;
            fill_chain_o <= chain;
            fill_sel_o <= sel;
            if (pop)
                fill_data_o <= mem[rp[FIFO_AW-1:0]];
            if (pop)
                rp <= rp + 1'b1;
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        state <= S_FILL;
                        chain <= 8'd0;
                        sel <= 4'd0;
                    end
                end
                S_FILL: begin
                    if (pop) begin
                        if (sel == WORDS_PER_CHAIN - 1) begin
                            sel <= 4'd0;
                            if (chain == N_CHAIN - 1) begin
                                chain <= 8'd0;
                                state <= S_READY;
                                shadow_ready_o <= 1'b1;
                            end else begin
                                chain <= chain + 1'b1;
                            end
                        end else begin
                            sel <= sel + 1'b1;
                        end
                    end
                end
                S_READY: begin
                    if (latch_i) begin
                        shadow_ready_o <= 1'b0;
                        hold <= CHAIN_LEN + 1;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (hold == 8'd1)
                        state <= S_FILL;
                    hold <= hold - 1'b1;
                end
            endcase
        end
    end

endmodule
