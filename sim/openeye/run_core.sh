#!/bin/sh
# Compile and run the OpenEye core testbench with Icarus Verilog.
# Options must precede file names, this iverilog build does not permute args.
# Usage: sim/openeye/run_core.sh [+BACKPRESSURE] [+DUMP] [+STIM=...] [+GOLD=...]
set -e
cd "$(dirname "$0")/../.."

mkdir -p sim/openeye/sim_build
iverilog -g2012 -DUSE_INTERNAL_PARAMS -s tb_openeye_core -o sim/openeye/sim_build/core.vvp -I ip/OpenEye/hdl -I ip/OpenEye/hdl/include -f sim/openeye/openeye_core.f ip/OpenEye/fpga/hdl/open_eye_axi_v1_0.v rtl/open_eye_mt_v1_0_cfg_reg.v rtl/openeye_irq.v sim/openeye/tb_openeye_core.v
vvp sim/openeye/sim_build/core.vvp -fst "$@"
