// =============================================================================
// amp_ctrl.v
//
// Asymmetric multiprocessing control block between the hardened quad-core SoC,
// which runs Linux, and the soft FCU SoC, which runs the NuttX flight stack.
// The hard SoC is the boot master: it loads the FCU image into the shared DDR,
// tells the FCU where to start and lets it out of reset. After that the two
// sides talk through doorbells and shared memory (remoteproc / rpmsg).
//
// Two APB3 slave ports share one register file:
//   host port   hard SoC APB window, CPU address 0xE810_8000
//   fcu  port   FCU APB window,      CPU address 0xF810_8000
// Both APB windows run on the peripheral clock, so there is no clock domain
// crossing inside this block.
//
// Register map, identical offsets on both ports
//   0x00 ID          RO   0x414D5001, "AMP" version 1
//   0x04 CTRL        RW*  bit 0 FCU_HOLD, 1 holds the FCU in reset
//   0x08 BOOT_ADDR   RW*  FCU entry point, read by the FCU boot stub
//   0x0C STATUS      RO   bit 0 FCU_HOLD, bit 1 host irq, bit 2 fcu irq
//   0x10 DB_SEND     W1S  ring the other side; reads return what is still
//                         pending over there
//   0x14 DB_PENDING  W1C  doorbells rung by the other side
//   0x18 DB_MASK     RW   pending bits that raise this side's interrupt
//   0x1C SYS_RESET   WO*  write SYS_RESET_KEY to reset the whole system, as
//                         the reset button does; reads 0, other values are
//                         an error
//   0x20 SCRATCH0 .. 0x3C SCRATCH7   RW, shared by both sides
//   * host port only. The FCU cannot release itself, move its own entry
//     point or reset the system; any FCU access to these is an error.
//
// Both interrupts are level: they stay high while a masked-in doorbell is
// pending and drop when that side clears it. A doorbell set and cleared in
// the same cycle stays set, so a ring is never lost to a racing acknowledge.
// When both sides write the same scratch word in the same cycle the host
// wins.
//
// Accesses outside the register map, and writes to read-only registers,
// complete with PSLVERR so a stale driver fails at its first access instead
// of reading silent zeros.
//
// Language: Verilog 2001. Reset: active-high synchronous.
// =============================================================================
`timescale 1ns / 1ps

module amp_ctrl #(
    // Address bits the port decodes. The register file occupies the low
    // 64 bytes; anything above that in the window is an error.
    parameter        AW              = 12,
    // The FCU stays in reset after power-up until the host releases it.
    // Its boot stub jumps to BOOT_ADDR, which is only meaningful once the
    // host has loaded an image there.
    parameter        FCU_HOLD_RESET  = 1'b1,
    parameter [31:0] BOOT_ADDR_RESET = 32'h0000_1000
) (
    input  wire          clk,
    input  wire          rst,

    // host port, hard SoC
    input  wire [AW-1:0] h_paddr,
    input  wire          h_psel,
    input  wire          h_penable,
    input  wire          h_pwrite,
    input  wire [31:0]   h_pwdata,
    output reg  [31:0]   h_prdata,
    output wire          h_pready,
    output reg           h_pslverr,

    // fcu port, soft SoC
    input  wire [AW-1:0] f_paddr,
    input  wire          f_psel,
    input  wire          f_penable,
    input  wire          f_pwrite,
    input  wire [31:0]   f_pwdata,
    output reg  [31:0]   f_prdata,
    output wire          f_pready,
    output reg           f_pslverr,

    output wire          fcu_hold,   // to the FCU asynchronous reset
    output reg           host_irq,   // doorbell from the FCU, to the hard SoC PLIC
    output reg           fcu_irq,    // doorbell from the host, to the FCU PLIC
    output reg           sys_reset   // one-cycle request, to the reset button input
);

    localparam [31:0] ID_VALUE      = 32'h414D_5001;
    localparam [31:0] SYS_RESET_KEY = 32'h5253_5421;    // "RST!"

    localparam [3:0] R_ID         = 4'h0,
                     R_CTRL       = 4'h1,
                     R_BOOT_ADDR  = 4'h2,
                     R_STATUS     = 4'h3,
                     R_DB_SEND    = 4'h4,
                     R_DB_PENDING = 4'h5,
                     R_DB_MASK    = 4'h6,
                     R_SYS_RESET  = 4'h7;
    // words 8..15 are the scratch registers

    // ---------------------------------------------------------------- decode
    // Zero wait states on both ports.
    assign h_pready = 1'b1;
    assign f_pready = 1'b1;

    wire       h_acc = h_psel & h_penable;
    wire       f_acc = f_psel & f_penable;
    wire       h_wr  = h_acc & h_pwrite;
    wire       f_wr  = f_acc & f_pwrite;

    // Inside the 64 byte register file?
    wire       h_in  = (h_paddr[AW-1:6] == {(AW-6){1'b0}});
    wire       f_in  = (f_paddr[AW-1:6] == {(AW-6){1'b0}});
    wire [3:0] h_w   = h_paddr[5:2];
    wire [3:0] f_w   = f_paddr[5:2];
    wire       h_scr = h_w[3];
    wire       f_scr = f_w[3];

    // ------------------------------------------------------------- registers
    reg         hold_q;
    reg  [31:0] boot_addr_q;
    reg  [31:0] h2f_pending_q;   // rung by the host, seen by the FCU
    reg  [31:0] f2h_pending_q;   // rung by the FCU, seen by the host
    reg  [31:0] h_mask_q;
    reg  [31:0] f_mask_q;
    // Flat vector rather than an array: two write ports, two asynchronous
    // reads and a reset of every word is not something a RAM can do, and an
    // array invites the synthesiser to try.
    reg  [255:0] scratch_q;

    assign fcu_hold = hold_q;

    // Doorbell updates. Each pending word is set from one port and cleared
    // from the other; applying the clear first makes a same-cycle set win.
    wire [31:0] h2f_set = (h_wr && h_in && h_w == R_DB_SEND)    ? h_pwdata : 32'd0;
    wire [31:0] h2f_clr = (f_wr && f_in && f_w == R_DB_PENDING) ? f_pwdata : 32'd0;
    wire [31:0] f2h_set = (f_wr && f_in && f_w == R_DB_SEND)    ? f_pwdata : 32'd0;
    wire [31:0] f2h_clr = (h_wr && h_in && h_w == R_DB_PENDING) ? h_pwdata : 32'd0;

    always @(posedge clk) begin
        if (rst) begin
            hold_q        <= FCU_HOLD_RESET;
            boot_addr_q   <= BOOT_ADDR_RESET;
            h2f_pending_q <= 32'd0;
            f2h_pending_q <= 32'd0;
            h_mask_q      <= 32'd0;
            f_mask_q      <= 32'd0;
            host_irq      <= 1'b0;
            fcu_irq       <= 1'b0;
            sys_reset     <= 1'b0;
            scratch_q     <= 256'd0;
        end else begin
            sys_reset <= h_wr && h_in && h_w == R_SYS_RESET && h_pwdata == SYS_RESET_KEY;

            h2f_pending_q <= (h2f_pending_q & ~h2f_clr) | h2f_set;
            f2h_pending_q <= (f2h_pending_q & ~f2h_clr) | f2h_set;

            // Registered so the PLIC inputs come straight from flops.
            host_irq <= |(f2h_pending_q & h_mask_q);
            fcu_irq  <= |(h2f_pending_q & f_mask_q);

            if (h_wr && h_in) begin
                case (h_w)
                    R_CTRL:      hold_q      <= h_pwdata[0];
                    R_BOOT_ADDR: boot_addr_q <= h_pwdata;
                    R_DB_MASK:   h_mask_q    <= h_pwdata;
                    default: ;
                endcase
            end

            if (f_wr && f_in && f_w == R_DB_MASK)
                f_mask_q <= f_pwdata;

            // Host after FCU, so the host wins a same-cycle collision.
            if (f_wr && f_in && f_scr)
                scratch_q[f_w[2:0]*32 +: 32] <= f_pwdata;
            if (h_wr && h_in && h_scr)
                scratch_q[h_w[2:0]*32 +: 32] <= h_pwdata;
        end
    end

    wire [31:0] status = {29'd0, fcu_irq, host_irq, hold_q};

    // ------------------------------------------------------------ read data
    always @(*) begin
        h_prdata = 32'd0;
        if (h_scr)
            h_prdata = scratch_q[h_w[2:0]*32 +: 32];
        else case (h_w)
            R_ID:         h_prdata = ID_VALUE;
            R_CTRL:       h_prdata = {31'd0, hold_q};
            R_BOOT_ADDR:  h_prdata = boot_addr_q;
            R_STATUS:     h_prdata = status;
            R_DB_SEND:    h_prdata = h2f_pending_q;
            R_DB_PENDING: h_prdata = f2h_pending_q;
            R_DB_MASK:    h_prdata = h_mask_q;
            default:      h_prdata = 32'd0;
        endcase
    end

    always @(*) begin
        f_prdata = 32'd0;
        if (f_scr)
            f_prdata = scratch_q[f_w[2:0]*32 +: 32];
        else case (f_w)
            R_ID:         f_prdata = ID_VALUE;
            R_CTRL:       f_prdata = {31'd0, hold_q};
            R_BOOT_ADDR:  f_prdata = boot_addr_q;
            R_STATUS:     f_prdata = status;
            R_DB_SEND:    f_prdata = f2h_pending_q;
            R_DB_PENDING: f_prdata = h2f_pending_q;
            R_DB_MASK:    f_prdata = f_mask_q;
            default:      f_prdata = 32'd0;
        endcase
    end

    // ---------------------------------------------------------------- errors
    // The FCU may not write ID, CTRL, BOOT_ADDR or STATUS, nor touch
    // SYS_RESET; the host may not write ID or STATUS, nor SYS_RESET with
    // anything but the key.
    always @(*) begin
        h_pslverr = 1'b0;
        if (h_acc) begin
            if (!h_in)
                h_pslverr = 1'b1;
            else if (h_pwrite && !h_scr && (h_w == R_ID || h_w == R_STATUS))
                h_pslverr = 1'b1;
            else if (h_pwrite && !h_scr && h_w == R_SYS_RESET && h_pwdata != SYS_RESET_KEY)
                h_pslverr = 1'b1;
        end
    end

    always @(*) begin
        f_pslverr = 1'b0;
        if (f_acc) begin
            if (!f_in || (!f_scr && f_w == R_SYS_RESET))
                f_pslverr = 1'b1;
            else if (f_pwrite && !f_scr && f_w <= R_STATUS)
                f_pslverr = 1'b1;
        end
    end

endmodule
