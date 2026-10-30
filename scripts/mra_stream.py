#!/usr/bin/env python3
"""Build the ROM download stream a MiSTer would send for an .mra file.

    scripts/mra_stream.py MRA ROMSRC OUT.bin [--index N]

ROMSRC is a folder holding the ROM files (or MAME .zip files), or a .zip.
Writes the bytes of <rom index="N"> (default 0) to OUT.bin and prints the
size, the bytes of every other <rom> index (e.g. the game select byte at
index 1), and a CRC check of each named part.

Supported MRA features (what this project's MRAs use): <part name=.. crc=..>,
<part repeat="N">HH</part>, inline hex <part>HH HH</part>, zip="a.zip|b.zip".
"""
import sys, os, zipfile, zlib, re
import xml.etree.ElementTree as ET


def open_sources(src, zipattr):
    """Return a function name -> bytes."""
    zips = []
    if os.path.isfile(src) and src.endswith('.zip'):
        zips.append(zipfile.ZipFile(src))
    elif os.path.isdir(src):
        for z in (zipattr or '').split('|'):
            p = os.path.join(src, z.strip())
            if z.strip() and os.path.isfile(p):
                zips.append(zipfile.ZipFile(p))

    def get(name):
        if os.path.isdir(src) and os.path.isfile(os.path.join(src, name)):
            return open(os.path.join(src, name), 'rb').read()
        for z in zips:
            for info in z.infolist():
                if os.path.basename(info.filename) == name:
                    return z.read(info)
        raise FileNotFoundError(f'{name} not found in {src} ({zipattr})')
    return get


def hexbytes(text):
    t = re.sub(r'\s+', '', text or '')
    return bytes.fromhex(t)


def build(mra, src, index=0):
    root = ET.parse(mra).getroot()
    out, others, checks = None, {}, []
    for rom in root.findall('rom'):
        idx = int(rom.get('index', '0'))
        get = open_sources(src, rom.get('zip'))
        data = bytearray()
        for part in rom.findall('part'):
            if part.get('name'):
                b = get(part.get('name'))
                crc = part.get('crc')
                ok = crc is None or int(crc, 16) == (zlib.crc32(b) & 0xffffffff)
                checks.append((part.get('name'), len(b), crc, ok))
                data += b
            elif part.get('repeat'):
                n = int(part.get('repeat'), 0)
                data += hexbytes(part.text) * n
            else:
                data += hexbytes(part.text)
        if idx == index:
            out = bytes(data)
        else:
            others[idx] = bytes(data)
    return out, others, checks


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    index = 0
    if '--index' in sys.argv:
        index = int(sys.argv[sys.argv.index('--index') + 1])
    out, others, checks = build(sys.argv[1], sys.argv[2], index)
    bad = 0
    for name, n, crc, ok in checks:
        print(f'  {name:28s} {n:8d} bytes  crc {crc}  {"ok" if ok else "MISMATCH"}')
        bad += not ok
    open(sys.argv[3], 'wb').write(out)
    print(f'index {index}: {len(out)} bytes (0x{len(out):X}) -> {sys.argv[3]}')
    for k, v in sorted(others.items()):
        print(f'index {k}: {v.hex(" ")}')
    sys.exit(1 if bad else 0)
