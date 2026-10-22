# Called by post_flow.tcl through quartus_sta. Can also be run by hand:
#   quartus_sta -t scripts/quartus/timing_paths_sta.tcl Shanghai3 Shanghai3
set proj [lindex $quartus(args) 0]
set rev  [lindex $quartus(args) 1]
project_open $proj -revision $rev
create_timing_netlist
read_sdc
update_timing_netlist
set out output_files/timing_paths.txt
file delete -force $out
report_timing -setup -npaths 2000 -nworst 1 -less_than_slack 0 -detail summary -file $out
report_timing -hold  -npaths 2000 -nworst 1 -less_than_slack 0 -detail summary -file $out -append
delete_timing_netlist
project_close
