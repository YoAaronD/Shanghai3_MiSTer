#!/usr/bin/env python3
"""Match simulation frames against MAME frames over a window of frame lags.

    scripts/mame_frame_match.py SIM_DIR MAME_DIR FRAME [FRAME ...] [--lag LO HI]

SIM_DIR: frame_%05d.ppm from `sim.sh game ... --frames-out` or `sim_top.sh`.
MAME_DIR: f%05d.png from tools/mame/frame_log.lua.
For each simulation frame, prints the three best MAME frames (sim frame - lag)
and the share of differing pixels; 0.000 % means pixel-identical.
heberpop matched at lag 9 (boot ~8 frames slower than MAME + the core's
one-frame display delay).
"""
import sys, os
import numpy as np
from PIL import Image
args = sys.argv[1:]
lo, hi = 0, 15
if '--lag' in args:
    i = args.index('--lag'); lo, hi = int(args[i + 1]), int(args[i + 2]); del args[i:i + 3]
sim_dir, mame_dir, frames = args[0], args[1], [int(a) for a in args[2:]]
for s in frames:
    a = np.asarray(Image.open(os.path.join(sim_dir, f'frame_{s:05d}.ppm')).convert('RGB')).astype(int)
    res = []
    for lag in range(lo, hi + 1):
        p = os.path.join(mame_dir, f'f{s - lag:05d}.png')
        if not os.path.exists(p): continue
        b = np.asarray(Image.open(p).convert('RGB')).astype(int)
        res.append(((np.abs(a - b).sum(2) > 0).mean(), lag))
    res.sort()
    print(s, '  '.join(f'lag {l}: {100*d:.3f}%' for d, l in res[:3]))
