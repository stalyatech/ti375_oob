/*
 * amp_ctrl.h — register map of rtl/amp_ctrl.v
 *
 * The AMP control block sits between the hardened SoC (Linux, boot master)
 * and the soft FCU SoC. Both sides see the same register file at the same
 * offsets, through their own APB windows:
 *
 *   hard SoC  AMP_HOST_BASE  0xE810_8000
 *   FCU       AMP_FCU_BASE   0xF810_8000
 *
 * CTRL, BOOT_ADDR and SYS_RESET are writable from the host port only.
 * Accesses outside the map, and writes to read-only registers, complete with
 * a bus error.
 */
#ifndef AMP_CTRL_H
#define AMP_CTRL_H

#define AMP_HOST_BASE           0xE8108000u
#define AMP_FCU_BASE            0xF8108000u

#define AMP_ID_VALUE            0x414D5001u     /* "AMP", version 1 */

#define AMP_REG_ID              0x00u           /* RO */
#define AMP_REG_CTRL            0x04u           /* RW host, RO FCU */
#define   AMP_CTRL_FCU_HOLD     (1u << 0)       /* 1 = FCU held in reset; set at power-up */
#define AMP_REG_BOOT_ADDR       0x08u           /* RW host, RO FCU: FCU entry point */
#define AMP_REG_STATUS          0x0Cu           /* RO */
#define   AMP_STATUS_FCU_HOLD   (1u << 0)
#define   AMP_STATUS_HOST_IRQ   (1u << 1)
#define   AMP_STATUS_FCU_IRQ    (1u << 2)
#define AMP_REG_DB_SEND         0x10u           /* W1S: ring the other side */
#define AMP_REG_DB_PENDING      0x14u           /* W1C: doorbells rung by the other side */
#define AMP_REG_DB_MASK         0x18u           /* pending bits that raise this side's irq */
#define AMP_REG_SYS_RESET       0x1Cu           /* WO host: AMP_SYS_RESET_KEY resets the whole
                                                   system, as the reset button does */
#define   AMP_SYS_RESET_KEY     0x52535421u     /* "RST!" */
#define AMP_REG_SCRATCH(n)      (0x20u + 4u * (n))   /* n = 0..7, shared */

/*
 * PLIC lines
 *   hard SoC  userInterruptK = PLIC 11   doorbell from the FCU
 *   FCU       userInterruptA = PLIC 16   doorbell from the host
 */

/*
 * Boot and park protocol between the host (Linux remoteproc, sw/linux/fcu_rproc)
 * and the FCU on-chip RAM image (sw/fcu_test), on top of the registers above.
 *
 * The FCU always starts at 0xF900_0000. To run an image from DDR the host holds
 * the FCU, loads the image into the FCU memory region, writes BOOT_ADDR and
 * AMP_BOOT_MAGIC, then releases it. The on-chip RAM image jumps to BOOT_ADDR
 * with every hart only when the magic is present and the address lies in the
 * region; otherwise it runs the LED test. The magic is cleared by the host
 * when it stops the FCU, and amp_ctrl comes up with it cleared at power-up,
 * so the FSBL's release at power-up always gets the LED test.
 *
 * To stop the FCU without wedging the shared DDR switch, the host asks it to
 * park first: doorbell bit AMP_DB_PARK. The FCU finishes its bus traffic, sets
 * AMP_SCR_STATE to AMP_STATE_PARKED, rings AMP_DB_PARK back and idles with
 * interrupts off. Only then does the host assert FCU_HOLD.
 *
 * The region below must match the fcu reserved-memory node in the Linux device
 * tree (br2-efinix tools/efx/dts/ti375_oob-linux.dtsi).
 */
#define AMP_FCU_MEM_BASE        0x1E000000u
#define AMP_FCU_MEM_SIZE        0x02000000u     /* 32 MiB */

#define AMP_SCR_HEARTBEAT       0               /* FCU: incremented while running */
#define AMP_SCR_MAGIC           1               /* FCU: AMP_FCU_MAGIC once running */
#define AMP_SCR_PATTERN         2               /* FCU test: current LED pattern */
#define AMP_SCR_STATE           4               /* FCU: AMP_STATE_* */
#define AMP_SCR_BOOT            6               /* host: AMP_BOOT_MAGIC to boot BOOT_ADDR */

#define AMP_FCU_MAGIC           0x46435521u     /* "FCU!" */
#define AMP_BOOT_MAGIC          0x424F4F54u     /* "BOOT" */

#define AMP_STATE_LED_TEST      1u              /* on-chip RAM LED test running */
#define AMP_STATE_BOOTING       2u              /* stub jumping to BOOT_ADDR */
#define AMP_STATE_RUNNING       3u              /* DDR image running */
#define AMP_STATE_PARKED        4u              /* idle, safe to hold */

/* Doorbell bits, both directions. */
#define AMP_DB_USER             (1u << 0)       /* host->FCU: LED test toggles its pattern;
                                                   FCU->host: FCU started */
#define AMP_DB_PARK             (1u << 1)       /* host->FCU: park request;
                                                   FCU->host: parked */

#endif /* AMP_CTRL_H */
