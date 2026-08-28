"""ONNX loading helpers: shape inference, initializers and attribute access."""

from __future__ import annotations

import numpy as np
import onnx
from onnx import numpy_helper, shape_inference


class OnnxModel:
    def __init__(self, model: onnx.ModelProto):
        try:
            model = shape_inference.infer_shapes(model)
        except Exception:
            pass
        self.model = model
        self.graph = model.graph
        self.initializers = {i.name: i for i in self.graph.initializer}
        self.shapes: dict[str, tuple] = {}
        for vi in list(self.graph.input) + list(self.graph.value_info) + list(self.graph.output):
            dims = []
            for d in vi.type.tensor_type.shape.dim:
                dims.append(d.dim_value if d.dim_value > 0 else 1)
            self.shapes[vi.name] = tuple(dims)
        for name, init in self.initializers.items():
            self.shapes[name] = tuple(init.dims)
        self.consumers: dict[str, list] = {}
        for node in self.graph.node:
            for i in node.input:
                self.consumers.setdefault(i, []).append(node)
        self.graph_inputs = [i.name for i in self.graph.input if i.name not in self.initializers]
        self.graph_outputs = [o.name for o in self.graph.output]

    @classmethod
    def load(cls, path_or_model) -> "OnnxModel":
        if isinstance(path_or_model, onnx.ModelProto):
            return cls(path_or_model)
        return cls(onnx.load(path_or_model))

    def const(self, name: str):
        if name in self.initializers:
            return numpy_helper.to_array(self.initializers[name])
        # Constant nodes feeding the tensor.
        for node in self.graph.node:
            if node.op_type == "Constant" and name in node.output:
                for a in node.attribute:
                    if a.name == "value":
                        return numpy_helper.to_array(a.t)
        return None

    def is_const(self, name: str) -> bool:
        return self.const(name) is not None

    def shape(self, name: str) -> tuple:
        return self.shapes.get(name, ())


def attr(node, name, default=None):
    for a in node.attribute:
        if a.name == name:
            return onnx.helper.get_attribute_value(a)
    return default


def as_int_list(v) -> list:
    if v is None:
        return []
    return [int(x) for x in np.asarray(v).ravel()]
