"""Test registry of the StalyaNPU simulation tree.

Each entry names a testbench top, the source files relative to the repository
root, extra defines and plusargs. ``needs_dsp_model`` adds the Efinity DSP48
simulation model unless the run uses the behavioural twin (--behav).
"""

RTL = "ip/stalyanpu/rtl"
COMMON = "sim/stalyanpu/common"
UNIT = "sim/stalyanpu/unit"

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
}
