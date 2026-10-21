#!/usr/bin/env bash
# Build and run the Verilator simulation.
#
#   scripts/sim.sh test            hand-made test ROM, checks results automatically
#   scripts/sim.sh game [frames]   real shangha3j program ROM (run romtool.py extract first)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj"
MODE="${1:-test}"
FRAMES="${2:-3}"

verilator --cc --exe --build -O2 -j 2 \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-SYMRSVDWORD \
    --top-module shangha3_board --Mdir "$OBJ" \
    "$ROOT/ext/fx68k/fx68kAlu.sv" "$ROOT/ext/fx68k/uaddrPla.sv" "$ROOT/ext/fx68k/fx68k.sv" \
    "$ROOT"/ext/jt49/hdl/jt49*.v \
    "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/rtl/shangha3_video_timing.sv" "$ROOT/rtl/shangha3_blitter.sv" \
    "$ROOT/rtl/shangha3_video.sv" "$ROOT/rtl/shangha3_board.sv" \
    "$ROOT/sim/tb_main.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }

# fx68k loads its microcode with $readmemb("microrom.mem"), relative to the cwd
cd "$ROOT/ext/fx68k"

case "$MODE" in
  test)
    python3 "$ROOT/scripts/make_test_rom.py" "$ROOT/sim/test_rom.bin"
    "$OBJ/Vshangha3_board" --prog "$ROOT/sim/test_rom.bin" --frames "$FRAMES" \
        --dsw1 A5 --trace "$ROOT/sim/test_trace.txt"
    python3 "$ROOT/scripts/check_test_trace.py" "$ROOT/sim/test_trace.txt" A5
    ;;
  game)
    "$OBJ/Vshangha3_board" --prog "$ROOT/sim/roms/prog.bin" --frames "$FRAMES" \
        --trace "$ROOT/sim/game_trace.txt" \
        --gfx "$ROOT/sim/roms/blitter.bin" --oki "$ROOT/sim/roms/oki.bin" "${@:3}"
    echo "trace written to sim/game_trace.txt"
    ;;
  *) echo "usage: $0 test|game [frames]"; exit 1 ;;
esac
