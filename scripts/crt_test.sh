#!/usr/bin/env bash
# CRT Adjust bench on the Shanghai III raster: sweeps every H-Size at both
# H-Position extremes plus V-Shift, and checks sync stability and picture integrity.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJ="$ROOT/sim/obj_crt"
verilator --binary --timing -O2 -j 2 -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL -Wno-INITIALDLY -Wno-BLKANDNBLK \
    --top-module tb_crt --Mdir "$OBJ" \
    "$ROOT/rtl/shangha3_video_timing.sv" "$ROOT/rtl/vendor/crt_adjust.sv" \
    "$ROOT/rtl/s3_crt_adjust.sv" "$ROOT/sim/tb_crt.sv" > "$OBJ.build.log" 2>&1 \
    || { tail -30 "$OBJ.build.log"; exit 1; }
"$OBJ/Vtb_crt"
