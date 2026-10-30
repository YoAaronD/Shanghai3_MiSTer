#!/usr/bin/env bash
# End-to-end simulation: MiSTer-style ROM download -> SDRAM -> game boot.
# usage: scripts/sim_top.sh MRA ROMDIR FRAMES [extra args, e.g. --frames-out DIR --every 30 --check-sdram]
#   The download stream and the game select byte are built from the MRA itself
#   (scripts/mra_stream.py), so this also checks the MRA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_top"
MRA="$1"; ROMDIR="$2"; FRAMES="$3"
STREAM="$OBJ/stream.bin"     # inside sim/obj_top/ (gitignored: it holds ROM data)
mkdir -p "$OBJ"
GAME=$(python3 "$ROOT/scripts/mra_stream.py" "$MRA" "$ROMDIR" "$STREAM" | tee /dev/stderr | sed -n 's/^index 1: //p')
GAME=$((16#${GAME:-00}))

verilator --cc --exe --build -O2 -j 2 ${VFLAGS:-} \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN \
    -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-SYMRSVDWORD -Wno-IMPLICIT -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-CASEX -Wno-SELRANGE \
    --top-module shangha3_top --Mdir "$OBJ" \
    "$ROOT/ext/fx68k/fx68kAlu.sv" "$ROOT/ext/fx68k/uaddrPla.sv" "$ROOT/ext/fx68k/fx68k.sv" \
    "$ROOT"/ext/jt49/hdl/jt49*.v "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/rtl/shangha3_video_timing.sv" "$ROOT/rtl/shangha3_blitter.sv" \
    "$ROOT/rtl/shangha3_video.sv" "$ROOT/rtl/shangha3_mixer.sv" "$ROOT/rtl/shangha3_board.sv" \
    "$ROOT"/ext/jt12/hdl/jt12*.v "$ROOT"/ext/jt12/hdl/adpcm/*.v \
    "$ROOT"/ext/tv80/tv80_core.v "$ROOT"/ext/tv80/tv80_alu.v "$ROOT"/ext/tv80/tv80_mcode.v "$ROOT"/ext/tv80/tv80_reg.v \
    "$ROOT/rtl/tv80_cen.v" "$ROOT/rtl/ga9201_sound.sv" "$ROOT/rtl/ga9201_mixer.sv" \
    "$ROOT/rtl/sdram.sv" "$ROOT/rtl/shangha3_mem.sv" "$ROOT/rtl/shangha3_ddr_arb.sv" "$ROOT/rtl/shangha3_top.sv" \
    "$ROOT/sim/top_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }

cd "$ROOT/ext/fx68k"     # fx68k microcode files are loaded from the cwd
"$OBJ/Vshangha3_top" --stream "$STREAM" --game "$GAME" --frames "$FRAMES" "${@:4}"
