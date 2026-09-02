# StalyaNPU synthesis check constraints.
# The PLL reference is 125 MHz on clk_in, the engine clock is 250 MHz on clk.
create_clock -period 8.0000 clk_fb
create_clock -period 4.0000 clk
set_false_path -from [get_ports {rst_i sin}]
set_false_path -to [get_ports {sout}]
