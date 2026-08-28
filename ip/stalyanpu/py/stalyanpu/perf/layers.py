"""Layer description used by the performance model.

``yolov8s_layers`` builds the YOLOv8s detection network (width 0.50, depth
0.33, max channels 1024) from its yaml structure so the performance model can
run without an ONNX export. The head is cut after the six per scale 1x1 convs
(box and class logits); DFL decoding and NMS run on the CPU.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Layer:
    name: str
    kind: str            # "conv" or "maxpool5"
    ic: int
    oc: int
    in_h: int
    in_w: int
    out_h: int
    out_w: int
    k: int = 1
    s: int = 1
    silu: bool = True
    residual: bool = False
    stem: bool = False
    group: str = ""
    tags: list = field(default_factory=list)

    @property
    def macs(self) -> int:
        if self.kind != "conv":
            return 0
        return self.out_h * self.out_w * self.oc * self.ic * self.k * self.k

    @property
    def weight_bytes(self) -> int:
        if self.kind != "conv":
            return 0
        return self.oc * self.ic * self.k * self.k


def _out(size: int, k: int, s: int) -> int:
    pad = k // 2
    return (size + (2 * pad) - k) // s + 1


class _Builder:
    def __init__(self):
        self.layers: list[Layer] = []

    def conv(self, name, ic, oc, k, s, h, w, silu=True, residual=False, stem=False, group=""):
        oh, ow = _out(h, k, s), _out(w, k, s)
        self.layers.append(Layer(name, "conv", ic, oc, h, w, oh, ow, k, s, silu, residual, stem, group))
        return oh, ow

    def maxpool5(self, name, c, h, w, group=""):
        self.layers.append(Layer(name, "maxpool5", c, c, h, w, h, w, 5, 1, False, False, False, group))
        return h, w

    def c2f(self, name, cin, cout, n, shortcut, h, w):
        c = cout // 2
        self.conv(f"{name}.cv1", cin, 2 * c, 1, 1, h, w, group=name)
        for i in range(n):
            self.conv(f"{name}.m{i}.cv1", c, c, 3, 1, h, w, group=name)
            self.conv(f"{name}.m{i}.cv2", c, c, 3, 1, h, w, residual=shortcut, group=name)
        self.conv(f"{name}.cv2", (2 + n) * c, cout, 1, 1, h, w, group=name)
        return h, w

    def sppf(self, name, cin, cout, h, w):
        c = cin // 2
        self.conv(f"{name}.cv1", cin, c, 1, 1, h, w, group=name)
        for i in range(3):
            self.maxpool5(f"{name}.pool{i}", c, h, w, group=name)
        self.conv(f"{name}.cv2", 4 * c, cout, 1, 1, h, w, group=name)
        return h, w

    def detect_scale(self, name, ch, h, w, c2=64, c3=128, nc=80):
        self.conv(f"{name}.cv2.0", ch, c2, 3, 1, h, w, group=name)
        self.conv(f"{name}.cv2.1", c2, c2, 3, 1, h, w, group=name)
        self.conv(f"{name}.cv2.2", c2, 64, 1, 1, h, w, silu=False, group=name)
        self.conv(f"{name}.cv3.0", ch, c3, 3, 1, h, w, group=name)
        self.conv(f"{name}.cv3.1", c3, c3, 3, 1, h, w, group=name)
        self.conv(f"{name}.cv3.2", c3, nc, 1, 1, h, w, silu=False, group=name)


def yolov8s_layers(height: int = 384, width: int = 640) -> list[Layer]:
    """YOLOv8s backbone, neck and head convs for the given input size."""
    b = _Builder()
    ch = [32, 64, 128, 256, 512]
    depth = [1, 2, 2, 1]

    h, w = b.conv("L0.stem", 3, ch[0], 3, 2, height, width, stem=True, group="L0")
    h, w = b.conv("L1.down", ch[0], ch[1], 3, 2, h, w, group="L1")
    h, w = b.c2f("L2.c2f", ch[1], ch[1], depth[0], True, h, w)
    h, w = b.conv("L3.down", ch[1], ch[2], 3, 2, h, w, group="L3")
    h3, w3 = b.c2f("L4.c2f", ch[2], ch[2], depth[1], True, h, w)
    h, w = b.conv("L5.down", ch[2], ch[3], 3, 2, h3, w3, group="L5")
    h4, w4 = b.c2f("L6.c2f", ch[3], ch[3], depth[2], True, h, w)
    h, w = b.conv("L7.down", ch[3], ch[4], 3, 2, h4, w4, group="L7")
    h5, w5 = b.c2f("L8.c2f", ch[4], ch[4], depth[3], True, h, w)
    h5, w5 = b.sppf("L9.sppf", ch[4], ch[4], h5, w5)

    # Neck. Upsample and concat are address modes, the concat channel count
    # shows up as the input channel count of the consuming C2f.
    b.c2f("L12.c2f", ch[4] + ch[3], ch[3], 1, False, h4, w4)
    b.c2f("L15.c2f", ch[3] + ch[2], ch[2], 1, False, h3, w3)
    b.conv("L16.down", ch[2], ch[2], 3, 2, h3, w3, group="L16")
    b.c2f("L18.c2f", ch[2] + ch[3], ch[3], 1, False, h4, w4)
    b.conv("L19.down", ch[3], ch[3], 3, 2, h4, w4, group="L19")
    b.c2f("L21.c2f", ch[3] + ch[4], ch[4], 1, False, h5, w5)

    b.detect_scale("Detect.P3", ch[2], h3, w3)
    b.detect_scale("Detect.P4", ch[3], h4, w4)
    b.detect_scale("Detect.P5", ch[4], h5, w5)
    return b.layers
