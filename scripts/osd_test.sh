#!/usr/bin/env bash
# MiSTer OSD info box ("Loading ..." progress box) over the core's video, with
# CRT Adjust Off and at several settings. Uses the framework's own sys/osd.v
# (a sim-only copy in sim/obj_osd/, with two in-block initializers moved so
# Verilator keeps them static) fed by the core's timing -> s3_crt_adjust.
# Prints box and text pixel counts per setting; text must be > 0 everywhere.
#   scripts/osd_test.sh [OUTDIR]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_osd"
mkdir -p "$OBJ"; OUT="${1:-$OBJ/frames}"; mkdir -p "$OUT"
sed -e 's/\treg \[21:0\] cnt = 0;/\treg [21:0] cnt;/' -e 's/\treg        highres = 0;/\treg        highres;/' \
    "$ROOT/sys/osd.v" > "$OBJ/osd_sim.v"
verilator --cc --exe --build -O2 -j 2 \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN \
    -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-SYMRSVDWORD \
    --top-module osd_top --Mdir "$OBJ" "$ROOT/sim/osd/osd_top.sv" "$ROOT/rtl/shangha3_video_timing.sv" \
    "$ROOT/rtl/s3_crt_adjust.sv" "$ROOT/rtl/vendor/crt_adjust.sv" "$OBJ/osd_sim.v" \
    "$ROOT/sim/osd/osd_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }
fail=0
# CRT Adjust on/off, H-Size index, H-Position index, V-Shift index (OSD bit values)
for cfg in "0 0 0 0" "1 0 0 0" "1 5 3 3" "1 10 7 7" "1 11 8 8" "1 23 15 15"; do
    set -- $cfg
    line=$("$OBJ/Vosd_top" "$OUT/osd_$1_$2_$3_$4.ppm" "$1" "$2" "$3" "$4" | tail -1)
    echo "$line"
    case "$line" in *"text pixels 0"*) fail=1 ;; esac
done
[ $fail = 0 ] && echo "PASS: OSD text visible at every setting" || { echo "FAIL"; exit 1; }
