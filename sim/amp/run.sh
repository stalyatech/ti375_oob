#!/bin/bash
# Run the AMP / bus-routing testbenches with Icarus Verilog.
#
#   sim/amp/run.sh            all testbenches, then the top-level check
#   sim/amp/run.sh amp_ctrl   one of: amp_ctrl axi_addr_split axi_err_slave top
#
# "top" elaborates ti375_oob_top.v against port-only stubs of the encrypted
# IP (make_stubs.py). It fails on any elaboration error and on any implicit
# net, which in this design means a misspelt wire.
#
# IVERILOG_BIN overrides where iverilog/vvp are found (default: PATH, then the
# local build under /media/tmk/uniwork/tools/iverilog).

set -u
cd "$(dirname "$0")"
RTL=../../rtl

if [ -n "${IVERILOG_BIN:-}" ]; then
    PATH="$IVERILOG_BIN:$PATH"
elif ! command -v iverilog >/dev/null 2>&1; then
    PATH="/media/tmk/uniwork/tools/iverilog/bin:$PATH"
fi
command -v iverilog >/dev/null 2>&1 || { echo "iverilog not found (set IVERILOG_BIN)"; exit 2; }

declare -A SRC=(
    [amp_ctrl]="$RTL/amp_ctrl.v"
    [axi_addr_split]="$RTL/axi_addr_split.v"
    [axi_err_slave]="$RTL/axi_err_slave.v"
)

run() {
    local tb=$1 out rc
    iverilog -g2012 -o "tb_$tb.vvp" "tb_$tb.v" ${SRC[$tb]} 2>&1 | grep -vE "timescale|inherit|sensitive to all"
    out=$(vvp -n "tb_$tb.vvp" 2>&1)
    rc=$?
    echo "$out" | grep -E "^FAIL|passed|timeout|FATAL"
    return $rc
}

STUBS=(
    gAXIS_1to2_switch=ip/gAXIS_1to2_switch/gAXIS_1to2_switch.v
    gAXIM_5to1_switch=ip/gAXIM_5to1_switch/gAXIM_5to1_switch.v
    gSDHC=ip/gSDHC/gSDHC.v
    tseCore=rtl/tseCore.v
    gDMA=ip/gDMA/gDMA.v
    snpu_apb_demux=ip/stalyanpu/rtl/snpu_apb_demux.v
    snpu_top=ip/stalyanpu/rtl/snpu_top.v
    snpu_axi_up512=ip/stalyanpu/rtl/snpu_axi_up512.v
    EfxSapphireHpSoc_slb=ip/EfxSapphireHpSoc_slb/EfxSapphireHpSoc_slb.v
    EfxSapphireFCU=ip/EfxSapphireFCU/EfxSapphireFCU.v
)

run_top() {
    local proj=../.. log=top_elab.log n
    (cd "$proj" && python3 sim/amp/make_stubs.py . sim/amp/top_stubs.v "${STUBS[@]}") || return 1
    (cd "$proj" && iverilog -g2012 -Wimplicit -Wportbind -I . -s ti375_oob_top -o sim/amp/top_elab.vvp \
        ti375_oob_top.v sim/amp/top_stubs.v rtl/snpu_apb_cdc.v \
        rtl/amp_ctrl.v rtl/axi_addr_split.v rtl/axi_err_slave.v) > "$log" 2>&1
    local rc=$?
    n=$(grep -ci "implicit" "$log")
    if [ $rc -ne 0 ]; then
        grep -i error "$log"; echo "top: elaboration FAILED"; return 1
    elif [ "$n" -ne 0 ]; then
        grep -i implicit "$log"; echo "top: $n implicit net(s) - a wire is misspelt or undeclared"; return 1
    fi
    echo "top: elaborates, no implicit nets ($(grep -ci warning "$log") pre-existing width warnings, see $log)"
}

tbs=${1:-amp_ctrl axi_addr_split axi_err_slave top}
failed=0
for tb in $tbs; do
    if [ "$tb" = top ]; then run_top || failed=1; else run "$tb" || failed=1; fi
done
exit $failed
