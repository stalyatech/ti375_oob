// Auto-generated from .\regmap.yaml
//
// DMA Storage Module - Receives and unpacks layer configuration parameters
//
// This module receives packed 64-bit DMA transmissions and extracts individual
// configuration parameters using bit slicing. Each layer requires multiple DMA
// transmissions to configure all parameters.
//
// Operation:
//   1. CPU/DMA controller writes to this module with write_en=1
//   2. write_addr selects which transmission (0 to TRANSMISSIONS-1)
//   3. dma_data_i contains the packed 64-bit word
//   4. Parameters are extracted and stored in output registers
//   5. Other hardware modules read these registers for layer execution

`include "regmap_params.vh"

module dma_storage (
    input  wire                  clk_i,
    input  wire                  rst_ni,           // Active-low reset
    input  wire                  write_en,         // Write enable from DMA
    input  wire [$clog2(TRANSMISSIONS)-1:0] write_addr,  // Transmission ID
    input  wire [DMA_BITWIDTH-1:0] dma_data_i,  // Packed 64-bit data
    output reg [7:0] wght_cycles_reg,
    output reg [2:0] stride_x_reg,
    output reg [2:0] stride_y_reg,
    output reg [0:0] skipIact_reg,
    output reg [0:0] skipWght_reg,
    output reg [0:0] skipPsum_reg,
    output reg [3:0] psum_q,
    output reg [3:0] kernel_per_pe_cluster_reg,
    output reg [5:0] kernel_size_x,
    output reg [3:0] kernel_size_y,
    output reg [7:0] x_lines_reg,
    output reg [7:0] needed_wght_cycles,
    output reg [17:0] needed_cycles,
    output reg [7:0] iact_converter_buffer_addr_max_cycles,
    output reg [7:0] iact_channels_per_pe,
    output reg [11:0] fc_size_reg,
    output reg [11:0] iact_size_x,
    output reg [7:0] iact_size_y,
    output reg [11:0] psum_size_x,
    output reg [7:0] psum_size_y,
    output reg [10:0] iact_needed_cycles,
    output reg [4:0] kernels_per_calc,
    output reg [3:0] y_lines_per_calc,
    output reg [7:0] output_cycles,
    output reg [0:0] store_in_psum,
    output reg [0:0] max_pooling,
    output reg [0:0] fully_connected_layer,
    output reg [0:0] choose_iact_buffer_output,
    output reg [0:0] choose_iact_buffer_input,
    output reg [3:0] iact_channels_per_pe_next_layer,
    output reg [7:0] needed_psum_storage_cycles_reg,
    output reg [7:0] iact_channel_max_cycles,
    output reg [4:0] input_activations,
    output reg [5:0] filters,
    output reg [1:0] needed_x_cls_reg,
    output reg [1:0] needed_y_cls_reg,
    output reg [3:0] needed_iact_cycles_reg,
    output reg [4:0] wght_addr_len_reg,
    output reg [3:0] iact_addr_len_reg,
    output reg [0:0] send_data_out,
    output reg [9:0] needed_iact_buffer_words,
    output reg [2:0] add_up_reg,
    output reg [7:0] iact_x_line_repetitions_reg,
    output reg [7:0] buffer_cycles_for_x_iact,
    output reg [3:0] start_param_array,
    output reg [7:0] limit_increase,
    output reg [7:0] initial_upper_limit,
    output reg [3:0] iteration_for_kernels,
    output reg [16:0] fsm_psum_limit,
    output reg [2:0] cluster_per_conv_cycle,
    output reg [7:0] iact_converter_max_cycles,
    output reg [11:0] iact_buffer_words_per_write,
    output reg [0:0] pooling_mode,
    output reg [19:0] test_reg
);

// Sequential logic: Store DMA data on write_en
always @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        // Reset all registers to 0
        wght_cycles_reg <= 8'd0;
        stride_x_reg <= 3'd0;
        stride_y_reg <= 3'd0;
        skipIact_reg <= 1'd0;
        skipWght_reg <= 1'd0;
        skipPsum_reg <= 1'd0;
        psum_q <= 4'd0;
        kernel_per_pe_cluster_reg <= 4'd0;
        kernel_size_x <= 6'd0;
        kernel_size_y <= 4'd0;
        x_lines_reg <= 8'd0;
        needed_wght_cycles <= 8'd0;
        needed_cycles <= 18'd0;
        iact_converter_buffer_addr_max_cycles <= 8'd0;
        iact_channels_per_pe <= 8'd0;
        fc_size_reg <= 12'd0;
        iact_size_x <= 12'd0;
        iact_size_y <= 8'd0;
        psum_size_x <= 12'd0;
        psum_size_y <= 8'd0;
        iact_needed_cycles <= 11'd0;
        kernels_per_calc <= 5'd0;
        y_lines_per_calc <= 4'd0;
        output_cycles <= 8'd0;
        store_in_psum <= 1'd0;
        max_pooling <= 1'd0;
        fully_connected_layer <= 1'd0;
        choose_iact_buffer_output <= 1'd0;
        choose_iact_buffer_input <= 1'd0;
        iact_channels_per_pe_next_layer <= 4'd0;
        needed_psum_storage_cycles_reg <= 8'd0;
        iact_channel_max_cycles <= 8'd0;
        input_activations <= 5'd0;
        filters <= 6'd0;
        needed_x_cls_reg <= 2'd0;
        needed_y_cls_reg <= 2'd0;
        needed_iact_cycles_reg <= 4'd0;
        wght_addr_len_reg <= 5'd0;
        iact_addr_len_reg <= 4'd0;
        send_data_out <= 1'd0;
        needed_iact_buffer_words <= 10'd0;
        add_up_reg <= 3'd0;
        iact_x_line_repetitions_reg <= 8'd0;
        buffer_cycles_for_x_iact <= 8'd0;
        start_param_array <= 4'd0;
        limit_increase <= 8'd0;
        initial_upper_limit <= 8'd0;
        iteration_for_kernels <= 4'd0;
        fsm_psum_limit <= 17'd0;
        cluster_per_conv_cycle <= 3'd0;
        iact_converter_max_cycles <= 8'd0;
        iact_buffer_words_per_write <= 12'd0;
        pooling_mode <= 1'd0;
        test_reg <= 20'd0;
    end else if (write_en) begin
        // Extract parameters based on transmission ID
        case (write_addr)
            0: begin  // Transmission 0
                wght_cycles_reg <= dma_data_i[PARAMETER_POS_0_0 + 7 : PARAMETER_POS_0_0];
                stride_x_reg <= dma_data_i[PARAMETER_POS_0_1 + 2 : PARAMETER_POS_0_1];
                stride_y_reg <= dma_data_i[PARAMETER_POS_0_2 + 2 : PARAMETER_POS_0_2];
                skipIact_reg <= dma_data_i[PARAMETER_POS_0_3 + 0 : PARAMETER_POS_0_3];
                skipWght_reg <= dma_data_i[PARAMETER_POS_0_4 + 0 : PARAMETER_POS_0_4];
                skipPsum_reg <= dma_data_i[PARAMETER_POS_0_5 + 0 : PARAMETER_POS_0_5];
                psum_q <= dma_data_i[PARAMETER_POS_0_6 + 3 : PARAMETER_POS_0_6];
                kernel_per_pe_cluster_reg <= dma_data_i[PARAMETER_POS_0_7 + 3 : PARAMETER_POS_0_7];
                kernel_size_x <= dma_data_i[PARAMETER_POS_0_8 + 5 : PARAMETER_POS_0_8];
                kernel_size_y <= dma_data_i[PARAMETER_POS_0_9 + 3 : PARAMETER_POS_0_9];
                x_lines_reg <= dma_data_i[PARAMETER_POS_0_10 + 7 : PARAMETER_POS_0_10];
                needed_wght_cycles <= dma_data_i[PARAMETER_POS_0_11 + 7 : PARAMETER_POS_0_11];
            end
            1: begin  // Transmission 1
                needed_cycles <= dma_data_i[PARAMETER_POS_1_0 + 17 : PARAMETER_POS_1_0];
                iact_converter_buffer_addr_max_cycles <= dma_data_i[PARAMETER_POS_1_1 + 7 : PARAMETER_POS_1_1];
                iact_channels_per_pe <= dma_data_i[PARAMETER_POS_1_2 + 7 : PARAMETER_POS_1_2];
                fc_size_reg <= dma_data_i[PARAMETER_POS_1_3 + 11 : PARAMETER_POS_1_3];
                iact_size_x <= dma_data_i[PARAMETER_POS_1_4 + 11 : PARAMETER_POS_1_4];
            end
            2: begin  // Transmission 2
                iact_size_y <= dma_data_i[PARAMETER_POS_2_0 + 7 : PARAMETER_POS_2_0];
                psum_size_x <= dma_data_i[PARAMETER_POS_2_1 + 11 : PARAMETER_POS_2_1];
                psum_size_y <= dma_data_i[PARAMETER_POS_2_2 + 7 : PARAMETER_POS_2_2];
                iact_needed_cycles <= dma_data_i[PARAMETER_POS_2_3 + 10 : PARAMETER_POS_2_3];
                kernels_per_calc <= dma_data_i[PARAMETER_POS_2_4 + 4 : PARAMETER_POS_2_4];
                y_lines_per_calc <= dma_data_i[PARAMETER_POS_2_5 + 3 : PARAMETER_POS_2_5];
                output_cycles <= dma_data_i[PARAMETER_POS_2_6 + 7 : PARAMETER_POS_2_6];
                store_in_psum <= dma_data_i[PARAMETER_POS_2_7 + 0 : PARAMETER_POS_2_7];
                max_pooling <= dma_data_i[PARAMETER_POS_2_8 + 0 : PARAMETER_POS_2_8];
                fully_connected_layer <= dma_data_i[PARAMETER_POS_2_9 + 0 : PARAMETER_POS_2_9];
                choose_iact_buffer_output <= dma_data_i[PARAMETER_POS_2_10 + 0 : PARAMETER_POS_2_10];
                choose_iact_buffer_input <= dma_data_i[PARAMETER_POS_2_11 + 0 : PARAMETER_POS_2_11];
            end
            3: begin  // Transmission 3
                iact_channels_per_pe_next_layer <= dma_data_i[PARAMETER_POS_3_0 + 3 : PARAMETER_POS_3_0];
                needed_psum_storage_cycles_reg <= dma_data_i[PARAMETER_POS_3_1 + 7 : PARAMETER_POS_3_1];
                iact_channel_max_cycles <= dma_data_i[PARAMETER_POS_3_2 + 7 : PARAMETER_POS_3_2];
                input_activations <= dma_data_i[PARAMETER_POS_3_3 + 4 : PARAMETER_POS_3_3];
                filters <= dma_data_i[PARAMETER_POS_3_4 + 5 : PARAMETER_POS_3_4];
                needed_x_cls_reg <= dma_data_i[PARAMETER_POS_3_5 + 1 : PARAMETER_POS_3_5];
                needed_y_cls_reg <= dma_data_i[PARAMETER_POS_3_6 + 1 : PARAMETER_POS_3_6];
                needed_iact_cycles_reg <= dma_data_i[PARAMETER_POS_3_7 + 3 : PARAMETER_POS_3_7];
                wght_addr_len_reg <= dma_data_i[PARAMETER_POS_3_8 + 4 : PARAMETER_POS_3_8];
                iact_addr_len_reg <= dma_data_i[PARAMETER_POS_3_9 + 3 : PARAMETER_POS_3_9];
                send_data_out <= dma_data_i[PARAMETER_POS_3_10 + 0 : PARAMETER_POS_3_10];
                needed_iact_buffer_words <= dma_data_i[PARAMETER_POS_3_11 + 9 : PARAMETER_POS_3_11];
                add_up_reg <= dma_data_i[PARAMETER_POS_3_12 + 2 : PARAMETER_POS_3_12];
            end
            4: begin  // Transmission 4
                iact_x_line_repetitions_reg <= dma_data_i[PARAMETER_POS_4_0 + 7 : PARAMETER_POS_4_0];
                buffer_cycles_for_x_iact <= dma_data_i[PARAMETER_POS_4_1 + 7 : PARAMETER_POS_4_1];
                start_param_array <= dma_data_i[PARAMETER_POS_4_2 + 3 : PARAMETER_POS_4_2];
                limit_increase <= dma_data_i[PARAMETER_POS_4_3 + 7 : PARAMETER_POS_4_3];
                initial_upper_limit <= dma_data_i[PARAMETER_POS_4_4 + 7 : PARAMETER_POS_4_4];
                iteration_for_kernels <= dma_data_i[PARAMETER_POS_4_5 + 3 : PARAMETER_POS_4_5];
                fsm_psum_limit <= dma_data_i[PARAMETER_POS_4_6 + 16 : PARAMETER_POS_4_6];
                cluster_per_conv_cycle <= dma_data_i[PARAMETER_POS_4_7 + 2 : PARAMETER_POS_4_7];
            end
            5: begin  // Transmission 5
                iact_converter_max_cycles <= dma_data_i[PARAMETER_POS_5_0 + 7 : PARAMETER_POS_5_0];
                iact_buffer_words_per_write <= dma_data_i[PARAMETER_POS_5_1 + 11 : PARAMETER_POS_5_1];
                pooling_mode <= dma_data_i[PARAMETER_POS_5_2 + 0 : PARAMETER_POS_5_2];
                test_reg <= dma_data_i[PARAMETER_POS_5_3 + 19 : PARAMETER_POS_5_3];
            end
        endcase
    end
end

endmodule
