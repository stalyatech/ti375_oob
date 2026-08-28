// =============================================================================
// tb_util.svh
//
// Small helpers shared by the StalyaNPU testbenches. A testbench declares
// `integer errors, checks;` and uses TB_CHECK for every comparison. The run
// ends with TB_FINISH, which prints exactly one "<name>: PASS" or
// "<name>: FAIL" line that run_sim.py looks for.
// =============================================================================
`ifndef TB_UTIL_SVH
`define TB_UTIL_SVH

`define TB_CHECK(cond, msg) \
    begin \
        checks = checks + 1; \
        if (!(cond)) begin \
            errors = errors + 1; \
            if (errors <= 16) $display("FAIL @%0t: %s", $time, msg); \
        end \
    end

`define TB_FINISH(name) \
    begin \
        if (errors == 0) $display("%s: PASS (%0d checks)", name, checks); \
        else $display("%s: FAIL (%0d errors in %0d checks)", name, errors, checks); \
        $finish; \
    end

`define TB_WATCHDOG(name, cycles, clk) \
    initial begin \
        repeat (cycles) @(posedge clk); \
        $display("FAIL @%0t: watchdog expired", $time); \
        $display("%s: FAIL (watchdog)", name); \
        $finish; \
    end

`endif
