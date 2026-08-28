"""Command line entry point: ``python -m stalyanpu <command>``.

Commands:
    perf        run the analytic performance model on the YOLOv8s layer table
    lower       import an ONNX model, lower it and print the coverage report
    gen-header  write (or check) the generated C header of the ISA
"""

from __future__ import annotations

import argparse
import sys


def cmd_perf(args):
    from .hwcfg import load
    from .perf import estimate, yolov8s_layers
    from .perf.report import group_summary, summary, table

    hw = load(args.hwcfg)
    if args.ddr_bw is not None:
        hw.ddr_bw_gbps = args.ddr_bw
    if args.clk is not None:
        hw.clk_mhz = args.clk
    layers = yolov8s_layers(args.height, args.width)
    est = estimate(layers, hw, cpu_ms=args.cpu_ms)
    if not args.quiet:
        print(table(est, markdown=args.markdown))
        print()
        print(group_summary(est))
        print()
    print(summary(est))
    return 0


def cmd_lower(args):
    from .frontend import lower_onnx

    g, report = lower_onnx(args.model, cut_tensors=args.cut)
    print(report.text())
    if args.dump:
        print()
        print(g.text())
    return 0 if report.ok else 1


def cmd_gen_header(args):
    from .backend.gen_header import DEFAULT_OUT, check_header, write_header

    path = args.out or DEFAULT_OUT
    if args.check:
        ok = check_header(path)
        print(("up to date: " if ok else "OUT OF DATE: ") + path)
        return 0 if ok else 1
    print("wrote " + write_header(path))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="stalyanpu", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("perf", help="analytic performance model")
    p.add_argument("--hwcfg", default="full2048", help="preset name or JSON file")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=384)
    p.add_argument("--ddr-bw", type=float, default=None, help="effective DDR bandwidth in GB/s")
    p.add_argument("--clk", type=float, default=None, help="clock in MHz")
    p.add_argument("--cpu-ms", type=float, default=4.0, help="CPU post processing time per frame")
    p.add_argument("--markdown", action="store_true")
    p.add_argument("--quiet", action="store_true", help="summary only")
    p.set_defaults(func=cmd_perf)

    p = sub.add_parser("lower", help="lower an ONNX model and report op coverage")
    p.add_argument("model")
    p.add_argument("--cut", nargs="*", default=None, help="tensor names that end the NPU graph")
    p.add_argument("--dump", action="store_true", help="print the lowered graph")
    p.set_defaults(func=cmd_lower)

    p = sub.add_parser("gen-header", help="generate the C header from isa.py")
    p.add_argument("--out", default=None)
    p.add_argument("--check", action="store_true", help="exit 1 if the file is stale")
    p.set_defaults(func=cmd_gen_header)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
