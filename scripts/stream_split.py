#!/usr/bin/env python3
"""Split a GA9201 download stream (scripts/mra_stream.py output) into the
files the board simulation (sim/tb_main.cpp, scripts/sim.sh game) reads:

    scripts/stream_split.py STREAM OUTDIR

  prog.bin     1 MB, 68000 program as big-endian words (even/odd EPROMs interleaved)
  z80.bin      64 KB Z80 program
  blitter.bin  3.5 MB graphics ROM
  oki.bin      512 KB OKI samples
"""
import sys, os
s = open(sys.argv[1], 'rb').read()
assert len(s) == 0x510000, hex(len(s))
out = sys.argv[2]; os.makedirs(out, exist_ok=True)
hi, lo = s[0:0x80000], s[0x80000:0x100000]
prog = bytearray(0x100000); prog[0::2] = hi; prog[1::2] = lo
open(os.path.join(out, 'prog.bin'), 'wb').write(prog)
open(os.path.join(out, 'z80.bin'), 'wb').write(s[0x100000:0x110000])
open(os.path.join(out, 'blitter.bin'), 'wb').write(s[0x110000:0x490000])
open(os.path.join(out, 'oki.bin'), 'wb').write(s[0x490000:0x510000])
print('wrote prog.bin z80.bin blitter.bin oki.bin to', out)
