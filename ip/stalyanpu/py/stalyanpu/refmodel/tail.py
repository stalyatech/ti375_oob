"""Detection tail of YOLOv8 on the CPU side: DFL decode, sigmoid and NMS.

Inputs are the six head tensors (box logits with 4*16 channels and class
logits with nc channels per scale) as float CHW arrays. Boxes come back in
the coordinates of the network input (letterboxed image).
"""

from __future__ import annotations

import numpy as np

REG_MAX = 16


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def _softmax(x, axis):
    x = x-x.max(axis=axis, keepdims=True)
    e = np.exp(x)
    return e / e.sum(axis=axis, keepdims=True)


def group_head_tensors(tensors: dict, nc: int = 80) -> list:
    """Return [(stride, box CHW, cls CHW)] sorted by stride, from a dict of
    the six cut tensors. The input size is inferred from the largest map."""
    box, cls = {}, {}
    for name, t in tensors.items():
        key = (t.shape[1], t.shape[2])
        if t.shape[0] == 4 * REG_MAX:
            box[key] = t
        elif t.shape[0] == nc:
            cls[key] = t
        else:
            raise ValueError(f"unexpected head tensor {name} {t.shape}")
    keys = sorted(box, key=lambda k: -k[0] * k[1])
    h0 = keys[0][0]
    out = []
    for k in keys:
        stride = 8 * (h0 // k[0])
        out.append((stride, box[k], cls[k]))
    return out


def decode(tensors: dict, nc: int = 80) -> tuple:
    """Returns (boxes xyxy [N,4], scores [N,nc])."""
    boxes, scores = [], []
    for stride, b, c in group_head_tensors(tensors, nc):
        _, h, w = b.shape
        d = b.reshape(4, REG_MAX, h * w)
        d = (_softmax(d, axis=1) * np.arange(REG_MAX, dtype=np.float32).reshape(1, REG_MAX, 1)).sum(axis=1)
        gy, gx = np.meshgrid(np.arange(h), np.arange(w), indexing="ij")
        cx = (gx.reshape(-1) + 0.5) * stride
        cy = (gy.reshape(-1) + 0.5) * stride
        l, t, r, bt = d * stride
        boxes.append(np.stack([cx-l, cy-t, cx+r, cy+bt], axis=1))
        scores.append(_sigmoid(c.reshape(nc, h * w)).T)
    return np.concatenate(boxes, 0).astype(np.float32), np.concatenate(scores, 0).astype(np.float32)


def _iou(box, boxes):
    x1 = np.maximum(box[0], boxes[:, 0])
    y1 = np.maximum(box[1], boxes[:, 1])
    x2 = np.minimum(box[2], boxes[:, 2])
    y2 = np.minimum(box[3], boxes[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    a = (box[2] - box[0]) * (box[3] - box[1])
    b = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    return inter / (a+b-inter + 1e-9)


def nms(boxes: np.ndarray, scores: np.ndarray, conf_thres: float = 0.001,
        iou_thres: float = 0.7, max_det: int = 300, max_nms: int = 30000) -> np.ndarray:
    """Class aware NMS. Returns [M, 6] rows of x1, y1, x2, y2, score, class."""
    idx, cls = np.nonzero(scores > conf_thres)
    if idx.size == 0:
        return np.zeros((0, 6), dtype=np.float32)
    conf = scores[idx, cls]
    order = np.argsort(-conf)[:max_nms]
    idx, cls, conf = idx[order], cls[order], conf[order]
    b = boxes[idx]
    # Offset boxes by class so one pass handles every class.
    off = cls.astype(np.float32).reshape(-1, 1) * 7680.0
    bo = b + off
    keep = []
    alive = np.ones(len(bo), dtype=bool)
    for i in range(len(bo)):
        if not alive[i]:
            continue
        keep.append(i)
        if len(keep) >= max_det:
            break
        rest = np.nonzero(alive[i + 1:])[0] + i + 1
        if rest.size:
            ious = _iou(bo[i], bo[rest])
            alive[rest[ious > iou_thres]] = False
    keep = np.array(keep, dtype=np.int64)
    return np.concatenate([b[keep], conf[keep, None], cls[keep, None].astype(np.float32)], axis=1)


def detect(tensors: dict, nc: int = 80, conf_thres: float = 0.001, iou_thres: float = 0.7,
           max_det: int = 300) -> np.ndarray:
    boxes, scores = decode(tensors, nc)
    return nms(boxes, scores, conf_thres, iou_thres, max_det)
