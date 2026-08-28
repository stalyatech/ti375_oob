"""StalyaNPU toolchain package.

Subpackages:
    hwcfg     hardware geometry and timing constants shared by every tool
    perf      analytic cycle model and YOLOv8s layer table
    frontend  ONNX import and lowering to the accelerator op set
    backend   descriptor ISA, blob layout and the generated C header
    refmodel  bit exact integer arithmetic used by hardware and compiler
"""

__version__ = "0.1.0"
