// =============================================================================
// openeye_irq.v  —  OpenEye DNN "done" interrupt latch
//
// OpenEye's AXI wrapper (open_eye_mt_v1_0) exposes NO interrupt line; inference
// completion is only signalled by the final output-stream beat (dma_o_tlast).
// This tiny module latches that event into a sticky, level-sensitive interrupt
// that a RISC-V userInterrupt line can consume, and is cleared by a CPU write.
//
// Intended use (FMU DNN pipeline, Faz 2):
//   - dma_o_t* come from open_eye_mt_v1_0 (or the DNN DMA output channel).
//   - irq  -> Hard SoC userInterruptA
//   - irq_clear <- a write-1-to-clear pulse decoded from the DNN cfg window.
//
// Language: Verilog 2001. Reset: active-low async (matches OpenEye rst_ni).
// =============================================================================
`timescale 1ns / 1ps

module openeye_irq (
    input  wire clk,
    input  wire rst_n,

    // OpenEye output stream (dma_o) completion handshake
    input  wire dma_o_tvalid,
    input  wire dma_o_tready,
    input  wire dma_o_tlast,

    // Write-1-to-clear pulse from the CPU (single-cycle)
    input  wire irq_clear,

    // Sticky, level-sensitive interrupt to the SoC
    output reg  irq
);

    // A "done" event = the final beat of an output transfer actually completes.
    wire done_evt = dma_o_tvalid & dma_o_tready & dma_o_tlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq <= 1'b0;
        else if (done_evt)          // set has priority over clear
            irq <= 1'b1;
        else if (irq_clear)
            irq <= 1'b0;
    end

endmodule
