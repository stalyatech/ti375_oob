/*
 * snpu_hal.h
 *
 * Minimal StalyaNPU access layer for the hard SoC bare-metal test. The CSR
 * window sits in the upper half of the hard SoC APB peripheral 0, which the
 * CPU reaches through its AXI-A port at 0xE810_0000.
 */
#ifndef SNPU_HAL_H
#define SNPU_HAL_H

#include <stdint.h>
#include "soc.h"
#include "stalyanpu_isa.h"

#define SNPU_CSR_BASE   (IO_APB_SLAVE_0_INPUT + 0x4000u)

#define SNPU_IRQ_DONE   0x1u
#define SNPU_IRQ_DESC   0x2u
#define SNPU_IRQ_ERROR  0x4u
#define SNPU_IRQ_TIMEOUT 0x8u

struct snpu_counters {
    uint32_t cycles;
    uint32_t stall_ibuf;
    uint32_t stall_wgt;
    uint32_t stall_acc;
    uint32_t stall_wr;
    uint32_t desc_done;
    uint32_t status;
};

static inline uint32_t snpu_rd(uint32_t off)
{
    return *(volatile uint32_t *)(SNPU_CSR_BASE + off);
}

static inline void snpu_wr(uint32_t off, uint32_t v)
{
    *(volatile uint32_t *)(SNPU_CSR_BASE + off) = v;
}

/* Start a descriptor list. irq_mask selects which IRQ_STATUS bits raise
 * the interrupt line; polling callers pass 0. */
void snpu_start(uint32_t desc_base, uint32_t desc_count, uint32_t irq_mask);

/* Poll IRQ_STATUS until done or error, or until timeout_us elapses.
 * Returns the IRQ_STATUS value seen (0 on timeout). The bits are cleared
 * before returning. */
uint32_t snpu_wait(uint32_t timeout_us);

void snpu_read_counters(struct snpu_counters *c);

/* Return the CLINT time in microseconds. */
uint64_t snpu_time_us(void);

#endif /* SNPU_HAL_H */
