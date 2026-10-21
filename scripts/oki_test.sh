#!/usr/bin/env bash
# OKI samples through the real ROM path (download -> SDRAM -> memory hub) vs. direct ROM.
# usage: scripts/oki_test.sh [--no-stress] [--wav out.wav]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_oki"
verilator --cc --exe --build -O2 -j 2 --public-flat-rw -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
    -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-BLKANDNBLK -Wno-INITIALDLY -Wno-MULTIDRIVEN \
    --top-module oki_bench --Mdir "$OBJ" \
    "$ROOT"/ext/jt6295/hdl/jt6295*.v "$ROOT/rtl/sdram.sv" "$ROOT/rtl/shangha3_mem.sv" \
    "$ROOT/sim/oki_bench.sv" "$ROOT/sim/oki_tb.cpp" > "$OBJ.build.log" 2>&1 \
    || { tail -30 "$OBJ.build.log"; exit 1; }
"$OBJ/Voki_bench" --oki "$ROOT/sim/roms/oki.bin" "$@"
