#!/usr/bin/env python3
"""Check the bus trace from the hand-made test ROM against expected results.

usage: check_test_trace.py trace.txt [dsw1_hex]
"""
import sys

trace = open(sys.argv[1]).read().splitlines()
dsw1 = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0xFF

writes, reads, events = [], [], []
for line in trace:
    parts = line.split()
    if parts[1] == "W":
        writes.append((int(parts[2], 16), int(parts[3], 16)))
    elif parts[1] == "R":
        reads.append((int(parts[2], 16), int(parts[3], 16)))
    else:
        events.append(parts[2:])

failures = 0
def check(name, cond, detail=""):
    global failures
    print(f"{'PASS' if cond else 'FAIL'}  {name}  {detail}")
    if not cond:
        failures += 1

check("reset vector fetch", reads[:4] == [(0x000000, 0x0031), (0x000002, 0x0000),
                                           (0x000004, 0x0000), (0x000006, 0x0400)],
      str([f"{a:06X}={d:04X}" for a, d in reads[:4]]))
check("work RAM write", (0x300000, 0x1234) in writes)
check("work RAM read back", (0x300000, 0x1234) in reads)
check("palette RAM write", (0x100000, 0x1234) in writes)
prot = [d for a, d in reads if a == 0x20004E]
check("protection sequence", prot[:2] == [0x0, 0x1], str(prot[:2]))
check("protection value stored", (0x300002, 0x0001) in writes)
sysv = [d for a, d in writes if a == 0x300004]
check("SYSTEM port read (bit7 = !vblank)", len(sysv) == 1 and (sysv[0] & 0xFF7F) == 0xFF7F,
      f"{sysv[0]:04X}" if sysv else "none")
ay = [d for a, d in writes if a == 0x300020]
check("DSW1 via YM2149 port A", len(ay) == 1 and (ay[0] >> 8) == dsw1,
      f"got {ay[0] >> 8:02X} want {dsw1:02X}" if ay else "none")
check("gfxlist register", ["GFXLIST", "0ABC"] in events)
check("blitter start", any(e[0] == "BLITTER_GO" for e in events))
irq_acks = sum(1 for e in events if e[0] == "IRQ_ACK")
frames = sum(1 for e in events if e[0] == "FRAME")
check("one vblank IRQ per frame", irq_acks >= 1 and abs(irq_acks - frames) <= 1,
      f"{irq_acks} acks, {frames} frames")
counter = [d for a, d in writes if a == 0x300010]
check("IRQ handler frame counter", counter == list(range(1, len(counter) + 1)) and counter,
      str(counter))
check("no exception trap", (0x3000FE, 0xDEAD) not in writes)

print(f"\n{failures} failure(s)")
sys.exit(1 if failures else 0)
