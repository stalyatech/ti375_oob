import os

from stalyanpu.backend import isa
from stalyanpu.backend.gen_header import DEFAULT_OUT, check_header, render_header


def test_fields_do_not_overlap():
    used = set()
    for f in isa.FIELDS:
        for b in range(f.lsb, f.lsb + f.width):
            assert (f.word, b) not in used
            used.add((f.word, b))


def test_crc_is_last_word():
    assert isa.field("crc32").word == isa.DESC_WORDS - 1


def test_header_contains_every_field_and_register():
    text = render_header()
    for f in isa.FIELDS:
        assert f"SNPU_DF_{f.name.upper()}_WORD" in text
    for _, name, _, _ in isa.CSR:
        assert f"SNPU_REG_{name}" in text
    for name in isa.OPCODES:
        assert f"SNPU_OP_{name}" in text


def test_committed_header_is_current():
    assert os.path.exists(DEFAULT_OUT), "run: python -m stalyanpu gen-header"
    assert check_header(DEFAULT_OUT), "stale header, run: python -m stalyanpu gen-header"
