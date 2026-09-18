/*
 * fcu_fw_test: FCU firmware for testing Linux remoteproc (load, start, stop).
 *
 * Runs from DDR at AMP_FCU_MEM_BASE, after the on-chip RAM boot stub jumped
 * here. Its LED pattern differs from the on-chip RAM LED test, so the board
 * shows which image runs:
 *
 *   LED1+3+5 and LED2+4 alternate every 150 ms
 *
 * amp_ctrl, as in the "Boot and park protocol" of sw/amp/amp_ctrl.h:
 *
 *   SCRATCH0   heartbeat
 *   SCRATCH1   AMP_FCU_MAGIC
 *   SCRATCH4   AMP_STATE_RUNNING, then AMP_STATE_PARKED
 *   doorbell   AMP_DB_USER to the host at start; AMP_DB_PARK is answered
 *              by parking
 */
#include <stdint.h>
#include "soc.h"
#include "io.h"
#include "gpio.h"
#include "clint.h"
#include "amp_ctrl.h"

#define GPIO        SYSTEM_GPIO_0_IO_CTRL
#define AMP         AMP_FCU_BASE
#define LED(n)      (1u << (n))
#define LEDS_ODD    (LED(1) | LED(3) | LED(5))
#define LEDS_EVEN   (LED(2) | LED(4))
#define LED_MASK    (LEDS_ODD | LEDS_EVEN)

static u32 amp_read(u32 reg)          { return read_u32(AMP + reg); }
static void amp_write(u32 reg, u32 v) { write_u32(v, AMP + reg); }

static void delay_ms(u32 ms)
{
    clint_uDelay(ms * 1000u, SYSTEM_CLINT_HZ, SYSTEM_CLINT_CTRL);
}

static void park(void)
{
    amp_write(AMP_REG_DB_PENDING, AMP_DB_PARK);
    gpio_setOutput(GPIO, 0);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_STATE), AMP_STATE_PARKED);
    amp_write(AMP_REG_DB_SEND, AMP_DB_PARK);
    for (;;)
        asm volatile("wfi");                    /* MIE is off since start.S */
}

int main(void)
{
    u32 beat = 0;

    gpio_setOutput(GPIO, 0);
    gpio_setOutputEnable(GPIO, LED_MASK);

    amp_write(AMP_REG_SCRATCH(AMP_SCR_MAGIC), AMP_FCU_MAGIC);
    amp_write(AMP_REG_SCRATCH(AMP_SCR_STATE), AMP_STATE_RUNNING);
    amp_write(AMP_REG_DB_SEND, AMP_DB_USER);

    for (;;) {
        if (amp_read(AMP_REG_DB_PENDING) & AMP_DB_PARK)
            park();

        gpio_setOutput(GPIO, (beat & 1u) ? LEDS_EVEN : LEDS_ODD);
        amp_write(AMP_REG_SCRATCH(AMP_SCR_HEARTBEAT), ++beat);
        delay_ms(150);
    }
}
