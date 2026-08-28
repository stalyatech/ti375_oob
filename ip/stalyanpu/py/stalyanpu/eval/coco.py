"""COCO val2017 evaluation of the FP32 ONNX model and of the INT8 reference
model, both through the same numpy detection tail so the comparison only
measures quantization."""

from __future__ import annotations

import json
import os
import random

import numpy as np
from PIL import Image

from ..refmodel import tail
from .preprocess import boxes_to_original, preprocess

# COCO 80 class index -> COCO 91 category id.
COCO80_TO_91 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 27, 28,
                31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55,
                56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 67, 70, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 84,
                85, 86, 87, 88, 89, 90]


def image_list(img_dir: str, ann_file: str, n: int, seed: int = 0) -> list:
    with open(ann_file) as fh:
        ann = json.load(fh)
    imgs = [(im["id"], os.path.join(img_dir, im["file_name"])) for im in ann["images"]]
    imgs.sort()
    rng = random.Random(seed)
    rng.shuffle(imgs)
    return imgs[:n] if n else imgs


def calibration_images(paths: list, new_h: int, new_w: int):
    for _, p in paths:
        yield preprocess(Image.open(p), new_h, new_w)[0]


class Fp32Head:
    """Runs the ONNX model up to the six cut tensors with onnxruntime."""

    def __init__(self, model, cut_tensors: list):
        import onnx
        import onnxruntime as ort
        from ..quant.calib import make_probe_model

        if not isinstance(model, onnx.ModelProto):
            model = onnx.load(model)
        probe = make_probe_model(model, cut_tensors)
        self.sess = ort.InferenceSession(probe.SerializeToString(), providers=["CPUExecutionProvider"])
        self.in_name = self.sess.get_inputs()[0].name
        self.cut = cut_tensors

    def __call__(self, img_nchw: np.ndarray) -> dict:
        outs = self.sess.run(self.cut, {self.in_name: img_nchw})
        return {n: o[0] for n, o in zip(self.cut, outs)}


class Int8Head:
    """Runs the INT8 reference model and dequantizes the cut tensors."""

    def __init__(self, qgraph):
        from ..refmodel.runner import QRunner

        self.runner = QRunner(qgraph)
        self.in_name = qgraph.graph.inputs[0]
        self.cut = qgraph.graph.outputs

    def __call__(self, img_nchw: np.ndarray) -> dict:
        q = self.runner.quantize_input(self.in_name, img_nchw[0])
        outs = self.runner.run({self.in_name: q})
        return {n: self.runner.dequantize(n, t) for n, t in outs.items()}


def run_detections(head, paths: list, new_h: int, new_w: int, nc: int = 80,
                   conf_thres: float = 0.001, iou_thres: float = 0.7, progress=None) -> list:
    results = []
    for i, (img_id, p) in enumerate(paths):
        img = Image.open(p)
        x, scale, px, py = preprocess(img, new_h, new_w)
        det = tail.detect(head(x), nc, conf_thres, iou_thres)
        det = boxes_to_original(det, scale, px, py, img.width, img.height)
        for x1, y1, x2, y2, s, c in det:
            results.append({"image_id": int(img_id), "category_id": COCO80_TO_91[int(c)],
                            "bbox": [float(x1), float(y1), float(x2 - x1), float(y2 - y1)],
                            "score": float(s)})
        if progress:
            progress(i + 1)
    return results


def coco_map(results: list, ann_file: str, img_ids: list) -> dict:
    from pycocotools.coco import COCO
    from pycocotools.cocoeval import COCOeval

    gt = COCO(ann_file)
    if not results:
        return {"map50_95": 0.0, "map50": 0.0}
    dt = gt.loadRes(results)
    ev = COCOeval(gt, dt, "bbox")
    ev.params.imgIds = sorted(img_ids)
    ev.evaluate()
    ev.accumulate()
    ev.summarize()
    return {"map50_95": float(ev.stats[0]), "map50": float(ev.stats[1])}
