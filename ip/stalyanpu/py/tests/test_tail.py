import numpy as np

from stalyanpu.refmodel import tail


def test_decode_geometry():
    # One box at grid cell (1, 2) of the stride 8 map with all distances
    # concentrated on bin 3 (3 * 8 = 24 pixels each side).
    h, w = 4, 6
    box = np.full((64, h, w), -20.0, dtype=np.float32)
    box[3::16, 1, 2] = 20.0
    cls = np.full((80, h, w), -20.0, dtype=np.float32)
    cls[7, 1, 2] = 20.0
    tensors = {"b8": box, "c8": cls,
               "b16": np.zeros((64, 2, 3), np.float32), "c16": np.full((80, 2, 3), -20.0, np.float32),
               "b32": np.zeros((64, 1, 2), np.float32), "c32": np.full((80, 1, 2), -20.0, np.float32)}
    det = tail.detect(tensors, conf_thres=0.5)
    assert det.shape[0] == 1
    x1, y1, x2, y2, s, c = det[0]
    cx, cy = (2 + 0.5) * 8, (1 + 0.5) * 8
    assert abs(x1 - (cx - 24)) < 1e-3 and abs(x2 - (cx + 24)) < 1e-3
    assert abs(y1 - (cy - 24)) < 1e-3 and abs(y2 - (cy + 24)) < 1e-3
    assert int(c) == 7 and s > 0.99


def test_nms_suppresses_overlaps():
    boxes = np.array([[0, 0, 10, 10], [1, 1, 11, 11], [50, 50, 60, 60]], np.float32)
    scores = np.zeros((3, 80), np.float32)
    scores[0, 0] = 0.9
    scores[1, 0] = 0.8
    scores[2, 0] = 0.7
    scores[1, 1] = 0.6   # same box, other class survives
    det = tail.nms(boxes, scores, conf_thres=0.5, iou_thres=0.5)
    assert det.shape[0] == 3
    assert set(det[:, 5].astype(int)) == {0, 1}
