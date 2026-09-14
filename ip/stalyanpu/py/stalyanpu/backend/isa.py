"""Single source of truth for the StalyaNPU descriptor format, register map
and blob header. ``gen_header`` renders it to C, the emitter packs
descriptors from it and the RTL constants in snpu_pkg.vh mirror it.

Descriptor: 32 little endian 32-bit words (128 bytes). Word 31 is the CRC32
of words 0..30 (zlib polynomial, initial value 0xFFFFFFFF, final xor). Byte
addresses are absolute DDR addresses. Strides are in bytes. Tensors use the
NC32HW layout: [ceil(C/32)][H][W][32] bytes, a "plane" is one channel group.
"""

from __future__ import annotations

from dataclasses import dataclass

DESC_WORDS = 32
DESC_BYTES = 4 * DESC_WORDS
ISA_VERSION = 1


@dataclass(frozen=True)
class Field:
    word: int
    name: str
    lsb: int
    width: int
    doc: str

    @property
    def mask(self) -> int:
        return (1 << self.width) - 1


# fmt: off
FIELDS = [
    Field(0,  "opcode",           0, 8,  "operation, see OPCODES"),
    Field(0,  "flags",            8, 16, "bit set, see FLAGS"),
    Field(0,  "version",         24, 8,  "descriptor format version (ISA_VERSION)"),
    Field(1,  "in_h",             0, 16, "input height in pixels"),
    Field(1,  "in_w",            16, 16, "input width in pixels"),
    Field(2,  "out_h",            0, 16, "output height in pixels"),
    Field(2,  "out_w",           16, 16, "output width in pixels"),
    Field(3,  "ic",               0, 16, "real input channels (before padding)"),
    Field(3,  "oc",              16, 16, "real output channels (before padding)"),
    Field(4,  "src0_base",        0, 32, "byte address of source 0"),
    Field(5,  "src0_plane_stride",0, 32, "bytes between channel groups of source 0"),
    Field(6,  "src0_row_stride",  0, 32, "bytes between rows of source 0"),
    Field(7,  "src0_planes",      0, 16, "channel groups read from source 0"),
    Field(7,  "src1_planes",     16, 16, "channel groups read from source 1 (TWO_SRC)"),
    Field(8,  "src1_base",        0, 32, "byte address of source 1"),
    Field(9,  "src1_plane_stride",0, 32, "bytes between channel groups of source 1"),
    Field(10, "src1_row_stride",  0, 32, "bytes between rows of source 1"),
    Field(11, "w_base",           0, 32, "byte address of the packed weights"),
    Field(12, "w_bytes_per_oct",  0, 32, "packed weight bytes per output channel tile"),
    Field(13, "param_base",       0, 32, "byte address of per channel {bias i32, mult u16, shift u8, zp i8}"),
    Field(14, "lut_base",         0, 32, "byte address of the 256 byte activation table, 0 if none"),
    Field(15, "out_base",         0, 32, "byte address of the output tensor (plane offset applied)"),
    Field(16, "out_plane_stride", 0, 32, "bytes between channel groups of the output"),
    Field(17, "out_row_stride",   0, 32, "bytes between rows of the output"),
    Field(18, "res_base",         0, 32, "byte address of the residual tensor (RESIDUAL)"),
    Field(19, "res_plane_stride", 0, 32, "bytes between channel groups of the residual"),
    Field(20, "res_row_stride",   0, 32, "bytes between rows of the residual"),
    Field(21, "zp_in",            0, 8,  "input zero point, int8"),
    Field(21, "zp_out",           8, 8,  "zero point after the activation table, int8 (requant zp is per channel in the param block)"),
    Field(21, "zp_res",          16, 8,  "residual zero point, int8"),
    Field(21, "zp_out2",         24, 8,  "output zero point after the residual add, int8"),
    Field(22, "res_mult_a",       0, 16, "residual path rescale multiplier of the activation"),
    Field(22, "res_shift_a",     16, 8,  "residual path rescale shift of the activation"),
    Field(23, "res_mult_b",       0, 16, "residual path rescale multiplier of the residual"),
    Field(23, "res_shift_b",     16, 8,  "residual path rescale shift of the residual"),
    Field(24, "tile_rows",        0, 16, "output rows per tile"),
    Field(24, "tile_px",         16, 16, "output pixels per tile (tile_rows * out_w)"),
    Field(25, "n_tiles",          0, 16, "tiles in this descriptor"),
    Field(25, "ring_rows",       16, 16, "input rows kept resident in the ibuf ring"),
    Field(26, "pad_t",            0, 8,  "top padding in pixels"),
    Field(26, "pad_l",            8, 8,  "left padding in pixels"),
    Field(26, "pad_b",           16, 8,  "bottom padding in pixels"),
    Field(26, "pad_r",           24, 8,  "right padding in pixels"),
    Field(27, "k",                0, 4,  "kernel size, 1 or 3 (5 for MAXPOOL5)"),
    Field(27, "stride",           4, 4,  "stride, 1 or 2"),
    Field(30, "tag",              0, 32, "debug tag, echoed in STATUS"),
    Field(31, "crc32",            0, 32, "CRC32 of words 0..30"),
]
# fmt: on

OPCODES = {
    "NOP": 0x00,
    "CONV": 0x01,
    "MAXPOOL5": 0x02,
    "COPY": 0x03,
    "BARRIER": 0x04,
    "END": 0xFF,
}

# Bit positions inside the flags field.
FLAGS = {
    "SILU": 0,        # apply the activation table
    "RESIDUAL": 1,    # add the residual tensor after the activation
    "IRQ": 2,         # raise the done interrupt after this descriptor
    "LAST": 3,        # last descriptor of the list
    "UPS0": 4,        # source 0 is read with nearest 2x upsampling
    "UPS1": 5,        # source 1 is read with nearest 2x upsampling
    "TWO_SRC": 6,     # channel groups of source 1 follow those of source 0
    "L0_MODE": 7,     # stem mode, 3x3x3 window presented as one 27 wide vector
    "WAIT_PREV": 8,   # wait for the previous descriptor's writes before reading
    "DEBUG_DUMP": 9,  # per descriptor done interrupt for debugging
}

# CSR register map, byte offsets inside the APB window.
CSR = [
    (0x00, "ID",          "RO", "0x534E5055 ('SNPU')"),
    (0x04, "VERSION",     "RO", "hardware version, major << 8 | minor"),
    (0x08, "GEOMETRY",    "RO", "n_chain[7:0] | chain_len[15:8] | log2(p_max)[19:16] | ibuf_kb[31:20]"),
    (0x0C, "CTRL",        "RW", "bit0 start (self clearing), bit1 abort, bit2 soft reset"),
    (0x10, "STATUS",      "RO", "bit0 busy, bits[15:8] error code, bits[31:16] current descriptor index"),
    (0x14, "DESC_BASE",   "RW", "byte address of the descriptor list, 128 byte aligned"),
    (0x18, "DESC_COUNT",  "RW", "number of descriptors to execute"),
    (0x1C, "IRQ_STATUS",  "W1C", "bit0 done, bit1 descriptor done, bit2 error, bit3 timeout"),
    (0x20, "IRQ_MASK",    "RW", "1 enables the corresponding IRQ_STATUS bit"),
    (0x24, "CYCLE_CNT",   "RO", "cycles spent busy since start"),
    (0x28, "STALL_IBUF",  "RO", "cycles spent in the input fill phases (array idle, DDR bound)"),
    (0x2C, "STALL_WGT",   "RO", "run phase cycles with no pixel vector entering the array"),
    (0x30, "STALL_ACC",   "RO", "cycles with a pixel vector entering the array (MAC cycles)"),
    (0x34, "STALL_WR",    "RO", "cycles an output word was held by the write path"),
    (0x38, "DESC_DONE",   "RO", "descriptors completed since start"),
    (0x3C, "TAG",         "RO", "tag word of the current descriptor"),
    (0x40, "DBG0",        "RO", "debug: rd_dma bookkeeping[31:8], seq state[7:3], unit busy, maxpool busy, wr idle"),
    (0x44, "DBG1",        "RO", "debug: wr pending[7:0], loaders idle, cmd/data handshakes, AXI valid and ready flags"),
    (0x48, "DBG2",        "RO", "debug: write AW wait cycles since reset"),
    (0x4C, "DBG3",        "RO", "debug: write W wait cycles after AW accept since reset"),
    (0x50, "DBG4",        "RO", "debug: write bursts finished since reset"),
    (0x54, "DBG5",        "RO", "debug: write beats sent since reset"),
]

ERRORS = {
    "NONE": 0,
    "BAD_OPCODE": 1,
    "BAD_CRC": 2,
    "BAD_VERSION": 3,
    "AXI_READ": 4,
    "AXI_WRITE": 5,
    "TIMEOUT": 6,
    "GEOMETRY": 7,
}

# Blob header (4 KB, little endian 32-bit words), produced by the emitter.
BLOB_MAGIC = 0x534E5055
BLOB_HEADER = [
    ("magic", "BLOB_MAGIC"),
    ("version", "ISA_VERSION"),
    ("base", "load address the blob was linked for"),
    ("size", "total blob size in bytes"),
    ("desc_off", "offset of the descriptor table"),
    ("desc_count", "number of descriptors"),
    ("param_off", "offset of weights, parameters and tables"),
    ("param_size", "size of that region"),
    ("scratch_base", "byte address of the activation scratch region"),
    ("scratch_size", "size of the scratch region"),
    ("input_off", "offset of the input tensor buffer inside scratch"),
    ("input_bytes", "input tensor size in bytes"),
    ("n_outputs", "number of output tensors"),
    ("outputs_off", "offset of the output table (see OutputEntry)"),
    ("crc32", "CRC32 of the blob excluding this word"),
]

OUTPUT_ENTRY = [
    ("offset", "byte offset inside scratch"),
    ("h", "height"),
    ("w", "width"),
    ("c", "real channels"),
    ("scale_q16", "dequantization scale, unsigned 16.16 fixed point"),
    ("zp", "zero point, int8 sign extended"),
    ("name_off", "offset of the zero terminated tensor name"),
    ("reserved", "0"),
]


def field(name: str) -> Field:
    for f in FIELDS:
        if f.name == name:
            return f
    raise KeyError(name)


def _check():
    used = {}
    for f in FIELDS:
        assert 0 <= f.word < DESC_WORDS, f
        assert f.lsb + f.width <= 32, f
        for b in range(f.lsb, f.lsb + f.width):
            key = (f.word, b)
            assert key not in used, (f, used[key])
            used[key] = f.name


_check()
