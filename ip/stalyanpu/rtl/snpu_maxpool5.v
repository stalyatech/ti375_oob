// =============================================================================
// snpu_maxpool5.v
//
// 5x5 stride 1 pad 2 max pool on NC32HW words (SPPF). Input words arrive
// plane after plane in raster order. Five rows are kept in a line buffer;
// once input row r is complete, output row r-2 is produced: for every
// column the five rows are read (five cycles), the column maximum is
// pushed into a horizontal window of five and the window maximum leaves
// with a delay of two columns. Rows and columns outside the image count as
// -128 so they never win.
//
// The line buffer is one RAM of 8*MAX_W words addressed by {slot, column};
// the slot of a row is tracked with small modulo 5 counters so the RAM
// address is a plain concatenation. The RAM is read every cycle; the read
// data is consumed in the cycle after the read was issued.
//
// Output words carry the plane and the pixel index (row * w + col).
// =============================================================================
`timescale 1ns / 1ps

module snpu_maxpool5 #(
    parameter MAX_W = 128,
    parameter W_AW  = 7
)(
    input  wire         clk,
    input  wire         rst,
    input  wire [15:0]  cfg_h_i,
    input  wire [15:0]  cfg_w_i,
    input  wire [7:0]   cfg_planes_i,
    input  wire         start_i,
    output wire         busy_o,
    input  wire         in_valid_i,
    input  wire [255:0] in_data_i,
    output wire         in_ready_o,
    output reg          out_valid_o,
    output reg  [255:0] out_data_o,
    output reg  [7:0]   out_plane_o,
    output reg  [15:0]  out_px_o,
    input  wire         out_ready_i
);

    localparam S_IDLE = 3'd0, S_IN = 3'd1, S_OUT = 3'd2, S_NEXT = 3'd3;
    reg [2:0] state;
    reg [7:0]  plane;
    reg [15:0] in_row, in_col;      // row being received
    reg [15:0] out_row, out_col;    // row being produced
    reg [2:0]  in_slot, out_slot;   // line buffer slots of in_row and out_row
    reg [2:0]  tap;                 // 0..4 row reads of one column
    reg [15:0] pending_rows;        // rows still to be produced for this plane

    function [2:0] mod5;
        input [3:0] v;
        begin
            if (v >= 4'd10) mod5 = v - 4'd10;
            else if (v >= 4'd5) mod5 = v - 4'd5;
            else mod5 = v[2:0];
        end
    endfunction

    assign in_ready_o = (state == S_IN);

    // Column maximum accumulation and horizontal window.
    reg [255:0] colmax;
    reg [255:0] win0, win1, win2, win3, win4;
    reg [255:0] rd_word;
    reg         rd_pad;
    reg         rd_valid;
    reg [2:0]   rd_tap;
    reg [15:0]  rd_col;
    wire [255:0] rd_data = rd_pad ? {32{8'h80}} : rd_word;

    function [255:0] bytemax;
        input [255:0] a;
        input [255:0] b;
        integer k;
        begin
            for (k = 0; k < 32; k = k + 1)
                bytemax[k*8 +: 8] = ($signed(a[k*8 +: 8]) > $signed(b[k*8 +: 8])) ? a[k*8 +: 8] : b[k*8 +: 8];
        end
    endfunction

    // Row of tap t for output row out_row: out_row - 2 + t.
    wire signed [17:0] tap_row = $signed({2'b0, out_row}) - 18'sd2 + $signed({15'b0, tap});
    wire tap_ok = (tap_row >= 0) && (tap_row < $signed({2'b0, cfg_h_i}));
    wire [2:0] tap_slot = mod5({1'b0, out_slot} + 4'd3 + {1'b0, tap});

    // Line buffer.
    reg [255:0] lines [0:8*MAX_W-1];
    wire [W_AW+2:0] wr_addr = {in_slot, in_col[W_AW-1:0]};
    wire [W_AW+2:0] rd_addr = {tap_slot, out_col[W_AW-1:0]};
    wire wr_en = (state == S_IN) && in_valid_i;
    always @(posedge clk) begin
        if (wr_en)
            lines[wr_addr] <= in_data_i;
        rd_word <= lines[rd_addr];
    end

    wire out_free = !out_valid_o || out_ready_i;
    reg [255:0] pipe_out;
    reg pipe_valid;
    reg [15:0] pipe_col;
    reg [15:0] emit_col;
    reg [15:0] cols_done;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; plane <= 8'd0; in_row <= 16'd0; in_col <= 16'd0; out_row <= 16'd0; out_col <= 16'd0;
            in_slot <= 3'd0; out_slot <= 3'd0;
            tap <= 3'd0; pending_rows <= 16'd0; out_valid_o <= 1'b0; out_data_o <= 256'd0; out_plane_o <= 8'd0;
            out_px_o <= 16'd0; rd_valid <= 1'b0; rd_pad <= 1'b0; rd_tap <= 3'd0; rd_col <= 16'd0; colmax <= 256'd0;
            win0 <= 256'd0; win1 <= 256'd0; win2 <= 256'd0; win3 <= 256'd0; win4 <= 256'd0;
            pipe_valid <= 1'b0; pipe_out <= 256'd0; pipe_col <= 16'd0; emit_col <= 16'd0; cols_done <= 16'd0;
        end else begin
            if (out_valid_o && out_ready_i)
                out_valid_o <= 1'b0;
            rd_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        plane <= 8'd0; in_row <= 16'd0; in_col <= 16'd0; out_row <= 16'd0;
                        in_slot <= 3'd0; out_slot <= 3'd0;
                        state <= S_IN;
                    end
                end
                S_IN: begin
                    // Receive one input row; the word is written by the
                    // line buffer block above.
                    if (in_valid_i) begin
                        if (in_col == cfg_w_i - 1) begin
                            in_col <= 16'd0;
                            in_row <= in_row + 1'b1;
                            in_slot <= mod5({1'b0, in_slot} + 4'd1);
                            // Rows 0 and 1 produce nothing yet.
                            if (in_row >= 16'd2) begin
                                out_row <= in_row - 16'd2;
                                out_slot <= mod5({1'b0, in_slot} + 4'd3);
                                state <= S_OUT;
                                out_col <= 16'd0; tap <= 3'd0; cols_done <= 16'd0; emit_col <= 16'd0;
                                win0 <= {32{8'h80}}; win1 <= {32{8'h80}}; win2 <= {32{8'h80}}; win3 <= {32{8'h80}}; win4 <= {32{8'h80}};
                            end else if (in_row + 1 == cfg_h_i) begin
                                // Tiny image: fewer than three rows, produce all rows now.
                                out_row <= 16'd0;
                                out_slot <= 3'd0;
                                state <= S_OUT;
                                out_col <= 16'd0; tap <= 3'd0; cols_done <= 16'd0; emit_col <= 16'd0;
                                win0 <= {32{8'h80}}; win1 <= {32{8'h80}}; win2 <= {32{8'h80}}; win3 <= {32{8'h80}}; win4 <= {32{8'h80}};
                            end
                        end else begin
                            in_col <= in_col + 1'b1;
                        end
                    end
                end
                S_OUT: begin
                    // Produce output row out_row: five row reads per column,
                    // then the horizontal window. Stalls when the output
                    // register is occupied.
                    if (out_free && !pipe_valid) begin
                        if (out_col < cfg_w_i) begin
                            rd_pad <= !tap_ok;
                            rd_valid <= 1'b1;
                            rd_tap <= tap;
                            rd_col <= out_col;
                            if (tap == 3'd4) begin
                                tap <= 3'd0;
                                out_col <= out_col + 1'b1;
                            end else begin
                                tap <= tap + 1'b1;
                            end
                        end
                    end
                    // Column maximum from the read stream.
                    if (rd_valid) begin
                        if (rd_tap == 3'd0)
                            colmax <= rd_data;
                        else
                            colmax <= bytemax(colmax, rd_data);
                        if (rd_tap == 3'd4) begin
                            // Shift the horizontal window: newest column enters.
                            win0 <= win1; win1 <= win2; win2 <= win3; win3 <= win4;
                            win4 <= bytemax(colmax, rd_data);
                            pipe_valid <= 1'b1;
                            pipe_col <= rd_col;
                        end
                    end
                    // Every completed column (and two virtual columns past the
                    // edge) emits the word two columns behind.
                    if (pipe_valid && out_free) begin
                        pipe_valid <= 1'b0;
                        if (pipe_col >= 16'd2) begin
                            out_valid_o <= 1'b1;
                            out_data_o <= bytemax(bytemax(bytemax(win0, win1), bytemax(win2, win3)), win4);
                            out_plane_o <= plane;
                            out_px_o <= out_row * cfg_w_i + (pipe_col - 16'd2);
                            cols_done <= cols_done + 1'b1;
                        end
                    end
                    // Flush the two trailing columns with -128 padding.
                    if (out_col == cfg_w_i && !rd_valid && !pipe_valid && out_free) begin
                        if (emit_col < 16'd2) begin
                            win0 <= win1; win1 <= win2; win2 <= win3; win3 <= win4; win4 <= {32{8'h80}};
                            out_valid_o <= 1'b1;
                            out_data_o <= bytemax(bytemax(bytemax(win1, win2), bytemax(win3, win4)), {32{8'h80}});
                            out_plane_o <= plane;
                            out_px_o <= out_row * cfg_w_i + (cfg_w_i - 16'd2) + emit_col;
                            emit_col <= emit_col + 1'b1;
                        end else begin
                            state <= S_NEXT;
                        end
                    end
                end
                S_NEXT: begin
                    if (out_row + 1 < cfg_h_i && (in_row == cfg_h_i) && out_row + 1 >= in_row - 2) begin
                        // Input finished: keep producing the remaining rows.
                        out_row <= out_row + 1'b1;
                        out_slot <= mod5({1'b0, out_slot} + 4'd1);
                        out_col <= 16'd0; tap <= 3'd0; cols_done <= 16'd0; emit_col <= 16'd0;
                        win0 <= {32{8'h80}}; win1 <= {32{8'h80}}; win2 <= {32{8'h80}}; win3 <= {32{8'h80}}; win4 <= {32{8'h80}};
                        state <= S_OUT;
                    end else if (out_row + 1 == cfg_h_i) begin
                        // Plane complete.
                        if (plane + 1 == cfg_planes_i) begin
                            state <= S_IDLE;
                        end else begin
                            plane <= plane + 1'b1;
                            in_row <= 16'd0; in_col <= 16'd0; out_row <= 16'd0;
                            in_slot <= 3'd0; out_slot <= 3'd0;
                            state <= S_IN;
                        end
                    end else begin
                        state <= S_IN;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy_o = (state != S_IDLE) || out_valid_o;

endmodule
