#!/usr/bin/env python
"""Run StalyaNPU testbenches with Icarus Verilog.

Usage:
    python sim/stalyanpu/run_sim.py all|unit|<test> [<test> ...] [options]

Options:
    --seed N       random seed passed as +SEED=N (default 1)
    --behav        use the behavioural DSP twin (-DSNPU_SIM_BEHAV) instead of
                   the Efinity DSP48 simulation model
    --dump         write an fst waveform next to the vvp file
    --plusargs ... extra plusargs, for example --plusargs +CYCLES=1000
    -j N           run N tests in parallel
    --list         print the registered tests and exit

A test passes when its log contains exactly one "<top>: PASS" line and no
line starting with "FAIL". The exit code is the number of failed tests.

iverilog options must come before file names, this build does not permute
its arguments.
"""

import argparse
import concurrent.futures
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

from tests import TESTS  # noqa: E402

DSP_MODEL = os.environ.get(
    "SNPU_DSP_MODEL",
    r"C:/Programs/Efinity/2025.2/sim_models/verilog/efx_dsp48.v",
)
BUILD = os.path.join(HERE, "sim_build")


def tool(name):
    return os.environ.get(name.upper(), name)


def run_one(name, args):
    spec = TESTS[name]
    top = spec["top"]
    os.makedirs(BUILD, exist_ok=True)
    vvp = os.path.join(BUILD, name + ".vvp")
    log = os.path.join(BUILD, name + ".log")

    cmd = [tool("iverilog"), "-g2012", "-s", top, "-o", vvp,
           "-I", os.path.join(ROOT, "ip", "stalyanpu", "rtl"),
           "-I", os.path.join(HERE, "common")]
    for d in spec.get("defines", []):
        cmd.append("-D" + d)
    if args.behav:
        cmd.append("-DSNPU_SIM_BEHAV")
    for k, v in spec.get("params", {}).items():
        cmd.append(f"-P{top}.{k}={v}")
    files = []
    if spec.get("needs_dsp_model") and not args.behav:
        files.append(DSP_MODEL)
    files += [os.path.join(ROOT, f) for f in spec["files"]]
    cmd += files

    t0 = time.time()
    with open(log, "w") as fh:
        fh.write("$ " + " ".join(cmd) + "\n")
        fh.flush()
        rc = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, cwd=ROOT).returncode
        if rc != 0:
            return name, False, time.time() - t0, "compile error, see " + log
        run = [tool("vvp"), vvp]
        if args.dump:
            run.append("-fst")
        run.append(f"+SEED={args.seed}")
        run += spec.get("plusargs", [])
        run += args.plusargs
        fh.write("$ " + " ".join(run) + "\n")
        fh.flush()
        rc = subprocess.run(run, stdout=fh, stderr=subprocess.STDOUT, cwd=ROOT).returncode

    with open(log) as fh:
        text = fh.read()
    passes = [l for l in text.splitlines() if l.startswith(top + ": PASS")]
    fails = [l for l in text.splitlines() if l.startswith("FAIL") or l.startswith(top + ": FAIL")]
    ok = rc == 0 and len(passes) == 1 and not fails
    detail = passes[0] if ok else (fails[0] if fails else f"no PASS line (rc={rc}), see {log}")
    return name, ok, time.time() - t0, detail


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tests", nargs="*", default=["all"])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--behav", action="store_true")
    ap.add_argument("--dump", action="store_true")
    ap.add_argument("--plusargs", nargs="*", default=[])
    ap.add_argument("-j", type=int, default=1)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for n, s in TESTS.items():
            print(f"{n:24s} group={s.get('group', '')} top={s['top']}")
        return 0

    selected = []
    for t in args.tests:
        if t == "all":
            selected += list(TESTS)
        elif t in TESTS:
            selected.append(t)
        else:
            group = [n for n, s in TESTS.items() if s.get("group") == t]
            if not group:
                print(f"unknown test or group: {t}")
                return 1
            selected += group
    selected = list(dict.fromkeys(selected))

    results = []
    if args.j > 1:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.j) as ex:
            results = list(ex.map(lambda n: run_one(n, args), selected))
    else:
        for n in selected:
            r = run_one(n, args)
            print(f"{r[0]:24s} {'PASS' if r[1] else 'FAIL':4s} {r[2]:7.1f}s  {r[3]}")
            results.append(r)
    if args.j > 1:
        for r in results:
            print(f"{r[0]:24s} {'PASS' if r[1] else 'FAIL':4s} {r[2]:7.1f}s  {r[3]}")

    failed = [r for r in results if not r[1]]
    print(f"{len(results) - len(failed)}/{len(results)} passed")
    return len(failed)


if __name__ == "__main__":
    sys.exit(main())
