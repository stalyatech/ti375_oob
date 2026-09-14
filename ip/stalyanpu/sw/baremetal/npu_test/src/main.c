/*
 * main.c: StalyaNPU board bring-up test for the Ti375 hard SoC.
 *
 * The DDR image (blob plus input tensor) is loaded through the debugger
 * before this program runs; testset.h names the descriptor list and the
 * output regions with their golden CRC32. The tests run in order:
 *
 *   T1  CSR identity registers
 *   T2  blob header in DDR (checks the debugger load and the CPU DDR path)
 *   T3  one descriptor list run with polling, region CRC compare
 *   T4  repeated runs for the frame rate and the stall counters
 *   T5  one run completed through the PLIC interrupt (id 9)
 *
 * Every test prints PASS or FAIL on the UART. A failing test does not stop
 * the later ones unless the accelerator never reports completion.
 */
#include <stdint.h>
#include "bsp.h"
#include "riscv.h"
#include "plic.h"
#include "vexriscv.h"
#include "snpu_hal.h"
#include "crc32.h"
#include "log.h"
#include "testset.h"

#ifndef LOOP_FRAMES
#define LOOP_FRAMES 10
#endif

#define RUN_TIMEOUT_US 5000000u

void trap_entry(void);

static volatile uint32_t irq_count;
static volatile uint32_t irq_status_seen;

static int fails;

static void report(const char *name, int ok)
{
    log_printf("%s: %s\r\n", name, ok ? "PASS" : "FAIL");
    if (!ok)
        fails++;
}

static void print_counters(const struct snpu_counters *c)
{
    /* The counters are cycle classes of the busy time: input fill phases
     * (DDR bound), run phase cycles with the array idle, cycles with a
     * vector entering the array, and output words held by the write path. */
    log_printf("  cycles %u  fill %u  run_idle %u  mac %u  wr_wait %u  desc_done %u  status 0x%x\r\n",
               c->cycles, c->stall_ibuf, c->stall_wgt, c->stall_acc, c->stall_wr,
               c->desc_done, c->status);
    if (c->cycles)
        log_printf("  fill %u%%  run_idle %u%%  mac %u%%  other %u%%\r\n",
                   (uint32_t)(100ull * c->stall_ibuf / c->cycles),
                   (uint32_t)(100ull * c->stall_wgt / c->cycles),
                   (uint32_t)(100ull * c->stall_acc / c->cycles),
                   (uint32_t)(100 - 100ull * (c->stall_ibuf + c->stall_wgt + c->stall_acc) / c->cycles));
}

/* T1 */
static void test_identity(void)
{
    uint32_t id = snpu_rd(SNPU_REG_ID);
    uint32_t ver = snpu_rd(SNPU_REG_VERSION);
    uint32_t geo = snpu_rd(SNPU_REG_GEOMETRY);
    log_printf("  ID 0x%x VERSION 0x%x GEOMETRY 0x%x\r\n", id, ver, geo);
    log_printf("  n_chain %u chain_len %u log2_pmax %u ibuf_kb %u\r\n",
               geo & 0xFF, (geo >> 8) & 0xFF, (geo >> 16) & 0xF, geo >> 20);
    report("T1 identity", id == SNPU_BLOB_MAGIC);
}

/* T2 */
static void test_blob_header(void)
{
    const volatile uint32_t *h = (const volatile uint32_t *)TESTSET_BLOB_BASE;
    uint32_t magic = h[0];
    uint32_t desc_count = h[5];
    log_printf("  blob magic 0x%x size %u desc_count %u\r\n", magic, h[3], desc_count);
    report("T2 blob header", magic == SNPU_BLOB_MAGIC && desc_count == TESTSET_DESC_COUNT);
}

static int check_regions(void)
{
    int ok = 1;
    data_cache_invalidate_all();
    for (int i = 0; i < TESTSET_N_REGIONS; i++) {
        const struct testset_region *r = &testset_regions[i];
        uint32_t crc = crc32_mem((const void *)r->base, r->bytes);
        log_printf("  region %s @0x%x %u B crc 0x%x golden 0x%x %s\r\n",
                   r->name, r->base, r->bytes, crc, r->crc32, crc == r->crc32 ? "ok" : "MISMATCH");
        if (crc != r->crc32)
            ok = 0;
    }
    return ok;
}

/* T3 */
static int test_single_run(void)
{
    struct snpu_counters c;
    uint64_t t0 = snpu_time_us();
    snpu_start(TESTSET_DESC_BASE, TESTSET_DESC_COUNT, 0);
    uint32_t st = snpu_wait(RUN_TIMEOUT_US);
    uint64_t dt = snpu_time_us() - t0;
    snpu_read_counters(&c);
    log_printf("  irq_status 0x%x wall %u us\r\n", st, (uint32_t)dt);
    print_counters(&c);
    if (st == 0) {
        report("T3 single run (timeout)", 0);
        return 0;
    }
    if (st & (SNPU_IRQ_ERROR | SNPU_IRQ_TIMEOUT)) {
        log_printf("  error code 0x%x at descriptor %u\r\n", (c.status >> 8) & 0xFF, c.status >> 16);
        report("T3 single run (error)", 0);
        return 0;
    }
    report("T3 single run", check_regions());
    return 1;
}

/* T4 */
static void test_loop(void)
{
    struct snpu_counters c;
    uint32_t cycles = 0;
    uint64_t t0 = snpu_time_us();
    for (int i = 0; i < LOOP_FRAMES; i++) {
        snpu_start(TESTSET_DESC_BASE, TESTSET_DESC_COUNT, 0);
        uint32_t st = snpu_wait(RUN_TIMEOUT_US);
        if (st != SNPU_IRQ_DONE && st != (SNPU_IRQ_DONE | SNPU_IRQ_DESC)) {
            log_printf("  frame %u irq_status 0x%x\r\n", i, st);
            report("T4 loop", 0);
            return;
        }
        snpu_read_counters(&c);
        cycles += c.cycles;
    }
    uint64_t dt = snpu_time_us() - t0;
    uint32_t us_per_frame = (uint32_t)(dt / LOOP_FRAMES);
    log_printf("  %u frames, %u us per frame, %u.%u fps, %u NPU cycles per frame\r\n",
               LOOP_FRAMES, us_per_frame, 1000000u / us_per_frame,
               (10000000u / us_per_frame) % 10, cycles / LOOP_FRAMES);
    print_counters(&c);
    report("T4 loop", check_regions());
}

/* T5: interrupt path. */
static void npu_isr(void)
{
    uint32_t claim;
    while ((claim = plic_claim(BSP_PLIC, BSP_PLIC_CPU_0))) {
        if (claim == SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT) {
            irq_status_seen = snpu_rd(SNPU_REG_IRQ_STATUS);
            snpu_wr(SNPU_REG_IRQ_STATUS, irq_status_seen);
            irq_count++;
        }
        plic_release(BSP_PLIC, BSP_PLIC_CPU_0, claim);
    }
}

void trap(void)
{
    int32_t mcause = csr_read(mcause);
    if (mcause < 0 && (mcause & 0xF) == CAUSE_MACHINE_EXTERNAL) {
        npu_isr();
        return;
    }
    log_printf("*** unexpected trap mcause 0x%x mepc 0x%x ***\r\n", mcause, csr_read(mepc));
    while (1)
        ;
}

static void test_irq(void)
{
    plic_set_threshold(BSP_PLIC, BSP_PLIC_CPU_0, 0);
    plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0, SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT, 1);
    plic_set_priority(BSP_PLIC, SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT, 1);
    csr_write(mtvec, trap_entry);
    csr_set(mie, MIE_MEIE);
    csr_write(mstatus, csr_read(mstatus) | MSTATUS_MPP | MSTATUS_MIE);

    irq_count = 0;
    snpu_start(TESTSET_DESC_BASE, TESTSET_DESC_COUNT, SNPU_IRQ_DONE | SNPU_IRQ_ERROR);
    uint64_t t0 = snpu_time_us();
    while (irq_count == 0 && snpu_time_us() - t0 < RUN_TIMEOUT_US)
        ;
    csr_clear(mie, MIE_MEIE);
    plic_set_enable(BSP_PLIC, BSP_PLIC_CPU_0, SYSTEM_PLIC_USER_INTERRUPT_I_INTERRUPT, 0);
    log_printf("  irq_count %u irq_status 0x%x\r\n", irq_count, irq_status_seen);
    report("T5 interrupt", irq_count == 1 && (irq_status_seen & SNPU_IRQ_DONE));
}

void main(void)
{
    log_init();
    log_printf("\r\n*** StalyaNPU bring-up test, set %s ***\r\n", TESTSET_NAME);
    log_printf("CSR 0x%x  desc 0x%x x%u  regions %u\r\n",
               SNPU_CSR_BASE, TESTSET_DESC_BASE, TESTSET_DESC_COUNT, TESTSET_N_REGIONS);
    crc32_init();
    fails = 0;

    test_identity();
    test_blob_header();
    if (test_single_run()) {
        test_loop();
        test_irq();
    }

    log_printf("*** %s (%u failing) ***\r\n", fails ? "FAILED" : "ALL PASS", fails);
    while (1)
        ;
}
