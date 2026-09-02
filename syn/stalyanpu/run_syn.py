"""Run the Efinity flow on a StalyaNPU synthesis project and print a summary.

Usage:
    python syn/stalyanpu/run_syn.py conv [--flow map|pnr|all]
    python syn/stalyanpu/run_syn.py top  [--flow map|pnr|all]

The projects live in syn/stalyanpu/<name>/ and wrap the engine or the full
accelerator with a shift register stimulus (see rtl/). The summary lists the
mapped primitives, the memory mapping and the timing of the clk domain.
"""
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EFINITY = os.environ.get("EFINITY_HOME", "C:/Programs/Efinity/2025.2")
PROJECTS = {"chain": "snpu_chain", "conv": "snpu_conv", "top": "snpu_top"}


def run(name, flow, extra):
    prj = PROJECTS[name]
    d = os.path.join(HERE, name)
    setup = os.path.join(EFINITY, "bin", "setup.bat").replace("/", "\\")
    cmd = f'cmd /c "call {setup} && efx_run {prj} --prj -f {flow} {extra}"'
    t0 = time.time()
    p = subprocess.run(cmd, cwd=d, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, errors="replace")
    dt = time.time() - t0
    log = os.path.join(d, f"run_{flow}.log")
    open(log, "w", encoding="utf-8").write(p.stdout)
    print(f"[{flow}] exit {p.returncode} in {dt:.0f}s, log {log}")
    if p.returncode != 0:
        tail = [l for l in p.stdout.splitlines() if re.search(r"ERROR|Error|error", l)]
        print("\n".join(tail[-20:]))
    return p.returncode


def summary_map(name):
    prj = PROJECTS[name]
    path = os.path.join(HERE, name, "outflow", f"{prj}.map.rpt")
    if not os.path.isfile(path):
        print("no map report")
        return
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"### ### Resource Summary \(begin\).*?### ### Resource Summary \(end\)", txt, re.S)
    if m:
        print(m.group(0))
    m = re.search(r"### ### Memory Mapping Report \(begin\).*?### ### Memory Mapping Report \(end\)", txt, re.S)
    if m:
        blocks = re.findall(r"^\d+\. (\S+) .*?\n((?:\t.*\n)+)", m.group(0), re.M)
        print("Memory mapping:")
        for inst, body in blocks:
            n = body.count("EFX_RAM10")
            print(f"  {inst}: {n} RAM10")
    warns = re.findall(r"^.*(?:WARNING|Warning).*$", txt, re.M)
    keep = [w for w in warns if re.search(r"latch|bit.?blast|logic for|not inferred|removed|unconnected|undriven", w, re.I)]
    if keep:
        print("Notable warnings:")
        for w in keep[:40]:
            print("  " + w.strip()[:160])


def summary_timing(name):
    prj = PROJECTS[name]
    path = os.path.join(HERE, name, "outflow", f"{prj}.timing.rpt")
    if not os.path.isfile(path):
        print("no timing report")
        return
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"Maximum possible analyzed clocks frequency.*?Geomean", txt, re.S)
    if m:
        print(m.group(0).rsplit("\n", 1)[0])
    m = re.search(r"Setup \(Max\) Clock Relationship.*?\n\n", txt, re.S)
    if m:
        print(m.group(0).rstrip())
    m = re.search(r"Hold \(Min\) Clock Relationship.*?\n\n", txt, re.S)
    if m:
        print(m.group(0).rstrip())


def summary_place(name):
    prj = PROJECTS[name]
    path = os.path.join(HERE, name, "outflow", f"{prj}.place.rpt")
    if not os.path.isfile(path):
        return
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"Resource Usage Summary \(begin\).*?Resource Usage Summary \(end\)", txt, re.S)
    if m:
        print(m.group(0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", choices=sorted(PROJECTS))
    ap.add_argument("--flow", default="all", choices=["map", "pnr", "all", "none"])
    ap.add_argument("--extra", default="", help="extra efx_run arguments")
    a = ap.parse_args()
    rc = 0
    if a.flow in ("map", "all"):
        rc = run(a.name, "map", a.extra)
        summary_map(a.name)
        if rc:
            sys.exit(rc)
    if a.flow in ("pnr", "all"):
        rc = run(a.name, "interface", a.extra)
        if rc:
            sys.exit(rc)
        rc = run(a.name, "pnr", a.extra)
        summary_place(a.name)
        summary_timing(a.name)
    if a.flow == "none":
        summary_map(a.name)
        summary_place(a.name)
        summary_timing(a.name)
    sys.exit(rc)


if __name__ == "__main__":
    main()
