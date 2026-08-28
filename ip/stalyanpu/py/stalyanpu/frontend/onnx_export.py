"""Export a YOLOv8 checkpoint to ONNX with ultralytics (optional dependency)."""

from __future__ import annotations

import os
import shutil


def export_yolov8(weights: str = "yolov8s.pt", out: str | None = None, height: int = 384,
                  width: int = 640, opset: int = 13) -> str:
    from ultralytics import YOLO

    model = YOLO(weights)
    path = model.export(format="onnx", imgsz=[height, width], opset=opset, simplify=True, dynamic=False)
    if out:
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        shutil.move(path, out)
        path = out
    return path
