#!/usr/bin/env bash
# End-to-end simulation: MiSTer-style ROM download -> SDRAM -> game boot.
# usage: scripts/sim_top.sh ROMDIR FRAMES [extra args, e.g. --frames-out DIR --every 30 --check-sdram]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_top"
ROMDIR="$1"; FRAMES="$2"

verilator --cc --exe --build -O2 -j 2 ${VFLAGS:-} \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN \
    -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-SYMRSVDWORD \
    --top-module shangha3_top --Mdir "$OBJ" \
    "$ROOT/ext/fx68k/fx68kAlu.sv" "$ROOT/ext/fx68k/uaddrPla.sv" "$ROOT/ext/fx68k/fx68k.sv" \
    "$ROOT"/ext/jt49/hdl/jt49*.v "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/rtl/shangha3_video_timing.sv" "$ROOT/rtl/shangha3_blitter.sv" \
    "$ROOT/rtl/shangha3_video.sv" "$ROOT/rtl/shangha3_mixer.sv" "$ROOT/rtl/shangha3_board.sv" \
    "$ROOT/rtl/sdram.sv" "$ROOT/rtl/shangha3_mem.sv" "$ROOT/rtl/shangha3_ddr_arb.sv" "$ROOT/rtl/shangha3_top.sv" \
    "$ROOT/sim/top_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }

cd "$ROOT/ext/fx68k"     # fx68k microcode files are loaded from the cwd
"$OBJ/Vshangha3_top" --roms "$ROMDIR" --frames "$FRAMES" "${@:3}"
