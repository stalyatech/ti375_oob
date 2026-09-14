/* log.c: newlib vsnprintf into a line buffer, then UART and RAM ring. */
#include <stdarg.h>
#include <stdio.h>
#include "bsp.h"
#include "log.h"

char log_buf[LOG_BUF_BYTES];
volatile uint32_t log_len;

void log_init(void)
{
    /* No bootloader runs before this program, so the UART divider is
     * still at its reset value. bsp_init sets 115200 8N1. */
    bsp_init();
    log_len = 0;
}

static void log_putc(char c)
{
    uart_write(BSP_UART_TERMINAL, c);
    if (log_len < LOG_BUF_BYTES)
        log_buf[log_len++] = c;
}

void log_printf(const char *fmt, ...)
{
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (n < 0)
        return;
    if (n >= (int)sizeof line)
        n = sizeof line - 1;
    for (int i = 0; i < n; i++) {
        if (line[i] == '\n')
            log_putc('\r');
        log_putc(line[i]);
    }
}
