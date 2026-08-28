# StalyaNPU simulation tree

Runner: `python sim/stalyanpu/run_sim.py all|unit|<test> [--seed N] [--behav] [--dump] [-j N]`.
Tests are registered in `tests.py`. A test passes when its log holds exactly one
`<top>: PASS` line and no `FAIL` line.

- `common/tb_util.svh`: `TB_CHECK`, `TB_FINISH`, `TB_WATCHDOG` macros.
- `common/lfsr16.sv`: stall generator with the taps of `sim/openeye/tb_openeye_core.v`.
- `unit/`: unit testbenches (`tb_dsp_mac`, `tb_pe_chain`).
- `stim/unit/`: small committed vectors. Everything else under `stim/` is generated
  by the Python toolchain and ignored by git.
- `sim_build/`: compile output and logs, ignored by git.

The Efinix DSP48 model is taken from `C:/Programs/Efinity/2025.2/sim_models/verilog/efx_dsp48.v`
(override with the `SNPU_DSP_MODEL` environment variable). `--behav` selects the
behavioural twin inside `snpu_dsp_mac2.v` instead.

Details and PASS criteria: `docs/stalyanpu/verification-guide.md`.
