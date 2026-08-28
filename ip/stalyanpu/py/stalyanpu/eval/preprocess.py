"""Image preprocessing identical to the C preprocessor on the target:
letterbox to the network size with gray padding, RGB, scale 1/255."""

from __future__ import annotations

import numpy as np
from PIL import Image


def letterbox(img: Image.Image, new_h: int, new_w: int, color: int = 114) -> tuple:
    """Returns (PIL image new_w x new_h, scale, pad_x, pad_y)."""
    w, h = img.size
    scale = min(new_h / h, new_w / w)
    rw, rh = int(round(w * scale)), int(round(h * scale))
    resized = img.resize((rw, rh), Image.BILINEAR)
    canvas = Image.new("RGB", (new_w, new_h), (color, color, color))
    pad_x = (new_w-rw) // 2
    pad_y = (new_h-rh) // 2
    canvas.paste(resized, (pad_x, pad_y))
    return canvas, scale, pad_x, pad_y


def preprocess(img: Image.Image, new_h: int, new_w: int) -> tuple:
    """Returns (NCHW float32 in [0,1], scale, pad_x, pad_y)."""
    lb, scale, px, py = letterbox(img.convert("RGB"), new_h, new_w)
    arr = np.asarray(lb, dtype=np.float32) / 255.0
    return arr.transpose(2, 0, 1)[None], scale, px, py


def boxes_to_original(det: np.ndarray, scale: float, pad_x: int, pad_y: int, orig_w: int, orig_h: int) -> np.ndarray:
    out = det.copy()
    out[:, [0, 2]] = (out[:, [0, 2]] - pad_x) / scale
    out[:, [1, 3]] = (out[:, [1, 3]] - pad_y) / scale
    out[:, [0, 2]] = np.clip(out[:, [0, 2]], 0, orig_w)
    out[:, [1, 3]] = np.clip(out[:, [1, 3]], 0, orig_h)
    return out
