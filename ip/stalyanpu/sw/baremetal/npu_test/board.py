"""Board helper for the StalyaNPU bring-up on the Ti375C529 development kit.

Usage:
    python board.py program [--hex outflow/ti375_oob.bit] [--url N]
    python board.py openocd
    python board.py run --set <ddr image dir> [--no-data] [--elf build/npu_test.elf]
    python board.py uart [--port COMx] [--seconds S] [--log file]
    python board.py npu [--desc N] [--base ADDR] [--count N] [--reset]

npu      reads and decodes the CSR block, including the debug words. With
         --desc N (or --base/--count) it first starts that descriptor and
         samples the state after 0.2 s; --reset issues a soft reset first.

program  loads the bitstream over JTAG with the Efinity FTDI programmer.
openocd  starts the Efinity OpenOCD with the hard SoC BSP configuration and
         keeps it in the foreground (stop with Ctrl+C). The debug link is
         FTDI channel 1 of the on-board FT4232H (BSP default).
run      talks to the running OpenOCD over its telnet port: halts hart 0,
         restores the DDR image chunks, loads the test ELF and resumes at
         the entry point. --no-data skips the DDR image (already loaded).
uart     prints (and optionally logs) the terminal UART for S seconds.
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
EFINITY = os.environ.get("EFINITY_HOME", r"C:\Programs\Efinity\2025.2")
BSP = os.path.join(ROOT, "embedded_sw", "efx_hard_soc")
OPENOCD_DIR = os.path.join(BSP, "bsp", "efinix", "EfxSapphireSoc", "openocd")
ENTRY = 0x1000


def cmd_program(a):
    hexfile = os.path.abspath(a.hex)
    cmd = [os.path.join(EFINITY, "pgm", "bin", "ftdi_pgm.bat"), "-m", "jtag", hexfile]
    if a.url:
        cmd += ["-u", "ftdi://0x0403:0x6011:4:2/%d" % a.url]
    print(" ".join(cmd))
    return subprocess.call(cmd)


def cmd_openocd(a):
    exe = os.path.join(EFINITY, "debugger", "openocd", "bin", "openocd.exe")
    cmd = [exe, "-c", "set bsp_loc %s" % BSP.replace("\\", "/"), "-f", "ftdi_ti.cfg", "-f", "debug_ti.cfg"]
    print(" ".join(cmd))
    return subprocess.call(cmd, cwd=OPENOCD_DIR)


class Telnet:
    """Minimal OpenOCD telnet client: one command, wait for the prompt."""

    def __init__(self, host="localhost", port=4444, timeout=600):
        self.s = socket.create_connection((host, port), timeout=timeout)
        self._read_until(b"> ")

    def _read_until(self, marker):
        buf = b""
        while not buf.endswith(marker):
            chunk = self.s.recv(4096)
            if not chunk:
                raise RuntimeError("openocd closed the connection")
            buf += chunk
        return buf

    def cmd(self, text):
        self.s.sendall(text.encode() + b"\n")
        out = self._read_until(b"> ").decode("ascii", "replace")
        lines = out.replace("\r", "").split("\n")
        body = "\n".join(l for l in lines[1:-1] if l.strip())
        print("%s\n%s" % (text, body) if body else text, flush=True)
        return body

    def close(self):
        self.s.close()


SPIN_ADDR = 0xF9000100


def clean_state(t):
    """Park hart 0 in a spin loop inside the on-chip RAM.

    Without a bootloader the hart sits in a trap loop at address 0 after
    reset, and the first fetch after a resume from that state faults. A
    short run through a known good loop clears that before the program
    starts. The same address serves as the trap vector until the program
    installs its own."""
    t.cmd("mww 0x%08x 0x0000006f" % SPIN_ADDR)
    t.cmd("reg mtvec 0x%08x" % SPIN_ADDR)
    t.cmd("resume 0x%08x" % SPIN_ADDR)
    time.sleep(0.2)
    t.cmd("halt")
    t.cmd("reg mcause 0")


def symbol(elf, name):
    out = subprocess.run(["riscv-none-elf-nm", elf], capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    raise KeyError(name)


def cmd_run(a):
    t = Telnet()
    t.cmd("targets fpga_spinal.cpu0")
    t.cmd("halt")
    clean_state(t)
    if not a.no_data:
        t0 = time.time()
        for fn in sorted(os.listdir(a.set)):
            if fn.startswith("chunk_") and fn.endswith(".bin"):
                addr = int(fn[6:14], 16)
                path = os.path.join(os.path.abspath(a.set), fn).replace("\\", "/")
                t.cmd("load_image %s 0x%08x bin" % (path, addr))
        print("ddr image loaded in %.0f s" % (time.time() - t0))
    t.cmd("load_image %s" % os.path.abspath(a.elf).replace("\\", "/"))
    t.cmd("resume 0x%x" % ENTRY)
    t.close()
    return 0


def cmd_dumplog(a):
    buf = symbol(a.elf, "log_buf")
    ln = symbol(a.elf, "log_len")
    t = Telnet()
    t.cmd("targets fpga_spinal.cpu0")
    t.cmd("halt")
    n = int(t.cmd("mdw 0x%08x 1" % ln).split(":")[1].strip(), 16)
    tmp = os.path.join(HERE, "build", "log_dump.bin").replace("\\", "/")
    if n:
        t.cmd("dump_image %s 0x%08x %d" % (tmp, buf, n))
    pc = t.cmd("reg pc"); mc = t.cmd("reg mcause"); me = t.cmd("reg mepc")
    t.cmd("resume")
    t.close()
    print("---- log (%d bytes) ----" % n)
    if n:
        text = open(tmp, "rb").read().decode("ascii", "replace")
        print(text.replace(chr(13), ""))
    return 0


CSR_BASE = 0xE8104000
SEQ_STATES = ["IDLE", "FETCH", "FETCH_WAIT", "CRC", "DECODE", "PRM", "LUT", "LOAD_WAIT", "TILE",
              "FILL", "FILL_WAIT", "WEIGHTS", "RUN", "RUN_WAIT", "NEXT_TILE", "DESC_END", "MP",
              "MP_WAIT", "DONE", "ERROR", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31"]
DBG1_FLAGS = ["loaders_idle", "cmd_valid0", "cmd_valid1", "cmd_ready0", "cmd_ready1", "d_valid0", "d_valid1",
              "d_ready0", "d_ready1", "arvalid", "arready", "rvalid", "rready", "awvalid", "awready",
              "wvalid", "wready", "bvalid", "rd_busy0", "rd_busy1", "o_valid", "o_ready", "rd_err", "wr_err"]


def csr_dump(t):
    out = t.cmd("mdw 0x%08x 22" % CSR_BASE)
    w = [int(x, 16) for x in " ".join(l.split(":")[1] for l in out.splitlines()).split()]
    st = w[4]
    print("  STATUS busy=%d err=%u desc_idx=%u | IRQ_STATUS 0x%x | CYCLE %u | DESC_DONE %u | TAG 0x%x"
          % (st & 1, (st >> 8) & 0xFF, st >> 16, w[7], w[9], w[14], w[15]))
    if len(w) < 18:
        return
    d0, d1 = w[16], w[17]
    rd = d0 >> 8
    print("  seq %s | unit_busy %d mp_busy %d wr_idle %d" % (SEQ_STATES[(d0 >> 3) & 0x1F], (d0 >> 2) & 1, (d0 >> 1) & 1, d0 & 1))
    print("  rd_dma outstanding %u/%u warm %u/%u active %u/%u issue_done %u/%u ord wp %u rp %u"
          % ((rd >> 16) & 0xF, (rd >> 20) & 0xF, (rd >> 10) & 7, (rd >> 13) & 7, (rd >> 8) & 1, (rd >> 9) & 1,
             (rd >> 6) & 1, (rd >> 7) & 1, (rd >> 3) & 7, rd & 7))
    flags = [n for i, n in enumerate(DBG1_FLAGS) if (d1 >> (8 + i)) & 1]
    print("  wr_pending %u | %s" % (d1 & 0xFF, " ".join(flags)))
    if len(w) >= 22:
        aw, ww, nb, beats = w[18], w[19], w[20], w[21]
        print("  wr counters: aw_wait %u  w_wait_after_aw %u  bursts %u  beats %u  (avg beats/burst %.1f, cycles/burst aw %.1f w %.1f)"
              % (aw, ww, nb, beats, beats / max(nb, 1), aw / max(nb, 1), ww / max(nb, 1)))


def cmd_npu(a):
    t = Telnet()
    t.cmd("targets fpga_spinal.cpu0")
    t.cmd("halt")
    if a.reset:
        t.cmd("mww 0x%08x 4" % (CSR_BASE + 0x0C))
        t.cmd("mww 0x%08x 0xF" % (CSR_BASE + 0x1C))
    base, count = a.base, a.count
    if a.desc is not None:
        base, count = 0x20001000 + 128 * a.desc, 1
    if base is not None:
        t.cmd("mww 0x%08x 0x%08x" % (CSR_BASE + 0x14, base))
        t.cmd("mww 0x%08x %d" % (CSR_BASE + 0x18, count))
        t.cmd("mww 0x%08x 1" % (CSR_BASE + 0x0C))
        time.sleep(0.2)
    csr_dump(t)
    t.cmd("resume")
    t.close()
    return 0


def cmd_uart(a):
    import serial
    log = open(a.log, "a", encoding="utf-8") if a.log else None
    with serial.Serial(a.port, a.baud, timeout=0.2) as s:
        t_end = time.time() + a.seconds
        buf = b""
        while time.time() < t_end:
            chunk = s.read(4096)
            if not chunk:
                continue
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("ascii", "replace").rstrip("\r")
                print(text, flush=True)
                if log:
                    log.write(text + "\n")
                    log.flush()
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("program"); s.add_argument("--hex", default=os.path.join(ROOT, "outflow", "ti375_oob.bit"))
    s.add_argument("--url", type=int, default=None, help="FTDI url index 1..4 (default: programmer choice)")
    s.set_defaults(fn=cmd_program)
    s = sub.add_parser("openocd"); s.set_defaults(fn=cmd_openocd)
    s = sub.add_parser("run"); s.add_argument("--set", required=True, help="ddr image dir (chunk_*.bin)")
    s.add_argument("--elf", default=os.path.join(HERE, "build", "npu_test.elf"))
    s.add_argument("--no-data", action="store_true")
    s.set_defaults(fn=cmd_run)
    s = sub.add_parser("dumplog"); s.add_argument("--elf", default=os.path.join(HERE, "build", "npu_test.elf"))
    s.set_defaults(fn=cmd_dumplog)
    s = sub.add_parser("npu"); s.add_argument("--desc", type=int, default=None)
    s.add_argument("--base", type=lambda v: int(v, 0), default=None); s.add_argument("--count", type=int, default=1)
    s.add_argument("--reset", action="store_true"); s.set_defaults(fn=cmd_npu)
    s = sub.add_parser("uart"); s.add_argument("--port", default="COM11"); s.add_argument("--baud", type=int, default=115200)
    s.add_argument("--seconds", type=float, default=30); s.add_argument("--log", default=None)
    s.set_defaults(fn=cmd_uart)
    a = p.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
