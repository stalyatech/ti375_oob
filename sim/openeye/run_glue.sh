#!/bin/sh
# Compile and run the OpenEye control-plane glue testbench with Icarus Verilog.
# Options must precede file names, this iverilog build does not permute args.
# Usage: sim/openeye/run_glue.sh [+DUMP]
set -e
cd "$(dirname "$0")/../.."

mkdir -p sim/openeye/sim_build
iverilog -g2012 -s tb_openeye_glue -o sim/openeye/sim_build/glue.vvp rtl/apb3_2_axi4_lite.v rtl/open_eye_mt_v1_0_cfg_reg.v rtl/openeye_irq.v rtl/pulse_sync.v sim/openeye/tb_openeye_glue.v
vvp sim/openeye/sim_build/glue.vvp -fst "$@"
