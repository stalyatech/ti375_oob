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
 * CTRL and BOOT_ADDR are writable from the host port only. Accesses outside
 * the map, and writes to read-only registers, complete with a bus error.
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
#define AMP_REG_SCRATCH(n)      (0x20u + 4u * (n))   /* n = 0..7, shared */

/*
 * PLIC lines
 *   hard SoC  userInterruptK = PLIC 11   doorbell from the FCU
 *   FCU       userInterruptA = PLIC 16   doorbell from the host
 */

#endif /* AMP_CTRL_H */
