#!/usr/bin/env bash
# Pixel-exact unit test of the HDL blitter against the software model.
#   1. refmodel dumps RAM + frame buffer before/after selected blitter runs
#   2. the HDL blitter replays each run and must produce the same frame buffer
# usage: scripts/blit_test.sh [dump-every] [dump-max] [extra refmodel args...]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVERY="${1:-50}"
MAX="${2:-60}"
OBJ="$ROOT/sim/obj_blit"

[ -x "$ROOT/sim/refmodel/refmodel" ] || "$ROOT/scripts/build_refmodel.sh"
mkdir -p "$ROOT/sim/blits"
rm -f "$ROOT"/sim/blits/*
"$ROOT/sim/refmodel/refmodel" "$ROOT/sim/roms/prog.bin" 3600 /dev/null --no-rom-log \
    --gfx "$ROOT/sim/roms/blitter.bin" --dump-blits "$ROOT/sim/blits" \
    --dump-every "$EVERY" --dump-max "$MAX" "${@:3}" > /dev/null

verilator --cc --exe --build -O2 -j 2 -Wno-fatal \
    --top-module shangha3_blitter --Mdir "$OBJ" \
    "$ROOT/rtl/shangha3_blitter.sv" "$ROOT/sim/blit_tb.cpp" > "$OBJ.build.log" 2>&1 \
    || { tail -30 "$OBJ.build.log"; exit 1; }

"$OBJ/Vshangha3_blitter" --gfx "$ROOT/sim/roms/blitter.bin" --dir "$ROOT/sim/blits" --latency "${LATENCY:-8}"
