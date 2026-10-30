#!/usr/bin/env bash
# Replay MAME's heberpop/blocken sound log through jt12 + jt6295 + ga9201_mixer.
#   scripts/snd2_replay.sh LOG OKIROM GAME OUT.raw [OUT.wav]    (GAME 1 heberpop, 2 blocken)
# LOG from tools/mame/sound_log.lua. Env SND_SECONDS limits the length; SND_BALANCE the mix.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_snd2"
verilator --cc --exe --build -O3 -j 2 \
    -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-IMPLICIT -Wno-PINCONNECTEMPTY \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-CASEX -Wno-SELRANGE \
    --top-module snd2_top --Mdir "$OBJ" \
    "$ROOT/sim/snd2/snd2_top.sv" "$ROOT/rtl/ga9201_mixer.sv" \
    "$ROOT"/ext/jt12/hdl/jt12*.v "$ROOT"/ext/jt12/hdl/adpcm/*.v "$ROOT"/ext/jt49/hdl/jt49*.v "$ROOT"/ext/jt6295/hdl/jt6295*.v \
    "$ROOT/sim/snd2/snd2_tb.cpp" > "$OBJ.build.log" 2>&1 || { tail -30 "$OBJ.build.log"; exit 1; }
"$OBJ/Vsnd2_top" "$@"
