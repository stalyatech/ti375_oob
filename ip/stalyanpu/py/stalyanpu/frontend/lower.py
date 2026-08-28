"""Lower an ONNX graph to the accelerator op set.

Partition: nodes are visited in graph order. A node runs on the NPU when its
type is supported, its constraints hold and all of its non constant inputs
are produced on the NPU (or are graph inputs). Everything else runs on the
CPU. NPU tensors consumed by CPU nodes, or listed as graph outputs, become
the NPU outputs. The optional ``cut_tensors`` argument forces the cut at the
named tensors.

Fusion after partition:
    Sigmoid + Mul sharing the input        -> silu flag on the producing CONV
    Add(conv_out, other) with one consumer -> residual on that CONV
Concat, Split and Resize stay as view ops and are resolved to address
modes by the emitter.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .graph import NpuGraph, Op, TensorInfo
from .onnx_import import OnnxModel, as_int_list, attr
from .patterns import CHECKS, silu_pair

SUPPORTED = {"Conv", "MaxPool", "Resize", "Concat", "Split", "Sigmoid", "Mul", "Add"}


@dataclass
class CoverageReport:
    npu_counts: dict = field(default_factory=dict)
    cpu_counts: dict = field(default_factory=dict)
    frontier_failures: list = field(default_factory=list)   # (node, reason)
    after_cut: list = field(default_factory=list)            # node names
    unsupported_frontier: list = field(default_factory=list) # (node, op_type)
    outputs: list = field(default_factory=list)
    macs: int = 0
    fused_silu: int = 0
    fused_residual: int = 0

    @property
    def ok(self) -> bool:
        return not self.frontier_failures

    def text(self) -> str:
        L = ["op coverage:"]
        types = sorted(set(self.npu_counts) | set(self.cpu_counts))
        L.append(f"  {'op':12s} {'npu':>5s} {'cpu':>5s}")
        for t in types:
            L.append(f"  {t:12s} {self.npu_counts.get(t, 0):5d} {self.cpu_counts.get(t, 0):5d}")
        L.append(f"fused: silu={self.fused_silu} residual={self.fused_residual}")
        L.append(f"npu MACs: {self.macs / 1e9:.3f} G")
        L.append(f"npu outputs ({len(self.outputs)}): {self.outputs}")
        if self.unsupported_frontier:
            L.append("cut at unsupported ops: " + ", ".join(f"{n}({t})" for n, t in self.unsupported_frontier))
        if self.frontier_failures:
            L.append("CONSTRAINT FAILURES (supported op types that could not be mapped):")
            for n, r in self.frontier_failures:
                L.append(f"  {n}: {r}")
        L.append("status: " + ("OK" if self.ok else "FAIL"))
        return "\n".join(L)


def lower_onnx(path_or_model, cut_tensors=None):
    m = OnnxModel.load(path_or_model)
    cut = set(cut_tensors or [])
    g = NpuGraph()
    rep = CoverageReport()

    npu_tensors = set(m.graph_inputs)
    for name in m.graph_inputs:
        g.add_tensor(TensorInfo(name, m.shape(name)))
    g.inputs = list(m.graph_inputs)

    npu_nodes = []
    cpu_nodes = set()

    def data_inputs(node):
        return [i for i in node.input if i and not m.is_const(i)]

    for node in m.graph.node:
        if node.op_type == "Constant":
            continue
        ins = data_inputs(node)
        upstream_ok = all(i in npu_tensors and i not in cut for i in ins)
        reason = None
        if node.op_type not in SUPPORTED:
            reason = "unsupported op"
            if upstream_ok:
                rep.unsupported_frontier.append((node.name or node.output[0], node.op_type))
        elif not upstream_ok:
            reason = "after cut"
        else:
            if node.op_type in CHECKS:
                reason = CHECKS[node.op_type](m, node)
            elif node.op_type == "Sigmoid":
                if silu_pair(m, node) is None:
                    reason = "sigmoid outside of x*sigmoid(x)"
            elif node.op_type == "Mul":
                prod = [n for n in m.graph.node if n.op_type == "Sigmoid" and n.output[0] in node.input]
                if not (prod and silu_pair(m, prod[0]) is node):
                    reason = "mul outside of x*sigmoid(x)"
            elif node.op_type == "Add":
                if len(ins) != 2 or m.shape(ins[0]) != m.shape(ins[1]):
                    reason = "add is not a same shape tensor add"
            if reason is not None:
                rep.frontier_failures.append((node.name or node.output[0], reason))
        if reason is None:
            npu_nodes.append(node)
            for o in node.output:
                npu_tensors.add(o)
                g.add_tensor(TensorInfo(o, m.shape(o)))
            rep.npu_counts[node.op_type] = rep.npu_counts.get(node.op_type, 0) + 1
        else:
            cpu_nodes.add(id(node))
            if reason == "after cut":
                rep.after_cut.append(node.name or node.output[0])
            rep.cpu_counts[node.op_type] = rep.cpu_counts.get(node.op_type, 0) + 1

    # Build IR ops.
    silu_of: dict[str, tuple] = {}   # conv output tensor -> (sigmoid, mul)
    for node in npu_nodes:
        if node.op_type == "Sigmoid":
            silu_of[node.input[0]] = (node, silu_pair(m, node))

    tensor_alias: dict[str, str] = {}   # replaced tensor -> surviving tensor

    def resolve(name):
        while name in tensor_alias:
            name = tensor_alias[name]
        return name

    for node in npu_nodes:
        if node.op_type in ("Sigmoid", "Mul"):
            continue
        name = node.name or node.output[0]
        if node.op_type == "Conv":
            w = m.shape(node.input[1])
            k = as_int_list(attr(node, "kernel_shape", list(w[2:])))[0]
            s = as_int_list(attr(node, "strides", [1, 1]))[0]
            out = node.output[0]
            silu = False
            if out in silu_of:
                sig, mul = silu_of[out]
                cons = m.consumers.get(out, [])
                if len(cons) == 2 and {id(c) for c in cons} == {id(sig), id(mul)}:
                    silu = True
                    tensor_alias[mul.output[0]] = out
                    g.tensors[out] = TensorInfo(out, m.shape(mul.output[0]))
                    rep.fused_silu += 1
            g.ops.append(Op("CONV", name, [resolve(node.input[0])], [out], {
                "k": k, "s": s, "pad": k // 2, "ic": w[1], "oc": w[0],
                "silu": silu, "residual": None,
                "weight": node.input[1],
                "bias": node.input[2] if len(node.input) > 2 else None,
            }))
        elif node.op_type == "MaxPool":
            g.ops.append(Op("MAXPOOL5", name, [resolve(node.input[0])], [node.output[0]], {"k": 5, "s": 1, "pad": 2}))
        elif node.op_type == "Resize":
            g.ops.append(Op("UPSAMPLE2", name, [resolve(node.input[0])], [node.output[0]], {"mode": "nearest"}))
        elif node.op_type == "Concat":
            g.ops.append(Op("CONCAT", name, [resolve(i) for i in node.input], [node.output[0]], {"axis": 1}))
        elif node.op_type == "Split":
            sizes = as_int_list(attr(node, "split"))
            if not sizes and len(node.input) > 1:
                sizes = as_int_list(m.const(node.input[1]))
            g.ops.append(Op("SPLIT", name, [resolve(node.input[0])], list(node.output), {"axis": 1, "sizes": sizes}))
        elif node.op_type == "Add":
            a, b = (resolve(i) for i in node.input)
            fused = False
            # The consumer count is taken on the ONNX tensor that feeds the
            # Add (the SiLU output when fused), not on the raw conv output.
            for orig, conv_t, other in ((node.input[0], a, b), (node.input[1], b, a)):
                prod = g.producer(conv_t)
                if prod is not None and prod.kind == "CONV" and prod.attrs["residual"] is None \
                        and len(m.consumers.get(orig, [])) == 1:
                    prod.attrs["residual"] = other
                    tensor_alias[node.output[0]] = conv_t
                    g.tensors[conv_t] = TensorInfo(conv_t, m.shape(node.output[0]))
                    rep.fused_residual += 1
                    fused = True
                    break
            if not fused:
                g.ops.append(Op("ADD", name, [a, b], [node.output[0]], {}))

    # Sigmoid and Mul that did not fuse become explicit SILU ops.
    for node in npu_nodes:
        if node.op_type == "Sigmoid" and node.input[0] not in tensor_alias.values():
            sig, mul = silu_of[node.input[0]]
            if mul.output[0] not in tensor_alias:
                g.ops.append(Op("SILU", node.name or node.output[0], [resolve(node.input[0])], [mul.output[0]], {}))

    # NPU outputs: NPU tensors consumed by CPU nodes or graph outputs.
    outputs = []
    for node in npu_nodes:
        for o in node.output:
            o_res = resolve(o)
            consumed_by_cpu = any(id(c) in cpu_nodes for c in m.consumers.get(o, []))
            if (consumed_by_cpu or o in m.graph_outputs or o in cut) and o_res not in outputs:
                outputs.append(o_res)
    g.outputs = outputs
    for o in outputs:
        if o not in g.tensors:
            g.add_tensor(TensorInfo(o, m.shape(o)))
    for op in g.ops:
        for t in op.inputs + op.outputs + ([op.attrs["residual"]] if op.attrs.get("residual") else []):
            if t not in g.tensors:
                g.add_tensor(TensorInfo(t, m.shape(t)))
    rep.outputs = outputs
    rep.macs = g.macs()
    return g, rep
