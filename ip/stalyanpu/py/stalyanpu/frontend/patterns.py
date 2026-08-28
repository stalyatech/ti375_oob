"""Constraint checks of the ONNX ops the accelerator accepts.

Each check returns None when the node is acceptable and a short reason
string otherwise. The reason ends up in the coverage report.
"""

from __future__ import annotations

from .onnx_import import OnnxModel, as_int_list, attr

CH_GROUP = 32


def check_conv(m: OnnxModel, node) -> str | None:
    if attr(node, "group", 1) != 1:
        return "grouped or depthwise conv"
    w = m.shape(node.input[1])
    if len(w) != 4:
        return "weight is not 4D"
    k = as_int_list(attr(node, "kernel_shape", list(w[2:])))
    if len(k) != 2 or k[0] != k[1] or k[0] not in (1, 3):
        return f"kernel {k} not 1x1 or 3x3"
    s = as_int_list(attr(node, "strides", [1, 1]))
    if len(s) != 2 or s[0] != s[1] or s[0] not in (1, 2):
        return f"stride {s} not 1 or 2"
    d = as_int_list(attr(node, "dilations", [1, 1]))
    if any(x != 1 for x in d):
        return f"dilation {d}"
    auto_pad = attr(node, "auto_pad", b"NOTSET")
    if isinstance(auto_pad, bytes):
        auto_pad = auto_pad.decode()
    pads = as_int_list(attr(node, "pads", [0, 0, 0, 0]))
    want = k[0] // 2
    if auto_pad == "NOTSET":
        if pads != [want] * 4:
            return f"pads {pads} not symmetric {want}"
    elif auto_pad not in ("SAME_UPPER", "SAME_LOWER"):
        return f"auto_pad {auto_pad}"
    if not m.is_const(node.input[1]):
        return "weights are not constant"
    if len(node.input) > 2 and node.input[2] and not m.is_const(node.input[2]):
        return "bias is not constant"
    return None


def check_maxpool(m: OnnxModel, node) -> str | None:
    k = as_int_list(attr(node, "kernel_shape"))
    s = as_int_list(attr(node, "strides", [1, 1]))
    pads = as_int_list(attr(node, "pads", [0, 0, 0, 0]))
    if k != [5, 5] or s != [1, 1] or pads != [2, 2, 2, 2]:
        return f"maxpool k={k} s={s} pads={pads}, only 5x5 s1 p2 (SPPF)"
    if attr(node, "ceil_mode", 0):
        return "ceil_mode"
    return None


def check_resize(m: OnnxModel, node) -> str | None:
    mode = attr(node, "mode", b"nearest")
    if isinstance(mode, bytes):
        mode = mode.decode()
    if mode != "nearest":
        return f"resize mode {mode}"
    in_shape = m.shape(node.input[0])
    out_shape = m.shape(node.output[0])
    scales = m.const(node.input[2]) if len(node.input) > 2 and node.input[2] else None
    sizes = m.const(node.input[3]) if len(node.input) > 3 and node.input[3] else None
    if scales is not None and len(scales) == 4:
        if list(scales) != [1.0, 1.0, 2.0, 2.0]:
            return f"resize scales {list(scales)}"
    elif sizes is not None and len(in_shape) == 4:
        if list(sizes)[2:] != [2 * in_shape[2], 2 * in_shape[3]]:
            return f"resize sizes {list(sizes)}"
    elif len(in_shape) == 4 and len(out_shape) == 4:
        if (out_shape[2], out_shape[3]) != (2 * in_shape[2], 2 * in_shape[3]):
            return "resize is not 2x"
    else:
        return "resize scale unknown"
    return None


def check_concat(m: OnnxModel, node) -> str | None:
    if attr(node, "axis", 1) != 1:
        return "concat axis is not the channel axis"
    for name in node.input[:-1]:
        sh = m.shape(name)
        if len(sh) < 2:
            return f"unknown shape of {name}"
        if sh[1] % CH_GROUP:
            return f"concat input {name} has {sh[1]} channels, needs a multiple of {CH_GROUP}"
    return None


def check_split(m: OnnxModel, node) -> str | None:
    if attr(node, "axis", 0) != 1:
        return "split axis is not the channel axis"
    sizes = as_int_list(attr(node, "split"))
    if not sizes and len(node.input) > 1:
        sizes = as_int_list(m.const(node.input[1]))
    if not sizes:
        n = len(node.output)
        c = m.shape(node.input[0])[1]
        sizes = [c // n] * n
    for s in sizes[:-1]:
        if s % CH_GROUP:
            return f"split size {s} is not a multiple of {CH_GROUP}"
    return None


def silu_pair(m: OnnxModel, node):
    """For a Sigmoid node return the Mul node completing x * sigmoid(x)."""
    if node.op_type != "Sigmoid":
        return None
    x = node.input[0]
    cons = m.consumers.get(node.output[0], [])
    if len(cons) != 1 or cons[0].op_type != "Mul":
        return None
    mul = cons[0]
    if set(mul.input) != {x, node.output[0]}:
        return None
    return mul


CHECKS = {
    "Conv": check_conv,
    "MaxPool": check_maxpool,
    "Resize": check_resize,
    "Concat": check_concat,
    "Split": check_split,
}
