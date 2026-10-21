#!/usr/bin/env python3
"""Compare video frames captured from the HDL board against the reference model.

Each HDL frame is matched against reference frames within +/-WINDOW frames,
because the HDL blitter takes real time (new content can appear a frame
later) and CPU timing differs slightly between the two models.

usage: compare_frames.py HDL_DIR REF_DIR [window]
  REF_DIR should hold every frame:  refmodel ... --frames-out REF_DIR --every 1
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

hdl_dir, ref_dir = sys.argv[1], sys.argv[2]
window = int(sys.argv[3]) if len(sys.argv) > 3 else 3

def load(p):
    return np.array(Image.open(p)).astype(np.int16)

exact, offset, differ = 0, [], []
files = sorted(glob.glob(os.path.join(hdl_dir, "frame_*.ppm")))
for f in files:
    n = int(os.path.basename(f)[6:11])
    h = load(f)
    best = None
    for o in range(-window, window + 1):
        rp = os.path.join(ref_dir, f"frame_{n + o:05d}.ppm")
        if not os.path.exists(rp):
            continue
        d = int((np.abs(h - load(rp)).sum(axis=2) > 0).sum())
        if best is None or d < best[0] or (d == best[0] and abs(o) < abs(best[1])):
            best = (d, o)
    if best is None:
        continue
    if best[0] == 0 and best[1] == 0:
        exact += 1
    elif best[0] == 0:
        offset.append((n, best[1]))
    else:
        differ.append((n, best[0], best[1]))

print(f"{len(files)} frames compared")
print(f"  identical to the same reference frame:      {exact}")
print(f"  identical to a reference frame +/-{window}:      {len(offset)}  {offset}")
print(f"  no identical reference frame nearby:        {len(differ)}")
for n, d, o in differ:
    print(f"    frame {n}: closest is ref {n + o} with {d} pixels different")
sys.exit(1 if differ else 0)
