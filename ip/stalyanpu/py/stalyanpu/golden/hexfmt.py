"""$readmemh memory images with 128-bit words.

Each line holds one little endian 128-bit word (16 bytes, byte 0 in the
lowest hex digits). Sparse regions start with an ``@<word address>`` line,
where the word address is the byte address divided by 16. Testbenches load
the file into the AXI memory model with $readmemh and compare golden
regions against the same format.
"""

from __future__ import annotations

import zlib

WORD = 16


def write_hex(path: str, ranges: list) -> None:
    """ranges: [(byte address, bytes)], addresses 16 byte aligned."""
    with open(path, "w", newline="\n") as fh:
        for addr, data in ranges:
            assert addr % WORD == 0, addr
            if len(data) % WORD:
                data = bytes(data) + b"\0" * (WORD - len(data) % WORD)
            fh.write(f"@{addr // WORD:08x}\n")
            for i in range(0, len(data), WORD):
                fh.write(data[i:i + WORD][::-1].hex() + "\n")


def write_win_hex(path: str, ranges: list, base: int) -> None:
    """Like write_hex, with word addresses relative to ``base`` for a
    direct $readmemh into one memory window array."""
    with open(path, "w", newline="\n") as fh:
        for addr, data in ranges:
            assert addr % WORD == 0 and addr >= base, (addr, base)
            if len(data) % WORD:
                data = bytes(data) + b"\0" * (WORD - len(data) % WORD)
            fh.write(f"@{(addr-base) // WORD:08x}\n")
            for i in range(0, len(data), WORD):
                fh.write(data[i:i + WORD][::-1].hex() + "\n")


def read_hex(path: str) -> list:
    ranges = []
    addr = 0
    buf = bytearray()
    start = 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("@"):
                if buf:
                    ranges.append((start, bytes(buf)))
                    buf = bytearray()
                addr = int(line[1:], 16) * WORD
                start = addr
                continue
            buf += bytes.fromhex(line)[::-1]
            addr += WORD
    if buf:
        ranges.append((start, bytes(buf)))
    return ranges


def crc32(data) -> int:
    return zlib.crc32(bytes(data)) & 0xFFFFFFFF
