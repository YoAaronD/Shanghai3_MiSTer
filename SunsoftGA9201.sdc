derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# fx68k (68000) runs from the 96 MHz system clock, but its registers only
# update on the enPhi1/enPhi2 clock enables, which this core pulses every
# 3rd clock (16 MHz CPU). Register-to-register paths inside the CPU therefore
# have 3 clocks (31 ns); fx68k's own notes give ~40 MHz for single-cycle use.
# Only paths that start AND end inside the CPU are relaxed. Paths from the
# board logic into the CPU (enables, reset, data bus) stay single-cycle.
# (The microcode ROM output registers update every clock, but their paths
# are short ROM-to-register hops that meet 96 MHz with plenty of margin.)
set cpu_regs [get_keepers -nowarn {*|fx68k:u_cpu|*}]
if {[get_collection_size $cpu_regs] > 0} {
    set_multicycle_path -setup -end 3 -from $cpu_regs -to $cpu_regs
    set_multicycle_path -hold  -end 2 -from $cpu_regs -to $cpu_regs
}

# tv80 (sound Z80 of Hebereke no Popoon / Blocken): every register inside it
# updates only on its clock enable (cen, every 16th clock = 6 MHz; ClkEn =
# cen && !BusAck, the register file's CEN, the bus block in tv80_cen.v).
# Internal register-to-register paths therefore have 16 clocks; 4 is used.
# Paths from outside (wait_n, int_n, di, reset) stay single-cycle.
set z80_regs [get_keepers -nowarn {*|tv80_cen:u_z80|*}]
if {[get_collection_size $z80_regs] > 0} {
    set_multicycle_path -setup -end 4 -from $z80_regs -to $z80_regs
    set_multicycle_path -hold  -end 3 -from $z80_regs -to $z80_regs
}
