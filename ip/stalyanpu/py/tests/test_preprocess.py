import numpy as np
from PIL import Image

from stalyanpu.eval.preprocess import boxes_to_original, letterbox, preprocess


def test_letterbox_16_9_source_fills_width():
    img = Image.fromarray(np.zeros((1080, 1920, 3), np.uint8))
    lb, scale, px, py = letterbox(img, 384, 640)
    assert lb.size == (640, 384)
    assert abs(scale - 1 / 3) < 1e-9
    assert (px, py) == (0, 12)          # 360 rows of content, 12 gray rows top and bottom
    arr = np.asarray(lb)
    assert arr[0, 0].tolist() == [114, 114, 114]
    assert arr[200, 300].tolist() == [0, 0, 0]


def test_preprocess_and_box_mapping():
    img = Image.fromarray(np.full((480, 640, 3), 255, np.uint8))
    x, scale, px, py = preprocess(img, 384, 640)
    assert x.shape == (1, 3, 384, 640) and x.dtype == np.float32
    assert x.max() <= 1.0
    det = np.array([[px + 10 * scale, py + 20 * scale, px + 110 * scale, py + 220 * scale, 0.9, 3]], np.float32)
    back = boxes_to_original(det, scale, px, py, 640, 480)
    assert np.allclose(back[0, :4], [10, 20, 110, 220], atol=1e-3)
