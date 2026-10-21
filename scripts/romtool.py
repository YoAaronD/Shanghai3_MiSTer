#!/usr/bin/env python3
"""ROM helper for the Shanghai III core.

Finds the shangha3j ROM files in one or more MAME zips (split or merged sets),
checks them against the CRCs from MAME's driver, and writes the images the
simulator needs:

  <out>/prog.bin     512 KB  68000 program, EPROMs interleaved (ic3 = high byte)
  <out>/blitter.bin    2 MB  graphics mask ROM (for the blitter, later)
  <out>/oki.bin      256 KB  OKI M6295 samples (later)

usage: romtool.py extract --out sim/roms shangha3j.zip [shangha3.zip ...]

ROM dumps are not included with this project. Use dumps of your own board.
"""
import argparse
import os
import sys
import zipfile
import zlib

# From MAME shangha3.cpp ROM_START( shangha3j )
SHANGHA3J = {
    "prog_hi": ("s3j_v11.ic3",      0xE98CE9C8, 0x40000),
    "prog_lo": ("s3j_v11.ic2",      0x09174620, 0x40000),
    "blitter": ("s3j_char-a1.ic43", 0x2DBF9D17, 0x200000),
    "oki":     ("s3j_v10.ic75",     0xF0CDC86A, 0x40000),
}


def find_files(zips):
    """Map CRC -> bytes for every file in the given zips."""
    found = {}
    for zp in zips:
        if os.path.isdir(zp):                 # a folder of unzipped ROM files
            for name in os.listdir(zp):
                with open(os.path.join(zp, name), "rb") as f:
                    data = f.read()
                found[zlib.crc32(data) & 0xFFFFFFFF] = data
            continue
        with zipfile.ZipFile(zp) as z:
            for info in z.infolist():
                data = z.read(info)
                found[zlib.crc32(data) & 0xFFFFFFFF] = data
    return found


def extract(args):
    found = find_files(args.zips)
    files = {}
    ok = True
    for key, (name, crc, size) in SHANGHA3J.items():
        data = found.get(crc)
        if data is None:
            print(f"MISSING  {name}  crc {crc:08x}")
            ok = False
        elif len(data) != size:
            print(f"BADSIZE  {name}  {len(data)} != {size}")
            ok = False
        else:
            print(f"ok       {name}  crc {crc:08x}")
            files[key] = data
    if not ok:
        sys.exit(1)

    os.makedirs(args.out, exist_ok=True)
    hi, lo = files["prog_hi"], files["prog_lo"]
    prog = bytearray(len(hi) * 2)
    prog[0::2] = hi      # ROM_LOAD16_BYTE at offset 0 -> even bytes (68000 high byte)
    prog[1::2] = lo
    with open(os.path.join(args.out, "prog.bin"), "wb") as f:
        f.write(prog)
    with open(os.path.join(args.out, "blitter.bin"), "wb") as f:
        f.write(files["blitter"])
    with open(os.path.join(args.out, "oki.bin"), "wb") as f:
        f.write(files["oki"])
    print(f"wrote prog.bin, blitter.bin, oki.bin to {args.out}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("--out", default="sim/roms")
    e.add_argument("zips", nargs="+")
    e.set_defaults(func=extract)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
