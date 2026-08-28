from fractions import Fraction

import numpy as np
import pytest

from stalyanpu.refmodel import fixedpoint as fp


def slow_requant(acc, bias, m, sh, zp):
    # Exact rational reference: round half up of (acc + bias) * m / 2^sh.
    v = Fraction((acc + bias) * m, 1 << sh)
    r = (v + Fraction(1, 2)).__floor__()
    return max(-128, min(127, r + zp))


@pytest.mark.parametrize("acc", [-(1 << 31) + 1, -123456789, -1, 0, 1, 12345, (1 << 31) - 2])
@pytest.mark.parametrize("m", [1 << 15, 40000, (1 << 16) - 1])
@pytest.mark.parametrize("sh", [0, 1, 7, 23, 31, 47])
@pytest.mark.parametrize("zp", [-128, 0, 5, 127])
def test_requant_scalar_matches_rational(acc, m, sh, zp):
    bias = 0
    assert fp.requant_scalar(acc, bias, m, sh, zp) == slow_requant(acc, bias, m, sh, zp)


def test_requant_ties_round_half_up():
    # (acc * m) = 3 * 2^(sh-1): exactly halfway between 1 and 2 -> 2
    m = 1 << 15
    sh = 16
    acc = 3
    assert fp.requant_scalar(acc, 0, m, sh, 0) == 2
    # negative tie: -1.5 -> -1 (half up means toward positive infinity)
    assert fp.requant_scalar(-acc, 0, m, sh, 0) == -1


def test_requant_vector_matches_scalar():
    rng = np.random.default_rng(1)
    n = 4096
    acc = rng.integers(-(1 << 30), 1 << 30, n, dtype=np.int64)
    bias = rng.integers(-(1 << 20), 1 << 20, n, dtype=np.int64)
    m = rng.integers(fp.MULT_MIN, fp.MULT_MAX + 1, n, dtype=np.int64)
    sh = rng.integers(0, 48, n, dtype=np.int64)
    zp = -7
    v = fp.requant(acc, bias, m, sh, zp)
    for i in range(n):
        assert int(v[i]) == fp.requant_scalar(int(acc[i]), int(bias[i]), int(m[i]), int(sh[i]), zp)


def test_requant_overflow_guard():
    with pytest.raises(OverflowError):
        fp.requant_scalar((1 << 31) - 1, 1, 1 << 15, 16, 0)


@pytest.mark.parametrize("scale", [1e-6, 3.7e-4, 0.0123, 0.5, 0.99, 1.0, 1.5, 200.0])
def test_quantize_multiplier_precision(scale):
    m, sh = fp.quantize_multiplier(scale)
    assert fp.MULT_MIN <= m <= fp.MULT_MAX
    assert 0 <= sh <= fp.SHIFT_MAX
    approx = m / (1 << sh)
    assert abs(approx / scale - 1.0) < 2 ** -15


def test_quantize_multiplier_rejects_nonpositive():
    with pytest.raises(ValueError):
        fp.quantize_multiplier(0.0)


def test_silu_lut_shape_and_monotone_tail():
    lut = fp.silu_lut(s_in=0.05, zp_in=-10, s_out=0.04, zp_out=-128)
    assert lut.shape == (256,)
    assert lut.dtype == np.int8
    # SiLU is monotone for x > 1.28, so the upper part of the table is
    # non decreasing.
    upper = lut[200:].astype(int)
    assert np.all(np.diff(upper) >= 0)
    # Large negative inputs map close to zero output.
    x_min = 0.05 * (-128 + 10)
    y_min = x_min / (1 + np.exp(-x_min))
    assert abs(int(lut[0]) - (round(y_min / 0.04) - 128)) <= 1
