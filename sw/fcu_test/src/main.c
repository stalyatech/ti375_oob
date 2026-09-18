/*
 * fcu_test — bring-up test for the soft FCU SoC on the ti375_oob v3.0 design.
 *
 * Runs from the FCU's on-chip RAM (0xF900_0000), where the FCU starts once
 * the hard SoC releases it through amp_ctrl. It needs no DDR, no flash and no
 * UART, so it tests exactly one thing each:
 *
 *   LEDs sweep LED1 -> LED5 -> LED1   the FCU is running and reached amp_ctrl
 *   LED1 and LED5 flash fast          amp_ctrl did not answer with its ID:
 *                                     the FCU -> amp_ctrl APB path is broken
 *   all LEDs blink together           the host rang doorbell bit 0; ring it
 *                                     again to go back to the sweep
 *
 * It is also the FCU's boot stub. When the host has loaded an image into DDR
 * and set BOOT_ADDR plus AMP_BOOT_MAGIC (amp_ctrl.h), every hart jumps there
 * instead; see "Boot and park protocol" in amp_ctrl.h.
 *
 * It reports to the host through amp_ctrl, so the hard SoC can check the FCU
 * without looking at the board:
 *
 *   SCRATCH0   heartbeat, incremented every LED step
 *   SCRATCH1   AMP_FCU_MAGIC once the program is running
 *   SCRATCH2   current pattern, 0 = sweep, 1 = blink
 *   SCRATCH4   AMP_STATE_LED_TEST, AMP_STATE_BOOTING or AMP_STATE_PARKED
 *   doorbell   AMP_DB_USER rung towards the host once at start-up
 *
 * From Linux on the hard SoC the remoteproc driver owns amp_ctrl; from U-Boot:
 *   md.l 0xe8108020 5          heartbeat, magic, pattern, -, state
 *   mw.l 0xe8108010 1          ring the FCU: switch pattern
 *
 * GPIO0 bits 1..5 drive USER_LED1..5 (GPIOT_N_19, GPIOL_23, GPIOL_24,
 * GPIOT_N_50, GPIOT_N_64). Bit 0 is GPIOT_P_19, not an LED, and stays an input.
 */
#include <stdint.h>
#include "soc.h"
#include "io.h"
#include "gpio.h"
#include "clint.h"
#include "start.h"
#include "amp_ctrl.h"

#define GPIO        SYSTEM_GPIO_0_IO_CTRL
#define AMP         AMP_FCU_BASE
#define LED(n)      (1u << (n))                 /* n = 1..5 */
#define LED_MASK    (LED(1) | LED(2) | LED(3) | LED(4) | LED(5))

enum { PATTERN_SWEEP = 0, PATTERN_BLINK = 1 };

static void delay_ms(u32 ms)
{
    clint_uDelay(ms * 1000u, SYSTEM_CLINT_HZ, SYSTEM_CLINT_CTRL);
}

static void leds(u32 on)
{
    gpio_setOutput(GPIO, on & LED_MASK);
}

static u32 amp_read(u32 reg)          { return read_u32(AMP + reg); }
static void amp_write(u32 reg, u32 v) { write_u32(v, AMP + reg); }

/*
 * Boot stub: jump to the image the host loaded, if it asked for that.
 * The other harts wait in start.S (smp_slave) and follow through smp_unlock.
 */
static void boot_if_requested(void)
{
    u32 entry = amp_read(AMP_REG_BOOT_ADDR);

    if (amp_read(AMP_REG_SCRATCH(AMP_SCR_BOOT)) != AMP_BOOT_MAGIC)
        return;
    if (entry < AMP_FCU_MEM_BASE || entry >= AMP_FCU_MEM_BASE + AMP_FCU_MEM_SIZE ||
        (entry & 3u))
        return;

    /* Doorbells and mask left over from the previous image are not ours. */
    amp_write(AMP_REG_DB_MASK, 0);
    amp_write(AMP_REG_DB_PENDING, 0xFFFFFFFFu);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_STATE), AMP_STATE_BOOTING);

    /*
     * start.S has every hart clear smp_lottery_lock as its first store. Give
     * the other three time to get past it before releasing them, or a late one
     * would clear the lock again and never leave smp_slave.
     */
    delay_ms(1);
    smp_unlock((void (*)(u32, u32, u32))entry);
    asm volatile("fence.i");
    ((void (*)(u32, u32, u32))entry)(0, 0, 0);
}

/* Park: acknowledge and idle with no bus traffic until the host holds us. */
static void park(void)
{
    amp_write(AMP_REG_DB_PENDING, AMP_DB_PARK);
    leds(0);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_STATE), AMP_STATE_PARKED);
    amp_write(AMP_REG_DB_SEND, AMP_DB_PARK);
    asm volatile("csrc mstatus, 8");            /* MIE off: wfi never returns to code */
    for (;;)
        asm volatile("wfi");
}

/* amp_ctrl did not identify itself: flash the two outer LEDs forever. */
static void fail_no_amp(void)
{
    for (;;) {
        leds(LED(1) | LED(5));
        delay_ms(50);
        leds(0);
        delay_ms(50);
    }
}

void main(void)
{
    u32 pattern = PATTERN_SWEEP;
    u32 beat = 0;
    int pos = 1, dir = 1;
    u32 blink = 0;

    gpio_setOutput(GPIO, 0);
    gpio_setOutputEnable(GPIO, LED_MASK);

    if (amp_read(AMP_REG_ID) != AMP_ID_VALUE)
        fail_no_amp();

    boot_if_requested();

    amp_write(AMP_REG_SCRATCH(AMP_SCR_MAGIC), AMP_FCU_MAGIC);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_PATTERN), pattern);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_STATE), AMP_STATE_LED_TEST);
    amp_write(AMP_REG_DB_SEND, AMP_DB_USER);    /* tell the host we are up */

    for (;;) {
        u32 db = amp_read(AMP_REG_DB_PENDING);

        if (db & AMP_DB_PARK)
            park();

        /* A doorbell from the host toggles the pattern. */
        if (db & AMP_DB_USER) {
            amp_write(AMP_REG_DB_PENDING, AMP_DB_USER);  /* W1C: acknowledge */
            pattern ^= 1u;
            amp_write(AMP_REG_SCRATCH(AMP_SCR_PATTERN), pattern);
        }

        if (pattern == PATTERN_SWEEP) {
            leds(LED(pos));
            pos += dir;
            if (pos == 5 || pos == 1)
                dir = -dir;
            delay_ms(80);
        } else {
            blink ^= 1u;
            leds(blink ? LED_MASK : 0);
            delay_ms(250);
        }

        amp_write(AMP_REG_SCRATCH(AMP_SCR_HEARTBEAT), ++beat);
    }
}
