"""Test registry of the StalyaNPU simulation tree.

Each entry names a testbench top, the source files relative to the repository
root, extra defines and plusargs. ``needs_dsp_model`` adds the Efinity DSP48
simulation model unless the run uses the behavioural twin (--behav).
"""

RTL = "ip/stalyanpu/rtl"
COMMON = "sim/stalyanpu/common"
UNIT = "sim/stalyanpu/unit"

CONV_FILES = [
            f"{RTL}/snpu_dsp_mac2.v", f"{RTL}/snpu_skew.v", f"{RTL}/snpu_wshadow.v", f"{RTL}/snpu_pe_chain.v",
            f"{RTL}/snpu_pe_array.v", f"{RTL}/snpu_acc.v", f"{RTL}/snpu_ibuf.v", f"{RTL}/snpu_wfifo.v",
            f"{RTL}/snpu_agen.v", f"{RTL}/snpu_epilogue.v", f"{RTL}/snpu_conv_unit.v", f"{UNIT}/tb_conv_unit.sv",
        ]

TOP_FILES = CONV_FILES[:-1] + [
            f"{RTL}/snpu_rd_dma.v", f"{RTL}/snpu_wr_dma.v", f"{RTL}/snpu_maxpool5.v", f"{RTL}/snpu_csr.v",
            f"{RTL}/snpu_seq.v", f"{RTL}/snpu_top.v", f"{COMMON}/axi4_mem_model.sv", f"{UNIT}/tb_npu_net.sv",
        ]

TESTS = {
    "tb_dsp_mac": {
        "top": "tb_dsp_mac",
        "files": [f"{RTL}/snpu_dsp_mac2.v", f"{UNIT}/tb_dsp_mac.sv"],
        "needs_dsp_model": True,
        "group": "unit",
    },
    "tb_pe_chain": {
        "top": "tb_pe_chain",
        "files": [
            f"{RTL}/snpu_dsp_mac2.v",
            f"{RTL}/snpu_skew.v",
            f"{RTL}/snpu_wshadow.v",
            f"{RTL}/snpu_pe_chain.v",
            f"{UNIT}/tb_pe_chain.sv",
        ],
        "needs_dsp_model": True,
        "group": "unit",
    },
    "tb_pe_chain_16": {
        "top": "tb_pe_chain",
        "files": [
            f"{RTL}/snpu_dsp_mac2.v",
            f"{RTL}/snpu_skew.v",
            f"{RTL}/snpu_wshadow.v",
            f"{RTL}/snpu_pe_chain.v",
            f"{UNIT}/tb_pe_chain.sv",
        ],
        "params": {"CHAIN_LEN": 16},
        "needs_dsp_model": True,
        "group": "unit",
    },
    "tb_conv_conv1x1": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv1x1", "sim/stalyanpu/stim/conv1x1"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv1x1", "+BACKPRESSURE=1"],
    },
    "tb_conv_conv3x3": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv3x3", "sim/stalyanpu/stim/conv3x3"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv3x3", "+BACKPRESSURE=1"],
    },
    "tb_conv_conv3x3s2": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv3x3s2", "sim/stalyanpu/stim/conv3x3s2"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv3x3s2", "+BACKPRESSURE=1"],
    },
    "tb_conv_conv_res": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv_res", "sim/stalyanpu/stim/conv_res"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv_res", "+BACKPRESSURE=1"],
    },
    "tb_conv_conv_pad80": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv_pad80", "sim/stalyanpu/stim/conv_pad80"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv_pad80", "+BACKPRESSURE=1"],
    },
    "tb_conv_conv_tiles": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "needs_dsp_model": True,
        "group": "layer",
        "gen": ["-m", "stalyanpu.golden.unit", "conv_tiles", "sim/stalyanpu/stim/conv_tiles"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv_tiles", "+BACKPRESSURE=1"],
    },
    "tb_conv_full": {
        "top": "tb_conv_unit",
        "files": CONV_FILES,
        "params": {"N_CHAIN": 32, "CHAIN_LEN": 32, "P_MAX": 1024, "P_W": 10, "IBUF_WORDS": 4096, "IBUF_AW": 12},
        "needs_dsp_model": True,
        "group": "layer_full",
        "gen": ["-m", "stalyanpu.golden.unit", "conv_full", "sim/stalyanpu/stim/conv_full"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/conv_full", "+BACKPRESSURE=1"],
    },
    "tb_net_demo": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "needs_dsp_model": True,
        "group": "net",
        "gen": ["-m", "stalyanpu.golden.demo", "net", "sim/stalyanpu/stim/demo_net"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/demo_net"],
        "plusargs_file": "sim/stalyanpu/stim/demo_net/run.txt",
    },
    "tb_layer_demo0": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "needs_dsp_model": True,
        "group": "net",
        "gen": ["-m", "stalyanpu.golden.demo", "layer", "sim/stalyanpu/stim/demo_l0", "0"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/demo_l0"],
        "plusargs_file": "sim/stalyanpu/stim/demo_l0/run.txt",
    },
    "tb_layer_demo1": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "needs_dsp_model": True,
        "group": "net",
        "gen": ["-m", "stalyanpu.golden.demo", "layer", "sim/stalyanpu/stim/demo_l1", "1"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/demo_l1"],
        "plusargs_file": "sim/stalyanpu/stim/demo_l1/run.txt",
    },
    "tb_layer_demo3": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "needs_dsp_model": True,
        "group": "net",
        "gen": ["-m", "stalyanpu.golden.demo", "layer", "sim/stalyanpu/stim/demo_l3", "3"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/demo_l3"],
        "plusargs_file": "sim/stalyanpu/stim/demo_l3/run.txt",
    },
    # Real YOLOv8s descriptors at the full geometry. They need .data/build/q_mse
    # (calibrated graph, not in git) and take long, so "all" skips them.
    "tb_yolo_l65": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "params": {"N_CHAIN": 32, "CHAIN_LEN": 32, "P_MAX": 1024, "P_W": 10, "IBUF_WORDS": 16384, "IBUF_AW": 14,
                   "WFIFO_WORDS": 1024, "WFIFO_AW": 10, "WIN0_WORDS": 1 << 20, "WIN1_WORDS": 1 << 20,
                   "MP_MAX_W": 128, "MP_W_AW": 7},
        "needs_dsp_model": True,
        "group": "yolo",
        "optional": True,
        "gen": ["-m", "stalyanpu", "golden", "--qgraph", ".data/build/q_mse", "--out", "sim/stalyanpu/stim/yolo_l65", "--layer", "65"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/yolo_l65", "+WATCHDOG=4000000"],
        "plusargs_file": "sim/stalyanpu/stim/yolo_l65/run.txt",
    },
    "tb_yolo_l26": {
        "top": "tb_npu_net",
        "files": TOP_FILES,
        "params": {"N_CHAIN": 32, "CHAIN_LEN": 32, "P_MAX": 1024, "P_W": 10, "IBUF_WORDS": 16384, "IBUF_AW": 14,
                   "WFIFO_WORDS": 1024, "WFIFO_AW": 10, "WIN0_WORDS": 1 << 20, "WIN1_WORDS": 1 << 20,
                   "MP_MAX_W": 128, "MP_W_AW": 7},
        "needs_dsp_model": True,
        "group": "yolo",
        "optional": True,
        "gen": ["-m", "stalyanpu", "golden", "--qgraph", ".data/build/q_mse", "--out", "sim/stalyanpu/stim/yolo_l26", "--layer", "26"],
        "plusargs": ["+VEC=sim/stalyanpu/stim/yolo_l26", "+WATCHDOG=4000000"],
        "plusargs_file": "sim/stalyanpu/stim/yolo_l26/run.txt",
    },
}
