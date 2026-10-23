#!/usr/bin/env bash
# Replay a sound-register log (YM2149 + OKI writes with timestamps) through the
# core's own jt49 + jt6295 + shangha3_mixer, much faster than the full board.
#
#   scripts/snd_replay.sh LOG OUT.raw [OUT.wav]
#
# LOG: "<seconds> AYA|AYD|OKI <hex>" per line, e.g. from tools/mame/snd_regs.lua.
# OUT.raw: float32 x3 per 48 kHz sample: psg_snd, oki_snd, snd (mixed).
# About 12 s of run time per emulated second. Needs sim/roms/oki.bin.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_snd"
verilator --cc --exe --build -O3 -j 2 \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY \
    --top-module snd_top --Mdir "$OBJ" \
    "$ROOT/sim/snd/snd_top.sv" "$ROOT/rtl/shangha3_mixer.sv" \
    "$ROOT"/ext/jt49/hdl/jt49*.v "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/sim/snd/snd_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }
"$OBJ/Vsnd_top" "$1" "$ROOT/sim/roms/oki.bin" "$2" ${3:+"$3"}
