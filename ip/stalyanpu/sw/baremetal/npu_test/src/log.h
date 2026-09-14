/*
 * log.h: test output to the terminal UART and to a RAM ring buffer.
 *
 * The RAM copy lets the host read the results through the debugger when
 * no terminal is attached (dump log_buf for log_len bytes).
 */
#ifndef LOG_H
#define LOG_H

#include <stdint.h>

#define LOG_BUF_BYTES 16384

extern char log_buf[LOG_BUF_BYTES];
extern volatile uint32_t log_len;

void log_init(void);
void log_printf(const char *fmt, ...);

#endif /* LOG_H */
