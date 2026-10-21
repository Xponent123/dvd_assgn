# Run from the submission root: sta -exit sta/sta.tcl
# First run: T=10 ns. Override STA_PERIOD for the measured minimum-period check.
if {![info exists ::env(PDK_ROOT)]} {error "PDK_ROOT is not set"}
set lib [file join $::env(PDK_ROOT) sky130A libs.ref sky130_fd_sc_hd lib sky130_fd_sc_hd__tt_025C_1v80.lib]
set T 10.0
if {[info exists ::env(STA_PERIOD)]} {set T $::env(STA_PERIOD)}

read_liberty $lib
read_verilog synth/mult_array_netlist.v
link_design mult_array
create_clock -name clk -period $T [get_ports clk]
set_input_delay 1.0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 1.0 -clock clk [all_outputs]
report_worst_slack -max -digits 3
report_checks -path_delay max -digits 3 > sta/mult_array_timing.rpt
