// =============================================================================
// tb_openeye_glue.v
//
// Directed testbench for the OpenEye control-plane glue used in ti375_oob_top:
//   1. apb3_2_axi4_lite (ADDR_WTH=6) driving open_eye_mt_v1_0_cfg_reg, both in
//      the peripheral clock domain, exactly as wired at the top level.
//   2. A standalone openeye_irq instance in the DNN clock domain, exercised
//      for corner cases the full-core testbench cannot hit deterministically.
//
// Checks:
//   - APB3 write then read back of all 16 cfg registers (walking ones plus an
//     address-unique pattern), pslverr stays low, back-to-back accesses work,
//     reads after reset return zero.
//   - openeye_irq: no set when tlast completes without tready, set wins over a
//     coincident clear, clear while idle keeps irq low, sticky behaviour.
//
// Run: sim/openeye/run_glue.sh (iverilog + vvp).
// =============================================================================
`timescale 1ns / 1ps

module tb_openeye_glue;

    // Two 100 MHz clocks with a deliberate phase offset. The peripheral and
    // DNN domains are asynchronous at the top level, so the offset shakes out
    // accidental same-edge assumptions between the two DUT groups.
    reg clk_peri = 1'b0;
    reg clk_dnn  = 1'b0;
    always #5.0 clk_peri = ~clk_peri;
    initial #3.3 forever #5.0 clk_dnn = ~clk_dnn;

    reg rstn = 1'b0;

    // ------------------------------------------------------------------
    // Group 1: APB3 bridge plus cfg_reg (peripheral clock domain)
    // ------------------------------------------------------------------
    reg  [5:0]  paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire        pready;
    wire [31:0] prdata;
    wire        pslverr;

    wire [5:0]  axi_awaddr;
    wire        axi_awvalid, axi_awready;
    wire [31:0] axi_wdata;
    wire        axi_wvalid, axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid, axi_bready;
    wire [5:0]  axi_araddr;
    wire        axi_arvalid, axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid, axi_rready;

    apb3_2_axi4_lite #(.ADDR_WTH(6)) u_bridge (
        .clk              ( clk_peri ),
        .rstn             ( rstn ),
        .s_apb3_paddr     ( paddr ),
        .s_apb3_psel      ( psel ),
        .s_apb3_penable   ( penable ),
        .s_apb3_pready    ( pready ),
        .s_apb3_pwrite    ( pwrite ),
        .s_apb3_pwdata    ( pwdata ),
        .s_apb3_prdata    ( prdata ),
        .s_apb3_pslverror ( pslverr ),
        .m_axi_awaddr     ( axi_awaddr ),
        .m_axi_awvalid    ( axi_awvalid ),
        .m_axi_awready    ( axi_awready ),
        .m_axi_wdata      ( axi_wdata ),
        .m_axi_wvalid     ( axi_wvalid ),
        .m_axi_wready     ( axi_wready ),
        .m_axi_bresp      ( axi_bresp ),
        .m_axi_bvalid     ( axi_bvalid ),
        .m_axi_bready     ( axi_bready ),
        .m_axi_araddr     ( axi_araddr ),
        .m_axi_arvalid    ( axi_arvalid ),
        .m_axi_arready    ( axi_arready ),
        .m_axi_rresp      ( axi_rresp ),
        .m_axi_rdata      ( axi_rdata ),
        .m_axi_rvalid     ( axi_rvalid ),
        .m_axi_rready     ( axi_rready )
    );

    open_eye_mt_v1_0_cfg_reg #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(6)
    ) u_cfg_reg (
        .S_AXI_ACLK    ( clk_peri ),
        .S_AXI_ARESETN ( rstn ),
        .S_AXI_AWADDR  ( axi_awaddr ),
        .S_AXI_AWPROT  ( 3'b000 ),
        .S_AXI_AWVALID ( axi_awvalid ),
        .S_AXI_AWREADY ( axi_awready ),
        .S_AXI_WDATA   ( axi_wdata ),
        .S_AXI_WSTRB   ( 4'hF ),
        .S_AXI_WVALID  ( axi_wvalid ),
        .S_AXI_WREADY  ( axi_wready ),
        .S_AXI_BRESP   ( axi_bresp ),
        .S_AXI_BVALID  ( axi_bvalid ),
        .S_AXI_BREADY  ( axi_bready ),
        .S_AXI_ARADDR  ( axi_araddr ),
        .S_AXI_ARPROT  ( 3'b000 ),
        .S_AXI_ARVALID ( axi_arvalid ),
        .S_AXI_ARREADY ( axi_arready ),
        .S_AXI_RDATA   ( axi_rdata ),
        .S_AXI_RRESP   ( axi_rresp ),
        .S_AXI_RVALID  ( axi_rvalid ),
        .S_AXI_RREADY  ( axi_rready )
    );

    // ------------------------------------------------------------------
    // Group 2: openeye_irq corner cases (DNN clock domain)
    // ------------------------------------------------------------------
    reg  irq_tvalid = 1'b0;
    reg  irq_tready = 1'b0;
    reg  irq_tlast  = 1'b0;
    reg  irq_clear  = 1'b0;
    wire irq;

    openeye_irq u_irq (
        .clk          ( clk_dnn ),
        .rst_n        ( rstn ),
        .dma_o_tvalid ( irq_tvalid ),
        .dma_o_tready ( irq_tready ),
        .dma_o_tlast  ( irq_tlast ),
        .irq_clear    ( irq_clear ),
        .irq          ( irq )
    );

    // ------------------------------------------------------------------
    // Group 3: full clear chain, mirroring the top level wiring. An APB
    // write of bit 0 to offset 0x3C is decoded into a one-cycle pulse in
    // the peripheral domain, crossed with pulse_sync into the DNN domain
    // and used to clear a second openeye_irq instance.
    // ------------------------------------------------------------------
    wire tb_clr_wr = psel & penable & pwrite & pready
                   & (paddr == 6'h3C) & pwdata[0];

    wire chain_clear;

    pulse_sync u_clr_sync (
        .src_clk   ( clk_peri ),
        .src_rst_n ( rstn ),
        .src_pulse ( tb_clr_wr ),
        .dst_clk   ( clk_dnn ),
        .dst_rst_n ( rstn ),
        .dst_pulse ( chain_clear )
    );

    reg  irq2_tvalid = 1'b0;
    reg  irq2_tready = 1'b0;
    reg  irq2_tlast  = 1'b0;
    wire irq2;

    openeye_irq u_irq2 (
        .clk          ( clk_dnn ),
        .rst_n        ( rstn ),
        .dma_o_tvalid ( irq2_tvalid ),
        .dma_o_tready ( irq2_tready ),
        .dma_o_tlast  ( irq2_tlast ),
        .irq_clear    ( chain_clear ),
        .irq          ( irq2 )
    );

    task irq2_set;
        begin
            @(posedge clk_dnn);
            irq2_tvalid <= 1'b1; irq2_tready <= 1'b1; irq2_tlast <= 1'b1;
            @(posedge clk_dnn);
            irq2_tvalid <= 1'b0; irq2_tready <= 1'b0; irq2_tlast <= 1'b0;
            @(posedge clk_dnn);
        end
    endtask

    // ------------------------------------------------------------------
    // Bookkeeping
    // ------------------------------------------------------------------
    integer errors = 0;

    task fail(input [8*64-1:0] msg);
        begin
            errors = errors + 1;
            $display("FAIL @%0t: %0s", $time, msg);
        end
    endtask

    // Always-on protocol monitor: the bridge must never report a slave error
    // in this testbench since every access targets a valid register.
    always @(posedge clk_peri) begin
        if (rstn && pslverr) fail("pslverr asserted");
    end

    // ------------------------------------------------------------------
    // APB3 master tasks (setup phase, then access phase held until pready)
    // ------------------------------------------------------------------
    task apb_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge clk_peri);
            psel    <= 1'b1;
            penable <= 1'b0;
            pwrite  <= 1'b1;
            paddr   <= addr;
            pwdata  <= data;
            @(posedge clk_peri);
            penable <= 1'b1;
            @(posedge clk_peri);
            while (pready !== 1'b1) @(posedge clk_peri);
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
        end
    endtask

    task apb_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge clk_peri);
            psel    <= 1'b1;
            penable <= 1'b0;
            pwrite  <= 1'b0;
            paddr   <= addr;
            @(posedge clk_peri);
            penable <= 1'b1;
            @(posedge clk_peri);
            while (pready !== 1'b1) @(posedge clk_peri);
            data     = prdata;
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    task check_read(input [5:0] addr, input [31:0] expected);
        reg [31:0] got;
        begin
            apb_read(addr, got);
            if (got !== expected) begin
                fail("cfg_reg readback mismatch");
                $display("  addr 0x%02h expected 0x%08h got 0x%08h", addr, expected, got);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    integer k;
    reg [31:0] rd;

    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_openeye_glue.fst");
            $dumpvars(0, tb_openeye_glue);
        end

        // Reset for a comfortable number of cycles in both domains.
        rstn = 1'b0;
        repeat (10) @(posedge clk_peri);
        rstn = 1'b1;
        repeat (4) @(posedge clk_peri);

        // 1. Reads after reset must return zero.
        for (k = 0; k < 16; k = k + 1)
            check_read(k[3:0] * 4, 32'h0);

        // 2. Walking ones across the 16 registers, then read all back. The
        //    readback happens after all writes so earlier registers must hold
        //    their values while later ones are written.
        for (k = 0; k < 16; k = k + 1)
            apb_write(k[3:0] * 4, 32'h1 << k);
        for (k = 0; k < 16; k = k + 1)
            check_read(k[3:0] * 4, 32'h1 << k);

        // 3. Address-unique pattern, back-to-back write then immediate read.
        for (k = 0; k < 16; k = k + 1) begin
            apb_write(k[3:0] * 4, 32'hA5000000 | (k * 32'h00010101));
            check_read(k[3:0] * 4, 32'hA5000000 | (k * 32'h00010101));
        end

        // 4. openeye_irq corner cases in the DNN domain.
        // 4a. tlast beat without tready must not set the interrupt.
        @(posedge clk_dnn);
        irq_tvalid <= 1'b1; irq_tlast <= 1'b1; irq_tready <= 1'b0;
        repeat (3) @(posedge clk_dnn);
        irq_tvalid <= 1'b0; irq_tlast <= 1'b0;
        @(posedge clk_dnn);
        if (irq !== 1'b0) fail("irq set without tready");

        // 4b. Clear pulse while irq is already low must keep it low.
        @(posedge clk_dnn);
        irq_clear <= 1'b1;
        @(posedge clk_dnn);
        irq_clear <= 1'b0;
        @(posedge clk_dnn);
        if (irq !== 1'b0) fail("irq glitched on idle clear");

        // 4c. Normal completion beat sets the interrupt on the next edge.
        @(posedge clk_dnn);
        irq_tvalid <= 1'b1; irq_tready <= 1'b1; irq_tlast <= 1'b1;
        @(posedge clk_dnn);
        irq_tvalid <= 1'b0; irq_tready <= 1'b0; irq_tlast <= 1'b0;
        @(posedge clk_dnn);
        if (irq !== 1'b1) fail("irq did not set on done beat");

        // 4d. Sticky: stays high over a long idle stretch.
        repeat (1000) @(posedge clk_dnn);
        if (irq !== 1'b1) fail("irq lost while idle");

        // 4e. Single-cycle clear drops it.
        @(posedge clk_dnn);
        irq_clear <= 1'b1;
        @(posedge clk_dnn);
        irq_clear <= 1'b0;
        @(posedge clk_dnn);
        if (irq !== 1'b0) fail("irq did not clear");

        // 4f. Set wins over a coincident clear.
        @(posedge clk_dnn);
        irq_tvalid <= 1'b1; irq_tready <= 1'b1; irq_tlast <= 1'b1; irq_clear <= 1'b1;
        @(posedge clk_dnn);
        irq_tvalid <= 1'b0; irq_tready <= 1'b0; irq_tlast <= 1'b0; irq_clear <= 1'b0;
        @(posedge clk_dnn);
        if (irq !== 1'b1) fail("set did not win over coincident clear");

        // Final clear so the bench ends in a quiet state.
        @(posedge clk_dnn);
        irq_clear <= 1'b1;
        @(posedge clk_dnn);
        irq_clear <= 1'b0;

        // 5. Full clear chain through the APB decode and pulse_sync.
        // 5a. Set the second irq instance, then clear it with the decoded
        //     write. Allow a few cycles for the toggle to cross domains.
        irq2_set;
        if (irq2 !== 1'b1) fail("chain irq did not set");
        apb_write(6'h3C, 32'h1);
        repeat (8) @(posedge clk_dnn);
        if (irq2 !== 1'b0) fail("chain irq did not clear via APB write");

        // 5b. A write with bit 0 low must not clear.
        irq2_set;
        apb_write(6'h3C, 32'hFFFF_FFFE);
        repeat (8) @(posedge clk_dnn);
        if (irq2 !== 1'b1) fail("chain irq cleared on bit0 low write");

        // 5c. A write to a different offset must not clear.
        apb_write(6'h38, 32'h1);
        repeat (8) @(posedge clk_dnn);
        if (irq2 !== 1'b1) fail("chain irq cleared on wrong offset");

        // 5d. Second decoded clear works after the toggle flipped once.
        apb_write(6'h3C, 32'h1);
        repeat (8) @(posedge clk_dnn);
        if (irq2 !== 1'b0) fail("chain irq did not clear a second time");

        repeat (10) @(posedge clk_peri);
        if (errors == 0) begin
            $display("tb_openeye_glue: PASS");
            $finish;
        end else begin
            $display("tb_openeye_glue: %0d error(s)", errors);
            $fatal(1);
        end
    end

    // Watchdog: the whole bench takes well under 1 ms of simulated time.
    initial begin
        #1_000_000;
        $display("tb_openeye_glue: watchdog timeout");
        $fatal(1);
    end

endmodule
