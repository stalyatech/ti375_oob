"""Command line entry point: ``python -m stalyanpu <command>``.

Commands:
    perf        run the analytic performance model on the YOLOv8s layer table
    lower       import an ONNX model, lower it and print the coverage report
    gen-header  write (or check) the generated C header of the ISA
    export      export a YOLOv8 checkpoint to ONNX (needs the export extra)
    calibrate   lower, calibrate on COCO images and write the quantized graph
    eval        COCO mAP of the FP32 model and of the INT8 reference model
    check-tail  compare the numpy detection tail with the ONNX model output
    compile     emit the descriptor blob (frame.bin, alloc.json), optionally check it
    golden      write simulation vectors for the whole net or one descriptor
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time


def _progress(total, label):
    t0 = time.time()

    def cb(i):
        if i == total or i % 50 == 0:
            print(f"  {label}: {i}/{total} ({time.time() - t0:.0f} s)", flush=True)
    return cb


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


def cmd_export(args):
    from .frontend.onnx_export import export_yolov8

    print("wrote " + export_yolov8(args.weights, args.out, args.height, args.width, args.opset))
    return 0


def cmd_calibrate(args):
    import onnx

    from .eval.coco import calibration_images, image_list
    from .frontend import lower_onnx
    from .frontend.onnx_import import OnnxModel
    from .quant import build_qgraph, choose_qparams
    from .quant.calib import collect_stats
    from .quant.qgraph import QuantParams

    model = onnx.load(args.model)
    g, rep = lower_onnx(model, cut_tensors=args.cut)
    print(rep.text())
    if not rep.ok:
        return 1
    paths = image_list(args.images, args.ann, args.ncalib, seed=args.seed)
    print(f"calibrating on {len(paths)} images, percentile {args.percentile}")
    stats = collect_stats(model, g, calibration_images(paths, args.height, args.width),
                          percentile=args.percentile, progress=_progress(len(paths), "calib"))
    fixed = {g.inputs[0]: QuantParams(1.0 / 255.0, -128)}
    overrides = {}
    if args.outputs_method:
        overrides = {o: args.outputs_method for o in g.outputs}
    tq, rrep = choose_qparams(g, stats, method=args.method, fixed=fixed, overrides=overrides)
    print(rrep.text())
    qg = build_qgraph(g, OnnxModel(model), tq, meta={
        "model": os.path.abspath(args.model), "height": args.height, "width": args.width,
        "ncalib": len(paths), "method": args.method, "percentile": args.percentile})
    qg.save(args.out)
    with open(os.path.join(args.out, "calib_stats.json"), "w") as fh:
        json.dump({n: s.as_dict() for n, s in stats.items()}, fh, indent=1)
    print("wrote " + args.out)
    return 0


def cmd_eval(args):
    from .eval.coco import Fp32Head, Int8Head, coco_map, image_list, run_detections
    from .quant.qgraph import QGraph

    paths = image_list(args.images, args.ann, args.n, seed=args.seed)
    ids = [i for i, _ in paths]
    out = {}
    if args.qgraph:
        qg = QGraph.load(args.qgraph)
        h, w = qg.meta.get("height", args.height), qg.meta.get("width", args.width)
        model = args.model or qg.meta.get("model")
        cut = qg.graph.outputs
    else:
        from .frontend import lower_onnx
        model = args.model
        g, _ = lower_onnx(model)
        cut = g.outputs
        h, w = args.height, args.width
    if not args.skip_fp32:
        print(f"FP32 on {len(paths)} images")
        res = run_detections(Fp32Head(model, cut), paths, h, w, progress=_progress(len(paths), "fp32"))
        out["fp32"] = coco_map(res, args.ann, ids)
    if args.qgraph:
        print(f"INT8 reference on {len(paths)} images")
        res = run_detections(Int8Head(qg), paths, h, w, progress=_progress(len(paths), "int8"))
        out["int8"] = coco_map(res, args.ann, ids)
    print(json.dumps(out, indent=1))
    if "fp32" in out and "int8" in out:
        drop = out["fp32"]["map50_95"] - out["int8"]["map50_95"]
        print(f"mAP50-95 drop: {100 * drop:.2f} points")
    if args.report:
        with open(args.report, "w") as fh:
            json.dump({"n": len(paths), "results": out}, fh, indent=1)
    return 0


def _load_input(args, qg):
    """Input image as CHW int8 for the quantized graph."""
    import numpy as np

    from .refmodel.runner import QRunner

    name = qg.graph.inputs[0]
    c, h, w = qg.graph.tensors[name].shape[1:]
    runner = QRunner(qg)
    if args.image:
        from PIL import Image

        from .eval.preprocess import preprocess
        x = preprocess(Image.open(args.image), h, w)[0][0]
    else:
        rng = np.random.default_rng(args.seed)
        x = rng.random((c, h, w), dtype=np.float32)
    return runner.quantize_input(name, x)


def cmd_compile(args):
    from .backend.compile import check, load_program, write_build
    from .hwcfg import load
    from .quant.qgraph import QGraph

    qg = QGraph.load(args.qgraph)
    hw = load(args.hwcfg)
    prog = load_program(qg, hw, args.base, args.scratch)
    write_build(prog, args.out)
    print(f"descriptors {len(prog.descriptors)}, blob {prog.size / 1e6:.2f} MB "
          f"(params {len(prog.params) / 1e6:.2f} MB), scratch {prog.alloc.scratch_size / 1e6:.2f} MB, "
          f"buffers {len(prog.alloc.buffers)}, virtual concats {len(prog.alloc.virtual_concat)}")
    print("wrote " + args.out)
    if args.check:
        ok, diff = check(qg, hw, prog, _load_input(args, qg))
        bad = {k: v for k, v in diff.items() if v}
        print("interp == runner: " + ("OK" if ok else f"MISMATCH {bad}"))
        return 0 if ok else 1
    return 0


def cmd_golden(args):
    from .backend.compile import load_program, make_memory
    from .golden.vectors import write_layer_vectors, write_net_vectors
    from .hwcfg import load
    from .quant.qgraph import QGraph

    qg = QGraph.load(args.qgraph)
    hw = load(args.hwcfg)
    prog = load_program(qg, hw, args.base, args.scratch)
    x = _load_input(args, qg)
    mem = make_memory(prog, x, qg.tq[prog.input_name].zp)
    if args.layer is None:
        meta = write_net_vectors(prog, hw, mem, args.out, dump_all=args.dump_all)
    else:
        meta = write_layer_vectors(prog, hw, mem, args.layer, args.out)
    from .golden.demo import write_regions
    write_regions(args.out)
    print(json.dumps(meta))
    print("wrote " + args.out)
    return 0


def cmd_check_tail(args):
    """Feed one image through the ONNX model and compare the boxes decoded by
    the numpy tail from the six cut tensors with the model's own output."""
    import numpy as np
    import onnx
    import onnxruntime as ort
    from PIL import Image

    from .eval.coco import Fp32Head
    from .eval.preprocess import preprocess
    from .frontend import lower_onnx
    from .refmodel import tail

    model = onnx.load(args.model)
    g, _ = lower_onnx(model)
    head = Fp32Head(model, g.outputs)
    x, _, _, _ = preprocess(Image.open(args.image), args.height, args.width)
    boxes, scores = tail.decode(head(x))
    sess = ort.InferenceSession(model.SerializeToString(), providers=["CPUExecutionProvider"])
    full = sess.run(None, {sess.get_inputs()[0].name: x})[0][0]      # [84, N] xywh + scores
    xywh = full[:4].T
    ref_boxes = np.stack([xywh[:, 0] - xywh[:, 2] / 2, xywh[:, 1] - xywh[:, 3] / 2,
                          xywh[:, 0] + xywh[:, 2] / 2, xywh[:, 1] + xywh[:, 3] / 2], axis=1)
    ref_scores = full[4:].T
    print("anchors", boxes.shape[0], "vs", ref_boxes.shape[0])
    print("max box error (px):", float(np.abs(boxes-ref_boxes).max()))
    print("max score error   :", float(np.abs(scores-ref_scores).max()))
    det = tail.nms(boxes, scores, conf_thres=0.25)
    print(f"{det.shape[0]} detections above 0.25:")
    for row in det[:10]:
        print("  ", [round(float(v), 1) for v in row])
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

    p = sub.add_parser("export", help="export YOLOv8 weights to ONNX")
    p.add_argument("--weights", default="yolov8s.pt")
    p.add_argument("--out", default=None)
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=384)
    p.add_argument("--opset", type=int, default=13)
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("calibrate", help="calibrate and write the quantized graph")
    p.add_argument("model")
    p.add_argument("--images", required=True, help="COCO val2017 image directory")
    p.add_argument("--ann", required=True, help="instances_val2017.json")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--ncalib", type=int, default=256)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=384)
    p.add_argument("--method", default="mse", choices=["mse", "minmax", "percentile"],
                   help="range selection; mse gives the best mAP on YOLOv8s, see docs/stalyanpu/accuracy-report.md")
    p.add_argument("--percentile", type=float, default=99.99)
    p.add_argument("--outputs-method", default=None, choices=[None, "mse", "percentile", "minmax"])
    p.add_argument("--cut", nargs="*", default=None)
    p.set_defaults(func=cmd_calibrate)

    p = sub.add_parser("eval", help="COCO mAP of FP32 and INT8")
    p.add_argument("--model", default=None)
    p.add_argument("--qgraph", default=None, help="directory written by calibrate")
    p.add_argument("--images", required=True)
    p.add_argument("--ann", required=True)
    p.add_argument("--n", type=int, default=500)
    p.add_argument("--seed", type=int, default=1, help="use a different seed than calibrate")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=384)
    p.add_argument("--skip-fp32", action="store_true")
    p.add_argument("--report", default=None, help="write results as JSON")
    p.set_defaults(func=cmd_eval)

    def addr_args(p):
        p.add_argument("--hwcfg", default="full2048")
        p.add_argument("--base", type=lambda v: int(v, 0), default=0x20000000, help="blob load address")
        p.add_argument("--scratch", type=lambda v: int(v, 0), default=0x28000000, help="activation scratch address")
        p.add_argument("--image", default=None, help="input image, random data when omitted")
        p.add_argument("--seed", type=int, default=0)

    p = sub.add_parser("compile", help="emit the descriptor blob from a quantized graph")
    p.add_argument("--qgraph", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--check", action="store_true", help="run the interpreter against the reference runner")
    addr_args(p)
    p.set_defaults(func=cmd_compile)

    p = sub.add_parser("golden", help="write simulation vectors (mem.hex, golden.hex, golden.json)")
    p.add_argument("--qgraph", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--layer", type=int, default=None, help="descriptor index for a single layer set")
    p.add_argument("--dump-all", action="store_true", help="net set: add every descriptor output as a region")
    addr_args(p)
    p.set_defaults(func=cmd_golden)

    p = sub.add_parser("check-tail", help="compare the numpy tail with the ONNX head output")
    p.add_argument("model")
    p.add_argument("image")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=384)
    p.set_defaults(func=cmd_check_tail)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
