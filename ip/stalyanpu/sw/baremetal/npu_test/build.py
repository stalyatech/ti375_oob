"""Build the StalyaNPU bring-up test for the Ti375 hard SoC.

Usage:
    python build.py --set <ddr image dir> [--frames N] [--bsp <efx_hard_soc dir>]

The flags follow embedded_sw/efx_hard_soc/software/standalone (bsp.mk,
riscv64-unknown-elf.mk with soc.mk, standalone.mk) so the result matches
what the Efinity makefiles would produce. GNU make is not required. The
ddr image dir comes from ``python -m stalyanpu.board.ddrimage`` and holds
testset.h. Outputs land in build/: npu_test.elf, .bin, .asm, .map.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
TOOLCHAIN = "riscv-none-elf-"


def run(cmd):
    print(" ".join(cmd[:2]), "...", os.path.basename(cmd[-1]))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.exit(r.returncode)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--set", required=True, help="ddr image dir with testset.h")
    p.add_argument("--frames", type=int, default=10, help="frames in the timing loop")
    p.add_argument("--bsp", default=os.path.join(ROOT, "embedded_sw", "efx_hard_soc"))
    p.add_argument("--out", default=os.path.join(HERE, "build"))
    a = p.parse_args(argv)

    standalone = os.path.join(a.bsp, "software", "standalone")
    bsp_path = os.path.join(a.bsp, "bsp", "efinix", "EfxSapphireSoc")
    src = os.path.join(HERE, "src")
    os.makedirs(a.out, exist_ok=True)
    shutil.copy(os.path.join(a.set, "testset.h"), os.path.join(a.out, "testset.h"))

    march = "rv32imafdc_zicsr_zifencei"
    mabi = "ilp32d"
    cflags = [
        "-march=" + march, "-mabi=" + mabi, "-DUSE_GP", "-DSMP", "-g3", "-Og",
        "-DLOOP_FRAMES=%d" % a.frames,
        "-I" + os.path.join(bsp_path, "include"),
        "-I" + os.path.join(bsp_path, "app"),
        "-I" + os.path.join(standalone, "include"),
        "-I" + os.path.join(standalone, "driver"),
        "-I" + os.path.join(ROOT, "ip", "stalyanpu", "sw", "include"),
        "-I" + src,
        "-I" + a.out,
    ]
    sources = [
        os.path.join(src, "main.c"),
        os.path.join(src, "snpu_hal.c"),
        os.path.join(src, "crc32.c"),
        os.path.join(src, "log.c"),
        os.path.join(standalone, "common", "start.S"),
        os.path.join(standalone, "common", "trap.S"),
    ]
    objs = []
    for s in sources:
        o = os.path.join(a.out, os.path.splitext(os.path.basename(s))[0] + ".o")
        run([TOOLCHAIN + "gcc", "-c"] + cflags + ["-o", o, s])
        objs.append(o)

    elf = os.path.join(a.out, "npu_test.elf")
    ld = os.path.join(bsp_path, "linker", "default.ld")
    run([TOOLCHAIN + "gcc"] + cflags + ["-o", elf] + objs + [
        "-L" + os.path.join(standalone, "common"),
        "-specs=nosys.specs", "-lgcc", "-nostartfiles", "-ffreestanding",
        "-Wl,-Bstatic,-T,%s,-Map,%s,--print-memory-usage" % (ld, os.path.join(a.out, "npu_test.map")),
        "-lm", "-lc",
    ])
    run([TOOLCHAIN + "objcopy", "-O", "binary", elf, os.path.join(a.out, "npu_test.bin")])
    with open(os.path.join(a.out, "npu_test.asm"), "w") as fh:
        subprocess.run([TOOLCHAIN + "objdump", "-S", "-d", elf], stdout=fh, check=True)

    # gdb script: DDR image first, then the program.
    with open(os.path.join(a.out, "run.gdb"), "w", newline="\n") as fh:
        fh.write("set mem inaccessible-by-default off\n")
        fh.write("set arch riscv:rv32\n")
        fh.write("set remotetimeout 250\n")
        fh.write("target extended-remote localhost:3333\n")
        fh.write("monitor halt\n")
        fh.write("cd %s\n" % os.path.abspath(a.set).replace("\\", "/"))
        fh.write("source load.gdb\n")
        fh.write("cd %s\n" % os.path.abspath(a.out).replace("\\", "/"))
        fh.write("load\n")
        fh.write("continue\n")
    print("built", elf)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
