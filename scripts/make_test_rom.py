#!/usr/bin/env python3
"""Build a tiny hand-assembled 68000 test program for the Shanghai III board.

It exercises every piece of the board that exists so far, so the simulation
can be checked without the real game ROMs:
  work RAM, palette RAM, protection reads, SYSTEM port, YM2149 DIP read,
  flipscreen, gfxlist, blitter start, vblank IRQ4 + acknowledge.

usage: make_test_rom.py out.bin
"""
import struct
import sys

ROM_SIZE = 0x80000

def words(*ws):
    return b"".join(struct.pack(">H", w) for w in ws)

rom = bytearray(b"\xff" * ROM_SIZE)

def put(addr, data):
    rom[addr:addr + len(data)] = data

# Vector table: every exception -> 0x600 (error trap) unless set below
for v in range(64):
    put(v * 4, struct.pack(">I", 0x600))
put(0x000, struct.pack(">I", 0x00310000))   # initial SSP = top of work RAM
put(0x004, struct.pack(">I", 0x00000400))   # initial PC
put(0x070, struct.pack(">I", 0x00000500))   # level 4 autovector (vblank)

main = words(
    0x41F9, 0x0030, 0x0000,          # lea     $300000,a0
    0x30BC, 0x1234,                  # move.w  #$1234,(a0)
    0x3010,                          # move.w  (a0),d0
    0x43F9, 0x0010, 0x0000,          # lea     $100000,a1
    0x3280,                          # move.w  d0,(a1)          palette[0]
    0x3239, 0x0020, 0x004E,          # move.w  $20004e,d1       prot -> 0
    0x3239, 0x0020, 0x004E,          # move.w  $20004e,d1       prot -> 1
    0x33C1, 0x0030, 0x0002,          # move.w  d1,$300002
    0x3439, 0x0020, 0x0002,          # move.w  $200002,d2       SYSTEM
    0x33C2, 0x0030, 0x0004,          # move.w  d2,$300004
    0x13FC, 0x000E, 0x0020, 0x003F,  # move.b  #$0e,$20003f     AY reg 14 (port A)
    0x1A39, 0x0020, 0x001F,          # move.b  $20001f,d5       DSW1
    0x13C5, 0x0030, 0x0020,          # move.b  d5,$300020
    0x13FC, 0x007E, 0x0034, 0x0001,  # move.b  #$7e,$340001     flipscreen off
    0x33FC, 0x0ABC, 0x0036, 0x0000,  # move.w  #$0abc,$360000   gfxlist addr
    0x33FC, 0x0000, 0x0020, 0x0008,  # move.w  #0,$200008       blitter go
    0x46FC, 0x2000,                  # move.w  #$2000,sr        enable IRQs
    0x5283,                          # loop: addq.l #1,d3
    0x60FC,                          #       bra.s  loop
)
put(0x400, main)

irq4 = words(
    0x33FC, 0x0001, 0x0020, 0x000A,  # move.w  #1,$20000a       IRQ ack
    0x5279, 0x0030, 0x0010,          # addq.w  #1,$300010       frame counter
    0x4E73,                          # rte
)
put(0x500, irq4)

trap = words(
    0x33FC, 0xDEAD, 0x0030, 0x00FE,  # move.w  #$dead,$3000fe
    0x60FE,                          # bra.s   *
)
put(0x600, trap)

with open(sys.argv[1], "wb") as f:
    f.write(rom)
print(f"wrote {sys.argv[1]} ({ROM_SIZE} bytes)")
