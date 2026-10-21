#!/usr/bin/env bash
# Build the software reference model (Musashi 68000 + MAME's memory map).
# Then run:  sim/refmodel/refmodel sim/roms/prog.bin 1500 sim/ref_trace.txt --no-rom-log
#            scripts/compare_traces.py sim/game_trace.txt sim/ref_trace.txt
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/ext/Musashi"
[ -d "$M" ] || git clone --depth 1 https://github.com/kstenerud/Musashi "$M"
cd "$M"
[ -f m68kops.c ] || { gcc -O1 -o m68kmake m68kmake.c && ./m68kmake . m68k_in.c; }
gcc -O2 -w -I"$M" -o "$ROOT/sim/refmodel/refmodel" "$ROOT/sim/refmodel/refmodel.c" "$ROOT/sim/refmodel/blitter.c" \
    m68kcpu.c m68kops.c m68kdasm.c softfloat/softfloat.c -lm
echo "built sim/refmodel/refmodel"
