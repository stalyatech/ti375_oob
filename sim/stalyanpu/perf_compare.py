"""Compare the measured cycle counts of the yolo layer tests with the
performance model.

For every descriptor of the compiled network the script builds the matching
performance model layer, asks the model for its cycle estimate and reads the
CYCLE_CNT line that tb_npu_net printed into the simulation log. The table
lists both numbers and their deviation; the M6 gate wants the total within
15 percent.

Usage:
    .venv-stalyanpu\\Scripts\\python sim/stalyanpu/perf_compare.py
    ... --qgraph .data/build/q_mse --logs sim/stalyanpu/sim_build
"""

from __future__ import annotations

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "ip", "stalyanpu", "py"))


def run_dims(stim_dir):
    import json
    path = os.path.join(stim_dir, "golden.json")
    if not os.path.isfile(path):
        return None
    with open(path) as fh:
        return json.load(fh).get("run_dims")


def measured_cycles(log_path):
    if not os.path.isfile(log_path):
        return None
    txt = open(log_path, encoding="utf-8", errors="replace").read()
    m = re.findall(r"CYCLE_CNT (\d+)", txt)
    if not m or "PASS" not in txt:
        return None
    return int(m[-1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qgraph", default=".data/build/q_mse")
    ap.add_argument("--logs", default="sim/stalyanpu/sim_build")
    ap.add_argument("--hwcfg", default="full2048")
    a = ap.parse_args()

    from stalyanpu.backend.compile import load_program
    from stalyanpu.hwcfg import load
    from stalyanpu.perf.layers import Layer
    from stalyanpu.perf.model import layer_cycles
    from stalyanpu.quant.qgraph import QGraph

    qg = QGraph.load(a.qgraph)
    hw = load(a.hwcfg)
    prog = load_program(qg, hw, 0x20000000, 0x28000000)

    rows = []
    for i, d in enumerate(prog.descriptors):
        f = {n: d.get(n) for n in ("opcode", "ic", "oc", "in_h", "in_w", "out_h", "out_w", "k", "stride")}
        dims = run_dims(os.path.join("sim", "stalyanpu", "stim", f"yolo_l{i}"))
        if dims:
            f.update(dims)
        op = f["opcode"]
        if op == 1:
            lay = Layer(prog.desc_names[i], "conv", f["ic"], f["oc"],
                        f["in_h"], f["in_w"], f["out_h"], f["out_w"],
                        f["k"], f["stride"], stem=(f["ic"] < 32))
        elif op == 2:
            lay = Layer(prog.desc_names[i], "maxpool5", f["ic"], f["ic"],
                        f["in_h"], f["in_w"], f["in_h"], f["in_w"], 5, 1)
        else:
            continue
        est = layer_cycles(lay, hw)
        meas = measured_cycles(os.path.join(a.logs, f"tb_yolo_l{i}.log"))
        rows.append((i, prog.desc_names[i], est.cycles, meas))

    print(f"{'idx':>4} {'model':>10} {'rtl':>10} {'dev%':>7}  name")
    t_model = t_rtl = n_meas = 0
    worst = 0.0
    for i, name, model, meas in rows:
        t_model += model
        if meas is None:
            print(f"{i:>4} {model:>10} {'-':>10} {'-':>7}  {name}")
            continue
        n_meas += 1
        t_rtl += meas
        dev = 100.0 * (meas-model) / model if model else 0.0
        worst = max(worst, abs(dev))
        print(f"{i:>4} {model:>10} {meas:>10} {dev:>6.1f}%  {name}")
    print()
    print(f"measured layers: {n_meas}/{len(rows)}")
    if n_meas:
        t_model_meas = sum(m for i, n, m, ms in rows if ms is not None)
        dev = 100.0 * (t_rtl-t_model_meas) / t_model_meas
        print(f"total model {t_model_meas} rtl {t_rtl} deviation {dev:.1f}% (gate 15%)")
        print(f"worst layer deviation {worst:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
