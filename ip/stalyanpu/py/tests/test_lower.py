"""Lowering test on a synthetic ONNX graph with every supported pattern."""

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

from stalyanpu.frontend import lower_onnx


def _conv(name, x, cin, cout, k, s, inits):
    w = numpy_helper.from_array(np.zeros((cout, cin, k, k), np.float32), name + ".w")
    b = numpy_helper.from_array(np.zeros((cout,), np.float32), name + ".b")
    inits += [w, b]
    return helper.make_node("Conv", [x, w.name, b.name], [name], name=name,
                            kernel_shape=[k, k], strides=[s, s], pads=[k // 2] * 4)


def _silu(name, x):
    return [
        helper.make_node("Sigmoid", [x], [name + ".sig"], name=name + ".sig"),
        helper.make_node("Mul", [x, name + ".sig"], [name], name=name),
    ]


def make_demo_model():
    inits = []
    nodes = []
    nodes.append(_conv("c0", "img", 3, 64, 3, 2, inits))
    nodes += _silu("a0", "c0")
    nodes.append(helper.make_node("Split", ["a0"], ["s0", "s1"], name="split", axis=1, split=[32, 32]))
    nodes.append(_conv("c1", "s1", 32, 32, 3, 1, inits))
    nodes += _silu("a1", "c1")
    nodes.append(helper.make_node("Add", ["a1", "s1"], ["r1"], name="add"))
    nodes.append(helper.make_node("Concat", ["s0", "s1", "r1"], ["cat"], name="cat", axis=1))
    nodes.append(_conv("c2", "cat", 96, 64, 1, 1, inits))
    nodes += _silu("a2", "c2")
    scales = numpy_helper.from_array(np.array([1, 1, 2, 2], np.float32), "scales")
    inits.append(scales)
    nodes.append(helper.make_node("Resize", ["a2", "", "scales"], ["up"], name="up", mode="nearest"))
    nodes.append(helper.make_node("MaxPool", ["up"], ["mp"], name="mp", kernel_shape=[5, 5], strides=[1, 1], pads=[2, 2, 2, 2]))
    nodes.append(_conv("c3", "mp", 64, 80, 1, 1, inits))
    # CPU tail
    shape = numpy_helper.from_array(np.array([1, 80, -1], np.int64), "shape")
    inits.append(shape)
    nodes.append(helper.make_node("Reshape", ["c3", "shape"], ["flat"], name="flat"))
    nodes.append(helper.make_node("Softmax", ["flat"], ["out"], name="softmax", axis=1))
    graph = helper.make_graph(
        nodes, "demo",
        [helper.make_tensor_value_info("img", TensorProto.FLOAT, [1, 3, 32, 64])],
        [helper.make_tensor_value_info("out", TensorProto.FLOAT, [1, 80, 32 * 64])],
        initializer=inits,
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 8
    return model


def test_lowering_partitions_and_fuses():
    g, rep = lower_onnx(make_demo_model())
    assert rep.ok, rep.text()
    kinds = g.op_counts()
    assert kinds["CONV"] == 4
    assert kinds["SPLIT"] == 1 and kinds["CONCAT"] == 1
    assert kinds["UPSAMPLE2"] == 1 and kinds["MAXPOOL5"] == 1
    assert "ADD" not in kinds and "SILU" not in kinds
    assert rep.fused_silu == 3 and rep.fused_residual == 1
    convs = {op.name: op for op in g.ops if op.kind == "CONV"}
    assert convs["c0"].attrs["silu"] and convs["c0"].attrs["s"] == 2
    assert convs["c1"].attrs["residual"] == "s1"
    assert not convs["c3"].attrs["silu"]
    assert g.outputs == ["c3"]
    assert rep.cpu_counts == {"Reshape": 1, "Softmax": 1}
    assert ("flat", "Reshape") in rep.unsupported_frontier


def test_concat_alignment_is_enforced():
    model = make_demo_model()
    # Change the split to 16/48: the concat offsets are no longer 32 aligned.
    for node in model.graph.node:
        if node.op_type == "Split":
            for a in node.attribute:
                if a.name == "split":
                    a.ints[:] = [16, 48]
    g, rep = lower_onnx(model)
    assert not rep.ok
    assert any("multiple of 32" in r for _, r in rep.frontier_failures)


def test_explicit_cut():
    g, rep = lower_onnx(make_demo_model(), cut_tensors=["a2"])
    assert g.outputs == ["c2"]
    assert "Resize" in rep.cpu_counts
