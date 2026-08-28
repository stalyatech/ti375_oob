"""End to end quantization of the synthetic demo graph: calibrate with
onnxruntime, build the integer parameters, run the bit exact reference and
compare the dequantized output against the FP32 model."""

import numpy as np
import onnx
import onnxruntime as ort
from onnx import numpy_helper

from stalyanpu.frontend import lower_onnx
from stalyanpu.frontend.onnx_import import OnnxModel
from stalyanpu.quant import build_qgraph, choose_qparams, unification_groups
from stalyanpu.quant.calib import collect_stats
from stalyanpu.quant.qgraph import QGraph, QuantParams
from stalyanpu.refmodel.runner import QRunner
from tests.test_lower import make_demo_model


def _randomize(model, rng):
    for init in model.graph.initializer:
        if init.name.endswith(".w"):
            arr = numpy_helper.to_array(init)
            fan_in = np.prod(arr.shape[1:])
            new = rng.normal(0, 1.0 / np.sqrt(fan_in), arr.shape).astype(np.float32)
            init.CopyFrom(numpy_helper.from_array(new, init.name))
        elif init.name.endswith(".b"):
            arr = numpy_helper.to_array(init)
            init.CopyFrom(numpy_helper.from_array(rng.normal(0, 0.1, arr.shape).astype(np.float32), init.name))
    return model


def _quantize_demo(tmp_path=None):
    rng = np.random.default_rng(11)
    model = _randomize(make_demo_model(), rng)
    g, rep = lower_onnx(model)
    assert rep.ok
    images = [rng.random((1, 3, 32, 64), dtype=np.float32) for _ in range(6)]
    stats = collect_stats(model, g, images)
    fixed = {g.inputs[0]: QuantParams(1.0 / 255.0, -128)}
    tq, rrep = choose_qparams(g, stats, method="minmax", fixed=fixed)
    qg = build_qgraph(g, OnnxModel(model), tq)
    return model, g, qg, images, tq


def test_unification_groups():
    g, _ = lower_onnx(make_demo_model())
    groups = unification_groups(g)
    joined = set().union(*groups)
    # split halves, concat inputs and output, residual add, upsample, maxpool
    for name in ("a0", "s0", "s1", "r1", "cat", "a2", "up", "mp"):
        assert name in joined, name


def test_int8_reference_tracks_fp32(tmp_path):
    model, g, qg, images, tq = _quantize_demo()
    sess = ort.InferenceSession(model.SerializeToString(), providers=["CPUExecutionProvider"])
    out_name = g.outputs[0]
    from stalyanpu.quant.calib import make_probe_model
    probe = ort.InferenceSession(make_probe_model(model, [out_name]).SerializeToString(),
                                 providers=["CPUExecutionProvider"])
    runner = QRunner(qg)
    errs = []
    for img in images[:3]:
        ref = probe.run([out_name], {"img": img})[0][0]
        q_in = runner.quantize_input("img", img[0])
        got = runner.dequantize(out_name, runner.run({"img": q_in})[out_name])
        assert got.shape == ref.shape
        errs.append(np.abs(got-ref).mean() / (np.abs(ref).mean() + 1e-9))
    assert max(errs) < 0.15, errs

    # The shared scales really are shared.
    assert tq["s1"].scale == tq["r1"].scale == tq["cat"].scale
    assert tq["a2"].scale == tq["up"].scale == tq["mp"].scale

    # Save and load round trip.
    qg.save(str(tmp_path))
    qg2 = QGraph.load(str(tmp_path))
    got2 = QRunner(qg2).run({"img": runner.quantize_input("img", images[0][0])})[out_name]
    got1 = runner.run({"img": runner.quantize_input("img", images[0][0])})[out_name]
    assert np.array_equal(got1, got2)
