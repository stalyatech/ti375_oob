"""Layout, packing, descriptor and emitter tests on the synthetic graph."""

import numpy as np

from stalyanpu.backend import layout, weightpack
from stalyanpu.backend.compile import check, load_program, make_memory
from stalyanpu.backend.emit import Descriptor
from stalyanpu.backend.interp import Memory, read_descriptors, read_header
from stalyanpu.golden import hexfmt
from stalyanpu.golden.vectors import write_layer_vectors, write_net_vectors
from stalyanpu.hwcfg import PRESETS
from tests.test_quant import _quantize_demo


def test_layout_round_trip():
    rng = np.random.default_rng(1)
    for c in (3, 32, 80, 96):
        t = rng.integers(-128, 128, (c, 5, 7), dtype=np.int8)
        data = layout.pack(t, pad_value=-5)
        assert len(data) == layout.tensor_bytes(c, 5, 7)
        assert np.array_equal(layout.unpack(data, c, 5, 7), t)
        # Padded channels hold the pad value.
        full = layout.unpack(data, layout.n_planes(c) * 32, 5, 7)
        if c % 32:
            assert np.all(full[c:] == -5)


def test_weightpack_round_trip():
    rng = np.random.default_rng(2)
    for hw in (PRESETS["full2048"], PRESETS["small256"]):
        for oc, ic, k in ((64, 32, 3), (80, 96, 1), (3, 5, 3), (130, 40, 3)):
            w = rng.integers(-127, 128, (oc, ic, k, k), dtype=np.int8)
            data, per_oct = weightpack.pack_weights(w, hw)
            n_oct = (oc + hw.n_oc - 1) // hw.n_oc
            assert len(data) == n_oct * per_oct
            assert np.array_equal(weightpack.unpack_weights(data, oc, ic, k, hw), w)
    # Lane order of the first pair: byte 0 is the even output channel.
    w = np.zeros((2, 1, 1, 1), dtype=np.int8)
    w[0, 0] = 7
    w[1, 0] = -3
    data, _ = weightpack.pack_weights(w, PRESETS["full2048"])
    assert data[0] == 7 and data[1] == (256 - 3)


def test_params_round_trip():
    bias = np.array([1, -2, 300000], dtype=np.int64)
    mult = np.array([32768, 40000, 65535], dtype=np.int64)
    shift = np.array([0, 15, 47], dtype=np.int64)
    data = weightpack.pack_params(bias, mult, shift, -7, 64)
    assert len(data) == 64 * 8
    b, m, s, zp = weightpack.unpack_params(data, 3)
    assert list(b) == [1, -2, 300000] and list(m) == [32768, 40000, 65535] and list(s) == [0, 15, 47] and zp == -7


def test_descriptor_fields_and_crc():
    d = Descriptor()
    d.set("opcode", 1)
    d.set("zp_in", -128)
    d.set("in_w", 640)
    d.set("in_h", 384)
    d.flag("SILU")
    d.finalize()
    assert d.get("zp_in", signed=True) == -128
    assert d.get("in_w") == 640 and d.get("in_h") == 384
    assert d.has_flag("SILU") and not d.has_flag("LAST")
    assert d.crc_ok()
    d2 = Descriptor.from_bytes(d.to_bytes())
    assert d2.w == d.w
    d2.w[3] ^= 1
    assert not d2.crc_ok()


def test_hex_round_trip(tmp_path):
    rng = np.random.default_rng(3)
    ranges = [(0x1000, rng.bytes(48)), (0x20000000, rng.bytes(17))]
    p = str(tmp_path / "m.hex")
    hexfmt.write_hex(p, ranges)
    back = hexfmt.read_hex(p)
    assert back[0] == ranges[0]
    assert back[1][0] == 0x20000000 and back[1][1][:17] == ranges[1][1]


def test_emit_and_interp_match_runner(tmp_path):
    model, g, qg, images, tq = _quantize_demo()
    hw = PRESETS["small256"]
    prog = load_program(qg, hw, 0x1000000, 0x2000000)
    blob = prog.to_bytes()
    assert len(blob) == prog.size
    x = np.random.default_rng(4).integers(-128, 128, (3, 32, 64), dtype=np.int8)
    ok, diff = check(qg, hw, prog, x)
    assert ok, diff

    # Header and descriptor table read back from memory.
    mem = make_memory(prog, x, tq["img"].zp)
    hdr = read_header(mem, prog.base)
    assert hdr["desc_count"] == len(prog.descriptors) == 5    # 4 conv + maxpool
    descs = read_descriptors(mem, prog.base, hdr)
    assert descs[-1].has_flag("LAST") and descs[-1].has_flag("IRQ")
    kinds = [d.get("opcode") for d in descs]
    assert kinds.count(2) == 1
    # The residual conv reads the split half as residual and writes into the concat buffer.
    res = [d for d in descs if d.has_flag("RESIDUAL")]
    assert len(res) == 1
    assert prog.alloc.place["r1"].buffer is prog.alloc.place["cat"].buffer
    assert prog.alloc.place["s1"].buffer is prog.alloc.place["cat"].buffer
    # Upsample feeds the maxpool through the UPS0 flag, no copy.
    mp = [d for d in descs if d.get("opcode") == 2][0]
    assert mp.has_flag("UPS0")

    # Golden vector sets.
    meta = write_net_vectors(prog, hw, make_memory(prog, x, tq["img"].zp), str(tmp_path / "net"), dump_all=True)
    assert meta["desc_count"] == 5
    meta = write_layer_vectors(prog, hw, make_memory(prog, x, tq["img"].zp), 2, str(tmp_path / "l2"))
    assert meta["desc_count"] == 1
    back = hexfmt.read_hex(str(tmp_path / "l2" / "golden.hex"))
    assert len(back) == 1 and back[0][0] == prog.descriptors[2].get("out_base")


def test_full_array_also_matches(tmp_path):
    model, g, qg, images, tq = _quantize_demo()
    prog = load_program(qg, PRESETS["full2048"])
    x = np.random.default_rng(5).integers(-128, 128, (3, 32, 64), dtype=np.int8)
    ok, diff = check(qg, PRESETS["full2048"], prog, x)
    assert ok, diff
