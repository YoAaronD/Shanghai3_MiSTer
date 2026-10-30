#!/usr/bin/env bash
# Build and run the Verilator simulation.
#
#   scripts/sim.sh test            hand-made test ROM, checks results automatically
#   scripts/sim.sh game [frames] [args]   real game ROMs from $SIM_ROMS (default sim/roms):
#       prog.bin, blitter.bin, oki.bin, z80.bin (scripts/stream_split.py, or romtool.py
#       extract for shangha3j). Pass --game 1 (heberpop) or 2 (blocken) for the new games.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="${SIM_OBJ:-$ROOT/sim/obj}"
MODE="${1:-test}"
FRAMES="${2:-3}"

verilator --cc --exe --build -O2 -j 2 \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-SYMRSVDWORD -Wno-IMPLICIT -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-CASEX -Wno-SELRANGE \
    --top-module shangha3_board --Mdir "$OBJ" \
    "$ROOT/ext/fx68k/fx68kAlu.sv" "$ROOT/ext/fx68k/uaddrPla.sv" "$ROOT/ext/fx68k/fx68k.sv" \
    "$ROOT"/ext/jt49/hdl/jt49*.v \
    "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/rtl/shangha3_video_timing.sv" "$ROOT/rtl/shangha3_blitter.sv" \
    "$ROOT/rtl/shangha3_video.sv" "$ROOT/rtl/shangha3_mixer.sv" "$ROOT/rtl/shangha3_board.sv" \
    "$ROOT"/ext/jt12/hdl/jt12*.v "$ROOT"/ext/jt12/hdl/adpcm/*.v \
    "$ROOT"/ext/tv80/tv80_core.v "$ROOT"/ext/tv80/tv80_alu.v "$ROOT"/ext/tv80/tv80_mcode.v "$ROOT"/ext/tv80/tv80_reg.v \
    "$ROOT/rtl/tv80_cen.v" "$ROOT/rtl/ga9201_sound.sv" "$ROOT/rtl/ga9201_mixer.sv" \
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
    R="${SIM_ROMS:-$ROOT/sim/roms}"
    Z=(); [ -f "$R/z80.bin" ] && Z=(--z80 "$R/z80.bin")
    "$OBJ/Vshangha3_board" --prog "$R/prog.bin" --frames "$FRAMES" \
        --trace "${SIM_TRACE:-$ROOT/sim/game_trace.txt}" \
        --gfx "$R/blitter.bin" --oki "$R/oki.bin" "${Z[@]}" "${@:3}"
    echo "trace written to sim/game_trace.txt"
    ;;
  *) echo "usage: $0 test|game [frames]"; exit 1 ;;
esac
