# OpenEye upstream issue draft

Title: FPGA level conv test fails on main since July 2026 (psum_enable clear, PE rewrite)

Environment: Icarus Verilog 12, cocotb 2.0.1, Python 3.11, TensorFlow 2.21, Windows 11.
Harness: test/cocotb_fpga/OpenEye_FPGA_tb.py driven exactly like the Makefile run target
(generator, vh_file_creator, USE_INTERNAL_PARAMS_PE defines), LAYER=Convolution,
NUM_FILTERS=16, INPUT_SIZE_X=4, INPUT_SIZE_Y=2, INPUT_CHANNELS=4, CLUSTER_ROWS=1,
CLUSTER_COLUMNS=1, NUM_GLB_IACT=1, IACT_RAM_CELLS=4, BUFFER_WIDTH=9, DMA_BITWIDTH=32,
PARALLEL_MACS=1, SPARSITY_EN=0.

Observed on main (fe2f5ed): the test fails, every output word equals the bias that was
streamed in, so the PE array contributes nothing. A pristine checkout shows the same.

Bisect results:

1. ca5a7dc passes (2x2, FC layer from the Makefile of that time).
2. d19314a (Fix PSUM datapath bugs causing zero-output on GEMM/attention layers) breaks the
   conv test. The hunk that removes psum_enable_i_reg <= 0 at the top of PSUM_GET_RESULTS
   is responsible; reverting only that hunk makes d19314a pass again.
3. 1f29695 and 00893e0 move the raw_wght flag to stream_data[8]; conv breaks again until
   7abd08c and 6611d1f fix the bit position.
4. 8350a00 is fine, it only changes the Makefile layer to INPUT_SIZE_X=16, which does not
   fit this configuration (the test fails on 3531eb3 too with INPUT_SIZE_X=16).
5. 3531eb3 is the last commit that passes, with the one line psum_enable fix applied.
6. ff4f99f (Tested PE for Sparsity and Dense and SIMD and SISD) rewrites PE.v; ff4f99f,
   a030ba9 and 302f94e do not elaborate (delay_cluster outputs are not regs), and from
   9d1aba8 up to fe2f5ed the conv test fails again with bias only output.

Multi cluster: with CLUSTER_ROWS=2, CLUSTER_COLUMNS=2, DMA_BITWIDTH=64 the test fails on
3531eb3 as well. test/cocotb_fpga/test_single_layers.py cannot run at all because
generator.py needs BRANCHES, BUFFER_WIDTH and BUFFER_WIDTH_WGHT in the environment.

Additional findings while porting to an Efinity Titanium flow:

- generator.py removes the last comma with a seek that breaks in text mode on Windows.
- GET_PARAMETERS does not reset fsm_cycle before GET_ROUTER_CONFIG, so the multi cluster
  exit condition of GET_ROUTER_CONFIG is never reached.
- quant_exp and quant_mant are sliced with OFFSET_WIDTH, truncating the mantissa to 8 bits.
- PE.v uses the loop variable pmc after the loop ended (index PARALLEL_MACS) in two places.
- layer_parameters.py trans_cycles_psum and psum_output_words ignore
  different_kernels_per_calculation and disagree with the generated streams.

Patches for all of the above are on https://github.com/stalyatech/OpenEye branch
stalya-upstream (commit 21db525).
