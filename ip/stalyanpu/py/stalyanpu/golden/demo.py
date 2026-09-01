"""Vector sets of the synthetic demo network for the descriptor driven
benches (tb_npu_net): the graph of tests/test_lower.py quantized on random
data, compiled for a given hardware preset and executed by the interpreter.

    python -m stalyanpu.golden.demo net <out_dir> [hwcfg]
    python -m stalyanpu.golden.demo layer <out_dir> <index> [hwcfg]

Also writes regions.txt ("base bytes" per golden region) and run.txt with
the descriptor list address and count for the bench plusargs.
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np

from ..backend.compile import load_program, make_memory
from ..hwcfg import load
from .vectors import write_layer_vectors, write_net_vectors

BASE = 0x20000000
SCRATCH = 0x28000000


def demo_qgraph():
    from onnx import numpy_helper

    from ..frontend import lower_onnx
    from ..frontend.onnx_import import OnnxModel
    from ..quant import build_qgraph, choose_qparams
    from ..quant.calib import collect_stats
    from ..quant.qgraph import QuantParams

    # Local copy of the demo graph builder so the package does not import the
    # test suite.
    import onnx
    from onnx import TensorProto, helper

    def conv(name, x, cin, cout, k, s, inits):
        w = numpy_helper.from_array(np.zeros((cout, cin, k, k), np.float32), name + ".w")
        b = numpy_helper.from_array(np.zeros((cout,), np.float32), name + ".b")
        inits += [w, b]
        return helper.make_node("Conv", [x, w.name, b.name], [name], name=name,
                                kernel_shape=[k, k], strides=[s, s], pads=[k // 2] * 4)

    def silu(name, x):
        return [helper.make_node("Sigmoid", [x], [name + ".sig"], name=name + ".sig"),
                helper.make_node("Mul", [x, name + ".sig"], [name], name=name)]

    inits, nodes = [], []
    nodes.append(conv("c0", "img", 3, 64, 3, 2, inits))
    nodes += silu("a0", "c0")
    inits.append(numpy_helper.from_array(np.array([32, 32], np.int64), "split_sizes"))
    nodes.append(helper.make_node("Split", ["a0", "split_sizes"], ["s0", "s1"], name="split", axis=1))
    nodes.append(conv("c1", "s1", 32, 32, 3, 1, inits))
    nodes += silu("a1", "c1")
    nodes.append(helper.make_node("Add", ["a1", "s1"], ["r1"], name="add"))
    nodes.append(helper.make_node("Concat", ["s0", "s1", "r1"], ["cat"], name="cat", axis=1))
    nodes.append(conv("c2", "cat", 96, 64, 1, 1, inits))
    nodes += silu("a2", "c2")
    inits.append(numpy_helper.from_array(np.array([1, 1, 2, 2], np.float32), "scales"))
    nodes.append(helper.make_node("Resize", ["a2", "", "scales"], ["up"], name="up", mode="nearest"))
    nodes.append(helper.make_node("MaxPool", ["up"], ["mp"], name="mp", kernel_shape=[5, 5], strides=[1, 1], pads=[2, 2, 2, 2]))
    nodes.append(conv("c3", "mp", 64, 80, 1, 1, inits))
    inits.append(numpy_helper.from_array(np.array([1, 80, -1], np.int64), "shape"))
    nodes.append(helper.make_node("Reshape", ["c3", "shape"], ["flat"], name="flat"))
    nodes.append(helper.make_node("Softmax", ["flat"], ["out"], name="softmax", axis=1))
    graph = helper.make_graph(nodes, "demo",
                              [helper.make_tensor_value_info("img", TensorProto.FLOAT, [1, 3, 32, 64])],
                              [helper.make_tensor_value_info("out", TensorProto.FLOAT, [1, 80, 32 * 64])],
                              initializer=inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 8

    rng = np.random.default_rng(11)
    for init in model.graph.initializer:
        if init.name.endswith(".w"):
            arr = numpy_helper.to_array(init)
            fan_in = np.prod(arr.shape[1:])
            init.CopyFrom(numpy_helper.from_array(rng.normal(0, 1.0 / np.sqrt(fan_in), arr.shape).astype(np.float32), init.name))
        elif init.name.endswith(".b"):
            arr = numpy_helper.to_array(init)
            init.CopyFrom(numpy_helper.from_array(rng.normal(0, 0.1, arr.shape).astype(np.float32), init.name))
    g, rep = lower_onnx(model)
    assert rep.ok
    images = [rng.random((1, 3, 32, 64), dtype=np.float32) for _ in range(6)]
    stats = collect_stats(model, g, images)
    tq, _ = choose_qparams(g, stats, method="minmax", fixed={g.inputs[0]: QuantParams(1.0 / 255.0, -128)})
    return build_qgraph(g, OnnxModel(model), tq), images[0][0]


def write_regions(out_dir: str) -> None:
    with open(os.path.join(out_dir, "golden.json")) as fh:
        doc = json.load(fh)
    with open(os.path.join(out_dir, "regions.txt"), "w", newline="\n") as fh:
        for r in doc["regions"]:
            fh.write(f"{r['base']:08x} {r['bytes']}\n")
    with open(os.path.join(out_dir, "run.txt"), "w", newline="\n") as fh:
        fh.write(f"+DESC_BASE={doc['desc_base']:08x} +DESC_COUNT={doc['desc_count']}\n")


def main(argv):
    kind, out_dir = argv[0], argv[1]
    hwname = "small512"
    index = None
    if kind == "layer":
        index = int(argv[2])
        if len(argv) > 3:
            hwname = argv[3]
    elif len(argv) > 2:
        hwname = argv[2]
    hw = load(hwname)
    qg, x = demo_qgraph()
    prog = load_program(qg, hw, BASE, SCRATCH)
    from ..refmodel.runner import QRunner
    xq = QRunner(qg).quantize_input(prog.input_name, x)
    mem = make_memory(prog, xq, qg.tq[prog.input_name].zp)
    if kind == "net":
        meta = write_net_vectors(prog, hw, mem, out_dir, dump_all=True)
    else:
        meta = write_layer_vectors(prog, hw, mem, index, out_dir)
    write_regions(out_dir)
    print(json.dumps(meta))
    print(f"scratch {prog.alloc.scratch_size} bytes, blob {prog.size} bytes, descriptors {len(prog.descriptors)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
