/* crc32.c: reflected CRC32, polynomial 0xEDB88320, same result as zlib. */
#include "crc32.h"

static uint32_t table[256];

void crc32_init(void)
{
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        table[i] = c;
    }
}

uint32_t crc32_mem(const void *data, uint32_t bytes)
{
    const uint8_t *p = (const uint8_t *)data;
    uint32_t c = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < bytes; i++)
        c = table[(c ^ p[i]) & 0xFFu] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}
