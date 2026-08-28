import numpy as np

from stalyanpu.refmodel import intops
from stalyanpu.refmodel.fixedpoint import requant_scalar


def naive_conv(x, w, stride, pad, pad_value):
    oc, ic, k, _ = w.shape
    xp = intops.pad_chw(x, pad, pad_value).astype(np.int64)
    _, h, w_ = xp.shape
    oh = (h-k) // stride + 1
    ow = (w_-k) // stride + 1
    out = np.zeros((oc, oh, ow), dtype=np.int64)
    for o in range(oc):
        for y in range(oh):
            for xx in range(ow):
                patch = xp[:, y * stride:y * stride + k, xx * stride:xx * stride + k]
                out[o, y, xx] = int((patch * w[o].astype(np.int64)).sum())
    return out


def test_conv2d_int_matches_naive():
    rng = np.random.default_rng(3)
    for k, s in ((1, 1), (3, 1), (3, 2)):
        x = rng.integers(-128, 128, (5, 7, 9), dtype=np.int8)
        w = rng.integers(-127, 128, (4, 5, k, k), dtype=np.int8)
        got = intops.conv2d_int(x, w, s, k // 2, pad_value=-3)
        assert np.array_equal(got, naive_conv(x, w, s, k // 2, -3))


def test_conv2d_int_extreme_values_stay_exact():
    x = np.full((512, 3, 3), -128, dtype=np.int8)
    w = np.full((2, 512, 3, 3), -128, dtype=np.int8)
    got = intops.conv2d_int(x, w, 1, 1, pad_value=-128)
    assert got[0, 1, 1] == 512 * 9 * 16384


def test_requant_channels_matches_scalar():
    rng = np.random.default_rng(5)
    acc = rng.integers(-(1 << 24), 1 << 24, (3, 4, 4), dtype=np.int64)
    bias = rng.integers(-1000, 1000, 3, dtype=np.int64)
    mult = rng.integers(1 << 15, 1 << 16, 3, dtype=np.int64)
    shift = np.array([10, 20, 30], dtype=np.int64)
    q = intops.requant_channels(acc, bias, mult, shift, zp_out=4)
    for c in range(3):
        for i in range(4):
            for j in range(4):
                assert int(q[c, i, j]) == requant_scalar(int(acc[c, i, j]), int(bias[c]), int(mult[c]), int(shift[c]), 4)


def test_lut_and_residual():
    lut = np.arange(-128, 128, dtype=np.int8)[::-1].copy()
    q = np.array([[[-128, 0, 127]]], dtype=np.int8)
    assert list(intops.apply_lut(q, lut)[0, 0]) == [127, -1, -128]
    y = np.array([[[10, 120]]], dtype=np.int8)
    r = np.array([[[20, 120]]], dtype=np.int8)
    out = intops.residual_add(y, r, 1 << 15, 15, 1 << 15, 15, zp_y=5, zp_r=5, zp_out=5)
    assert list(out[0, 0]) == [25, 127]


def test_maxpool5_and_upsample():
    rng = np.random.default_rng(7)
    x = rng.integers(-128, 128, (2, 6, 8), dtype=np.int8)
    got = intops.maxpool5(x)
    xp = intops.pad_chw(x, 2, -128)
    for c in range(2):
        for y in range(6):
            for xx in range(8):
                assert got[c, y, xx] == xp[c, y:y + 5, xx:xx + 5].max()
    up = intops.upsample2(x)
    assert up.shape == (2, 12, 16)
    assert up[1, 5, 7] == x[1, 2, 3]
