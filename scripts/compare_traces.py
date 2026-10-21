#!/usr/bin/env python3
"""Compare CPU write sequences between the HDL simulation and the reference model.

Timing differs slightly between the two (polling loops can run a different
number of times), so only the ORDER of writes (address + data) and events is
compared, not timestamps or reads.

usage: compare_traces.py hdl_trace.txt ref_trace.txt
"""
import sys

def load(path):
    out = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) < 3:
                continue
            if p[1] == "W":
                out.append(("W", p[2], p[3], p[0]))
            elif p[1] == "EV" and p[2] in ("BLITTER_GO", "GFXLIST", "OKI_WRITE"):
                out.append(("EV", p[2], " ".join(p[3:]), p[0]))
    return out

hdl, ref = load(sys.argv[1]), load(sys.argv[2])
n = min(len(hdl), len(ref))
reordered = 0
i = 0
while i < n:
    if hdl[i][:3] != ref[i][:3]:
        # A real 68000 (and fx68k) stacks exception frames as PC-low, SR, PC-high;
        # Musashi writes them in plain order. Accept the same 3 writes in any order.
        a = sorted(x[:3] for x in hdl[i:i + 3])
        b = sorted(x[:3] for x in ref[i:i + 3])
        if a == b:
            reordered += 1
            i += 3
            continue
        print(f"MISMATCH at item {i}:")
        for j in range(max(0, i - 5), min(n, i + 5)):
            mark = ">>" if j == i else "  "
            print(f"{mark} hdl {hdl[j][3]:>12}us {' '.join(hdl[j][:3]):30}  ref {ref[j][3]:>12}us {' '.join(ref[j][:3])}")
        sys.exit(1)
    i += 1
print(f"MATCH: first {n} writes/events identical "
      f"(hdl has {len(hdl)}, ref has {len(ref)}; {reordered} exception frames stacked in 68000 order)")
last = hdl[n - 1] if n else None
if last:
    print(f"last compared: {' '.join(last[:3])} at hdl {last[3]}us")
