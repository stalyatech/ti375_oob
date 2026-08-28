from stalyanpu.hwcfg import PRESETS
from stalyanpu.perf import estimate, yolov8s_layers


def test_yolov8s_macs_at_640():
    # Ultralytics reports 28.6 GFLOPs for YOLOv8s at 640x640, that is
    # 14.3 GMAC. The head tail (DFL conv) is not part of the table, so the
    # sum lands slightly below.
    layers = yolov8s_layers(640, 640)
    macs = sum(l.macs for l in layers)
    assert 13.5e9 < macs < 14.5e9


def test_yolov8s_shapes():
    layers = yolov8s_layers(384, 640)
    by_name = {l.name: l for l in layers}
    assert (by_name["L0.stem"].out_h, by_name["L0.stem"].out_w) == (192, 320)
    assert (by_name["L9.sppf.cv2"].out_h, by_name["L9.sppf.cv2"].out_w) == (12, 20)
    assert by_name["Detect.P3.cv3.2"].oc == 80
    assert by_name["L12.c2f.cv1"].ic == 768


def test_full_array_reaches_target():
    est = estimate(yolov8s_layers(384, 640), PRESETS["full2048"])
    assert est.fps >= 30.0
    assert est.util > 0.5


def test_small_array_runs():
    est = estimate(yolov8s_layers(384, 640), PRESETS["small256"])
    assert est.cycles > 0
    assert est.fps < 30.0
