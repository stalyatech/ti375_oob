# Offline stimulus and golden reference generator for tb_openeye_core.
#
# Reuses the OpenEye Python verification stack in its ONLY_FILES mode: the
# layer model, the dma_i word stream and the expected dma_o beats are all
# produced without a simulator, then converted to $readmemh format.
#
# Run from the project root with the Efinity bundled Python 3.11 and the
# project local package directory:
#   PYTHONHOME="C:/Programs/Efinity/2025.2/python311" \
#   PYTHONPATH=".pydeps-openeye;ip/OpenEye/src" \
#   "C:/Programs/Efinity/2025.2/python311/bin/python.exe" sim/openeye/gen_stimulus.py
#
# Outputs land in sim/openeye/stim/: dma_stim.hex, dma_golden.hex and the raw
# demo/ tree from the OpenEye toolchain. The geometry below must match the
# open_eye_mt_v1_0 instantiation in ti375_oob_top.v, which uses the wrapper
# defaults.

import os
import sys

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STIM_DIR = os.path.join(PROJECT_ROOT, "sim", "openeye", "stim")

# Geometry and layer selection. Environment variables are read by the OpenEye
# modules at import time, so everything is set before the imports below.
GEN_ENV = {
    "ONLY_FILES": "1",
    "LOGGER_LEVEL": "20",
    # Geometry, must match the RTL instantiation defaults.
    "CLUSTER_ROWS": "2",
    "CLUSTER_COLUMNS": "2",
    "NUM_GLB_IACT": "3",
    "NUM_GLB_WGHT": "3",
    "NUM_GLB_PSUM": "4",
    "RAM_CELLS": "8",
    "BUFFER_WIDTH": "10",
    "BRANCHES": "1",
    "QUANT_AMOUNT": "32",
    "PARALLEL_MACS": "2",
    # Data widths, upstream Makefile defaults.
    "DATA_IACT_BITWIDTH": "8",
    "DATA_PSUM_BITWIDTH": "32",
    "DATA_WGHT_BITWIDTH": "8",
    "DATA_IACT_OVERHEAD": "4",
    "DATA_WGHT_IGNORE_ZEROS": "4",
    "TRANS_BITWIDTH_IACT": "24",
    "TRANS_BITWIDTH_WGHT": "24",
    "TRANS_BITWIDTH_PSUM": "32",
    "IACT_PER_PE": "16",
    "PE_IACT_ADDR_ADDR": "9",
    "WGHT_PER_PE": "96",
    "PE_WGHT_ADDR_ADDR": "16",
    "PSUM_PER_PE": "32",
    # Layer under test. Small enough for the reduced buffer geometry.
    "LAYER": os.environ.get("LAYER", "Convolution"),
    "NUM_FILTERS": os.environ.get("NUM_FILTERS", "8"),
    "KERNEL_SIZE_X": os.environ.get("KERNEL_SIZE_X", "3"),
    "KERNEL_SIZE_Y": os.environ.get("KERNEL_SIZE_Y", "3"),
    "INPUT_SIZE_X": os.environ.get("INPUT_SIZE_X", "8"),
    "INPUT_SIZE_Y": os.environ.get("INPUT_SIZE_Y", "8"),
    "INPUT_CHANNELS": os.environ.get("INPUT_CHANNELS", "4"),
    "OUTPUT_SIZE": os.environ.get("OUTPUT_SIZE", "32"),
    "STRIDE": os.environ.get("STRIDE", "1"),
    "USE_RANDOM_VALUES": "1",
    "USE_SPARSE_IACTS": "0",
    "USE_SPARSE_WEIGHTS": "0",
}


def generate():
    os.environ.update(GEN_ENV)
    os.makedirs(STIM_DIR, exist_ok=True)
    # The OpenEye writers use relative demo/ paths, so run inside the stim dir.
    os.chdir(STIM_DIR)

    import random
    import numpy as np
    import tensorflow as tf

    # Fixed seeds so the committed stimulus is reproducible.
    random.seed(1)
    np.random.seed(1)
    tf.random.set_seed(1)

    import open_eye.generic_test_utils as gtu
    import open_eye.open_eye_parameters as oep
    import open_eye.layer_parameters as lp
    import open_eye.DRAM as DRAM
    import open_eye.test_utils_main as tum
    import open_eye.simple_layer_operations as slo
    import open_eye.data_create as data_create

    layer_mode = os.environ["LAYER"]
    filters = int(os.environ["NUM_FILTERS"])
    ksx = int(os.environ["KERNEL_SIZE_X"])
    ksy = int(os.environ["KERNEL_SIZE_Y"])
    isx = int(os.environ["INPUT_SIZE_X"])
    isy = int(os.environ["INPUT_SIZE_Y"])
    outputsize = int(os.environ["OUTPUT_SIZE"])
    stride = int(os.environ["STRIDE"])
    channels = int(os.environ["INPUT_CHANNELS"])
    strides = (stride, stride)
    sparse_iacts = 0
    sparse_wghts = 0
    serial = 1

    model = data_create.create_layer(
        layer_mode, filters, ksx, ksy, isx, isy, strides, channels, outputsize)
    trunc_model = [
        layer for layer in model.layers
        if not isinstance(layer, tf.keras.layers.Flatten)
    ]

    # The remainder mirrors execute_model() from OpenEye_FPGA_tb.py with
    # only_files=1, stripped of every cocotb interaction.
    openeye_parameter = oep.get_oep(serial)
    gtu.delete_files_in_directory("demo/")

    max_layers = len(trunc_model)
    layer_parameters = [0 for _ in range(max_layers)]
    for layer_number, layer in reversed(list(enumerate(trunc_model))):
        layer_parameters[max_layers - layer_number - 1] = lp.LayerParameters(
            layer_parameters, layer, openeye_parameter, layer_number, max_layers)
    layer_parameters = list(reversed(layer_parameters))

    dram = DRAM.DRAMContents(trunc_model, layer_parameters)
    dram.write_initial_data_to_dram(trunc_model, layer_parameters, sparse_iacts, sparse_wghts)

    reps_per_layer = []
    for layer_number, layer in enumerate(trunc_model):
        lpar = layer_parameters[layer_number]
        calculated_results = tum.collect_results(
            layer_number, lpar, dram, openeye_parameter.SERIAL)
        tum.make_ref(openeye_parameter, lpar, layer_number, dram, calculated_results)
        dram_layer_content = [dram.fmap[layer_number], dram.weights[layer_number], dram.bias[layer_number]]
        stream = tum.write_stream(
            openeye_parameter, lpar, dram_layer_content, sparse_iacts, sparse_wghts)
        reps_per_layer.append(lpar.needed_total_transmissions)
        for layer_repetition in range(lpar.needed_total_transmissions):
            gtu.create_stream_file(stream[layer_repetition], layer_number, layer_repetition)
        if layer_number == max_layers - 1:
            dram.fmap[1 + layer_number] = tum.fill_dram_with_ref(
                calculated_results, dram.fmap[1 + layer_number],
                lpar, layer_parameters[layer_number + 1] if layer_number + 1 < max_layers else lpar)
        if lpar.layer_name != "Pooling":
            slo.batchnorm_output(lpar, 1, layer_number, dram)

    print(f"layers: {max_layers}, transmissions per layer: {reps_per_layer}")

    # Convert layer 0 files to $readmemh format. Multiple transmissions of the
    # same layer are concatenated in send order, which matches how gDMA_dnn
    # would stream consecutive descriptor chains.
    stim_words = []
    gold_words = []
    for rep in range(reps_per_layer[0]):
        in_path = os.path.join("demo", f"layer_0_{rep}", "dma_stream_input.txt")
        ref_path = os.path.join("demo", f"layer_0_{rep}", "dma_stream_ref.txt")
        with open(in_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    stim_words.append(int(line) & ((1 << 64) - 1))
        with open(ref_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    gold_words.append(int(line, 2) & ((1 << 64) - 1))

    with open("dma_stim.hex", "w") as f:
        for w in stim_words:
            f.write(f"{w:016x}\n")
    with open("dma_golden.hex", "w") as f:
        for w in gold_words:
            f.write(f"{w:016x}\n")

    print(f"dma_stim.hex: {len(stim_words)} words")
    print(f"dma_golden.hex: {len(gold_words)} words")


if __name__ == "__main__":
    generate()
