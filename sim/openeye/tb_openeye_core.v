// =============================================================================
// tb_openeye_core.v
//
// File driven functional test of the OpenEye DNN core as integrated in
// ti375_oob_top: DUT is open_eye_mt_v1_0 (which includes the cfg_reg AXI4-Lite
// slave) together with the openeye_irq done latch, all on a single 100 MHz
// clock, matching the top level where core and both stream ports run on
// io_dnnClk.
//
// The stimulus is the 64-bit dma_i word stream produced offline by the OpenEye
// Python toolchain (see gen_stimulus.py), the golden file holds the expected
// dma_o beats in output order. The stream master honors dma_i_tready, which is
// the contract of the gDMA_dnn stream channel and stricter than the upstream
// cocotb bench.
//
// Plusargs:
//   +STIM=<file>  stimulus hex file (default sim/openeye/stim/dma_stim.hex)
//   +GOLD=<file>  golden hex file  (default sim/openeye/stim/dma_golden.hex)
//   +BACKPRESSURE=1 enables pseudo random stalls on dma_o_tready
//   +DUMP         write an fst waveform
//
// Run: sim/openeye/run_core.sh
// =============================================================================
`timescale 1ns / 1ps

module tb_openeye_core;

    localparam MAX_WORDS = 1 << 20;

    reg clk = 1'b0;
    always #5.0 clk = ~clk;

    reg rstn = 1'b0;

    // dma_i stream master
    reg  [63:0] dma_i_tdata  = 64'h0;
    reg  [7:0]  dma_i_tstrb  = 8'hFF;
    reg         dma_i_tvalid = 1'b0;
    reg         dma_i_tlast  = 1'b0;
    wire        dma_i_tready;

    // dma_o stream slave
    wire [63:0] dma_o_tdata;
    wire [7:0]  dma_o_tstrb;
    wire        dma_o_tvalid;
    wire        dma_o_tlast;
    reg         dma_o_tready = 1'b0;

    // cfg_reg AXI4-Lite is tied off. The register block is functionally inert
    // in the datapath (configuration streams in over dma_i) and its bus
    // behaviour is covered by tb_openeye_glue.
    open_eye_mt_v1_0 u_dut (
        .clk             ( clk ),
        .rstn            ( rstn ),
        .cfg_reg_aclk    ( clk ),
        .cfg_reg_aresetn ( rstn ),
        .cfg_reg_awaddr  ( 6'h0 ),
        .cfg_reg_awprot  ( 3'b000 ),
        .cfg_reg_awvalid ( 1'b0 ),
        .cfg_reg_awready (  ),
        .cfg_reg_wdata   ( 32'h0 ),
        .cfg_reg_wstrb   ( 4'h0 ),
        .cfg_reg_wvalid  ( 1'b0 ),
        .cfg_reg_wready  (  ),
        .cfg_reg_bresp   (  ),
        .cfg_reg_bvalid  (  ),
        .cfg_reg_bready  ( 1'b1 ),
        .cfg_reg_araddr  ( 6'h0 ),
        .cfg_reg_arprot  ( 3'b000 ),
        .cfg_reg_arvalid ( 1'b0 ),
        .cfg_reg_arready (  ),
        .cfg_reg_rdata   (  ),
        .cfg_reg_rresp   (  ),
        .cfg_reg_rvalid  (  ),
        .cfg_reg_rready  ( 1'b1 ),
        .dma_i_aclk      ( clk ),
        .dma_i_aresetn   ( rstn ),
        .dma_i_tready    ( dma_i_tready ),
        .dma_i_tdata     ( dma_i_tdata ),
        .dma_i_tstrb     ( dma_i_tstrb ),
        .dma_i_tlast     ( dma_i_tlast ),
        .dma_i_tvalid    ( dma_i_tvalid ),
        .dma_o_aclk      ( clk ),
        .dma_o_aresetn   ( rstn ),
        .dma_o_tvalid    ( dma_o_tvalid ),
        .dma_o_tdata     ( dma_o_tdata ),
        .dma_o_tstrb     ( dma_o_tstrb ),
        .dma_o_tlast     ( dma_o_tlast ),
        .dma_o_tready    ( dma_o_tready )
    );

    reg  irq_clear = 1'b0;
    wire irq;

    openeye_irq u_irq (
        .clk          ( clk ),
        .rst_n        ( rstn ),
        .dma_o_tvalid ( dma_o_tvalid ),
        .dma_o_tready ( dma_o_tready ),
        .dma_o_tlast  ( dma_o_tlast ),
        .irq_clear    ( irq_clear ),
        .irq          ( irq )
    );

    // ------------------------------------------------------------------
    // Stimulus and golden data
    // ------------------------------------------------------------------
    reg [63:0] stim [0:MAX_WORDS-1];
    reg [63:0] gold [0:MAX_WORDS-1];
    integer stim_count = 0;
    integer gold_count = 0;

    reg [8*256-1:0] stim_file = "sim/openeye/stim/dma_stim.hex";
    reg [8*256-1:0] gold_file = "sim/openeye/stim/dma_golden.hex";

    integer i;
    integer plusarg_hit;

    task load_files;
        begin
            plusarg_hit = $value$plusargs("STIM=%s", stim_file);
            plusarg_hit = $value$plusargs("GOLD=%s", gold_file);
            for (i = 0; i < MAX_WORDS; i = i + 1) begin
                stim[i] = 64'hx;
                gold[i] = 64'hx;
            end
            $readmemh(stim_file, stim);
            $readmemh(gold_file, gold);
            stim_count = 0;
            while (stim_count < MAX_WORDS && stim[stim_count] !== 64'hx)
                stim_count = stim_count + 1;
            gold_count = 0;
            while (gold_count < MAX_WORDS && gold[gold_count] !== 64'hx)
                gold_count = gold_count + 1;
            if (stim_count == 0 || gold_count == 0) begin
                $display("tb_openeye_core: empty stimulus or golden file");
                $fatal(1);
            end
            $display("tb_openeye_core: %0d stimulus words, %0d golden beats",
                     stim_count, gold_count);
        end
    endtask

    // ------------------------------------------------------------------
    // Result collection and checking
    // ------------------------------------------------------------------
    integer errors = 0;
    integer beat_idx = 0;
    reg     seen_tlast = 1'b0;
    reg     collecting = 1'b0;
    reg     use_backpressure = 1'b0;
    reg [15:0] lfsr = 16'hACE1;

    // The ready decision for the next cycle comes from an LFSR when
    // backpressure mode is on, otherwise ready stays high while collecting.
    always @(posedge clk) begin
        if (!rstn) begin
            dma_o_tready <= 1'b0;
            lfsr         <= 16'hACE1;
        end else if (collecting) begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            dma_o_tready <= use_backpressure ? (lfsr[2] | lfsr[7]) : 1'b1;
        end else begin
            dma_o_tready <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rstn && dma_o_tvalid && dma_o_tready) begin
            if (beat_idx >= gold_count) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("FAIL @%0t: extra output beat %0d data %h",
                             $time, beat_idx, dma_o_tdata);
            end else if (dma_o_tdata !== gold[beat_idx]) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("FAIL @%0t: beat %0d expected %h got %h",
                             $time, beat_idx, gold[beat_idx], dma_o_tdata);
            end
            if (dma_o_tlast) begin
                seen_tlast = 1'b1;
                if (beat_idx != gold_count - 1) begin
                    errors = errors + 1;
                    $display("FAIL @%0t: tlast on beat %0d, expected on %0d",
                             $time, beat_idx, gold_count - 1);
                end
            end
            beat_idx = beat_idx + 1;
        end
    end

    // The interrupt must stay low until the final output beat completes.
    always @(posedge clk) begin
        if (rstn && !seen_tlast && irq) begin
            errors = errors + 1;
            $display("FAIL @%0t: irq high before final beat", $time);
        end
    end

    // ------------------------------------------------------------------
    // Stream master: send every stimulus word, honoring tready.
    // ------------------------------------------------------------------
    integer si;

    task send_stream;
        begin
            @(posedge clk);
            for (si = 0; si < stim_count; si = si + 1) begin
                dma_i_tdata  <= stim[si];
                dma_i_tvalid <= 1'b1;
                dma_i_tlast  <= (si == stim_count - 1);
                @(posedge clk);
                while (dma_i_tready !== 1'b1) @(posedge clk);
            end
            dma_i_tvalid <= 1'b0;
            dma_i_tlast  <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    integer wait_cycles;

    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_openeye_core.fst");
            $dumpvars(0, tb_openeye_core);
        end
        use_backpressure = $test$plusargs("BACKPRESSURE");

        load_files;

        rstn = 1'b0;
        repeat (20) @(posedge clk);
        rstn = 1'b1;
        repeat (10) @(posedge clk);

        collecting = 1'b1;
        send_stream;
        $display("tb_openeye_core: stream sent (%0d words) at %0t", stim_count, $time);

        // Wait for the full set of output beats with a generous limit.
        wait_cycles = 0;
        while (beat_idx < gold_count && wait_cycles < 2_000_000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (beat_idx < gold_count) begin
            errors = errors + 1;
            $display("FAIL: only %0d of %0d output beats received",
                     beat_idx, gold_count);
        end

        // No stray beats after the expected end.
        repeat (2000) @(posedge clk);

        if (!seen_tlast) begin
            errors = errors + 1;
            $display("FAIL: no tlast observed on dma_o");
        end

        // Done interrupt is set, sticky, and clears on request.
        if (irq !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: irq not set after completion");
        end
        repeat (100) @(posedge clk);
        if (irq !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: irq not sticky");
        end
        @(posedge clk);
        irq_clear <= 1'b1;
        @(posedge clk);
        irq_clear <= 1'b0;
        @(posedge clk);
        if (irq !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL: irq did not clear");
        end

        if (errors == 0) begin
            $display("tb_openeye_core: PASS (%0d beats checked)", beat_idx);
            $finish;
        end else begin
            $display("tb_openeye_core: %0d error(s)", errors);
            $fatal(1);
        end
    end

    // Watchdog on absolute simulated time.
    initial begin
        #100_000_000;
        $display("tb_openeye_core: watchdog timeout");
        $fatal(1);
    end

endmodule
