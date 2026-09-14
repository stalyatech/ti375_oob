/*
 * snpu_hal.c
 *
 * CSR sequences shared by the bring-up tests. The order mirrors the RTL
 * testbench: descriptor base and count, interrupt mask, then the start bit.
 */
#include "bsp.h"
#include "clint.h"
#include "snpu_hal.h"

void snpu_start(uint32_t desc_base, uint32_t desc_count, uint32_t irq_mask)
{
    snpu_wr(SNPU_REG_IRQ_STATUS, 0xFu);
    snpu_wr(SNPU_REG_DESC_BASE, desc_base);
    snpu_wr(SNPU_REG_DESC_COUNT, desc_count);
    snpu_wr(SNPU_REG_IRQ_MASK, irq_mask);
    snpu_wr(SNPU_REG_CTRL, 0x1u);
}

uint64_t snpu_time_us(void)
{
    return clint_getTime(BSP_CLINT) / (BSP_CLINT_HZ / 1000000u);
}

uint32_t snpu_wait(uint32_t timeout_us)
{
    uint64_t t0 = snpu_time_us();
    for (;;) {
        uint32_t st = snpu_rd(SNPU_REG_IRQ_STATUS);
        if (st & (SNPU_IRQ_DONE | SNPU_IRQ_ERROR | SNPU_IRQ_TIMEOUT)) {
            snpu_wr(SNPU_REG_IRQ_STATUS, st);
            return st;
        }
        if (snpu_time_us() - t0 > timeout_us)
            return 0;
    }
}

void snpu_read_counters(struct snpu_counters *c)
{
    c->cycles     = snpu_rd(SNPU_REG_CYCLE_CNT);
    c->stall_ibuf = snpu_rd(SNPU_REG_STALL_IBUF);
    c->stall_wgt  = snpu_rd(SNPU_REG_STALL_WGT);
    c->stall_acc  = snpu_rd(SNPU_REG_STALL_ACC);
    c->stall_wr   = snpu_rd(SNPU_REG_STALL_WR);
    c->desc_done  = snpu_rd(SNPU_REG_DESC_DONE);
    c->status     = snpu_rd(SNPU_REG_STATUS);
}
