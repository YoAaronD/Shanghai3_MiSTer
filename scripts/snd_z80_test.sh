#!/usr/bin/env bash
# Unit test of the heberpop/blocken sound CPU section (rtl/ga9201_sound.sv):
# a hand-assembled Z80 program exercises IM 0 latch interrupts, YM3438 timer
# NMIs, RAM and I/O writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_snd_z80"
verilator --cc --exe --build -O2 -j 2 -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
    -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-BLKANDNBLK -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-IMPLICIT \
    -Wno-PINCONNECTEMPTY -Wno-CASEX -Wno-SELRANGE -Wno-LATCH -Wno-COMBDLY \
    --top-module ga9201_sound --Mdir "$OBJ" \
    "$ROOT"/ext/jt12/hdl/jt12*.v "$ROOT"/ext/jt12/hdl/adpcm/*.v "$ROOT"/ext/jt49/hdl/jt49*.v \
    "$ROOT"/ext/tv80/tv80_core.v "$ROOT"/ext/tv80/tv80_alu.v "$ROOT"/ext/tv80/tv80_mcode.v "$ROOT"/ext/tv80/tv80_reg.v \
    "$ROOT/rtl/tv80_cen.v" "$ROOT/rtl/ga9201_sound.sv" \
    "$ROOT/sim/snd_z80/snd_z80_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }
"$OBJ/Vga9201_sound"
