# Runs once after every full Quartus compile (POST_FLOW_SCRIPT_FILE in
# Shanghai3.qsf). Writes output_files/timing_paths.txt: every failing
# endpoint with its worst path (setup, then hold), one line each, so a
# timing failure can be diagnosed from one text file.
# Any problem here only prints a message; it never fails the compile.
if {[catch {
    set proj [lindex $quartus(args) 1]
    set rev  [lindex $quartus(args) 2]
    set sta  [file join $quartus(binpath) quartus_sta]
    set tcl  [file join [pwd] scripts quartus timing_paths_sta.tcl]
    exec $sta -t $tcl $proj $rev
} msg]} {
    puts "post_flow.tcl: timing path report not written: $msg"
}
