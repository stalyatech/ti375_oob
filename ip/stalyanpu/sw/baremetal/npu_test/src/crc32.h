/* crc32.h: zlib compatible CRC32 used to compare DDR regions with golden. */
#ifndef CRC32_H
#define CRC32_H

#include <stdint.h>

void crc32_init(void);
uint32_t crc32_mem(const void *data, uint32_t bytes);

#endif /* CRC32_H */
