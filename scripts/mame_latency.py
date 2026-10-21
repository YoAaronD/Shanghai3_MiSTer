#!/usr/bin/env python3
"""Frame latency of the HDL core relative to real MAME.

Inputs
  MAME_DIR  output of tools/mame/frame_log.lua: f00001.png ... + log.txt
  HDL_DIR   board-sim frames saved with --frames-out HDL_DIR --every 1
  HDL_TRACE the board-sim trace (--trace), for FRAME and BLITTER_GO events

Method
  Both sides log every blitter start ("go"). For an HDL frame, the number of
  gos issued before it was captured is jH; for the MAME frame showing the
  identical picture, it is jM. jH - jM is how many blitter runs later the
  HDL shows the same picture. With one blitter run per frame (true while the
  game animates), that is the extra latency in frames: 0 = same as MAME.
  Only frames that differ from both neighbours are used, so a picture
  identifies one moment of the game.

usage: mame_latency.py MAME_DIR HDL_DIR HDL_TRACE [first last]
"""
import bisect
import collections
import glob
import os
import re
import sys

import numpy as np
from PIL import Image

mame_dir, hdl_dir, trace = sys.argv[1:4]
first = int(sys.argv[4]) if len(sys.argv) > 4 else 1
last = int(sys.argv[5]) if len(sys.argv) > 5 else 10**9


def load(p):
    a = np.array(Image.open(p).convert("RGB")).astype(np.int16)
    return a >> 3          # compare at 5 bits per channel (palette precision)


def same(a, b):
    if a.shape != b.shape:
        return False
    return (np.abs(a - b).max(axis=2) > 1).sum() <= a.shape[0] * a.shape[1] // 1000


# --- MAME log
m_go = []                  # snapshots saved before each go
for line in open(os.path.join(mame_dir, "log.txt")):
    m = re.match(r"GO \d+ snaps=(\d+)", line)
    if m:
        m_go.append(int(m.group(1)))
m_files = {int(os.path.basename(f)[1:6]): f for f in glob.glob(os.path.join(mame_dir, "f*.png"))}

# --- HDL trace
h_go, frame = [], 0
for line in open(trace):
    if " EV FRAME " in line:
        frame += 1
    elif " EV BLITTER_GO" in line:
        h_go.append(frame)
h_files = {int(os.path.basename(f)[6:11]): f for f in glob.glob(os.path.join(hdl_dir, "frame_*.ppm"))}

print(f"MAME: {len(m_files)} frames, {len(m_go)} blitter starts;  HDL: {len(h_files)} frames, {len(h_go)} blitter starts")

cache = {}
def img(kind, n):
    key = (kind, n)
    if key not in cache:
        files = m_files if kind == "m" else h_files
        cache[key] = load(files[n]) if n in files else None
    return cache[key]

results = collections.Counter()
examples = []
mame_frames = sorted(m_files)
for k in sorted(h_files):
    if not (first <= k <= last):
        continue
    a, p, n = img("h", k), img("h", k - 1), img("h", k + 1)
    if p is None or n is None or same(a, p) or same(a, n) or a.max() == 0:
        continue
    jH = bisect.bisect_left(h_go, k)               # gos before frame k was captured
    # MAME frames around the same game moment
    matches = []
    for s in mame_frames:
        jM_s = bisect.bisect_left(m_go, s)
        if abs(jM_s - jH) > 6:
            continue
        b = img("m", s)
        if b is not None and same(a, b):
            matches.append(s)
    if len(matches) != 1:
        results["ambiguous" if matches else "no match"] += 1
        continue
    s = matches[0]
    jM = bisect.bisect_left(m_go, s)
    results[jH - jM] += 1
    if len(examples) < 8:
        examples.append((k, jH, s, jM))

print("HDL frame / gos before it  ->  matching MAME frame / gos before it")
for k, jH, s, jM in examples:
    print(f"  HDL {k:5d} / {jH:4d}   MAME {s:5d} / {jM:4d}   -> {jH - jM:+d}")
print("extra blitter runs before the HDL shows the same picture (0 = same timing as MAME):")
for key, v in sorted(results.items(), key=lambda kv: str(kv[0])):
    print(f"  {key}: {v} frames")
