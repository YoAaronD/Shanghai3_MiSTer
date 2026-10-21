#!/usr/bin/env bash
# One-step tool setup for a fresh cloud sandbox (Ubuntu 24.04, no apt access).
# Builds what the simulations need from GitHub sources, with the workarounds
# found in the Shanghai III project. Safe to re-run: finished steps are skipped.
#
#   scripts/setup_sandbox.sh          # flex + Verilator 5.030 + Musashi disassembler
#
# Takes ~15-20 minutes the first time (Verilator build on 2 cores).
set -euo pipefail
SRC=/opt/src
mkdir -p "$SRC" /opt/tools

echo "== network check (what this sandbox can reach)"
for url in https://github.com https://codeload.github.com https://raw.githubusercontent.com \
           https://pypi.org https://registry.npmjs.org http://archive.ubuntu.com \
           https://downloads.intel.com; do
    code=$(curl -sS -o /dev/null -w "%{http_code}" -I --max-time 10 "$url" 2>/dev/null || true)
    case "$code" in 000|"") state="blocked" ;; *) state="reachable (HTTP $code)" ;; esac
    printf "  %-40s %s\n" "$url" "$state"
done
echo "  (github.com must work; the rest are nice-to-have. Intel = Quartus download.)"

if ! command -v flex >/dev/null; then
    echo "== building flex 2.6.4 (Verilator needs it; apt is blocked)"
    cd "$SRC"
    curl -sSLo flex.tgz https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
    tar xzf flex.tgz && cd flex-2.6.4
    ./configure --prefix=/usr/local >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null
fi

if ! command -v verilator >/dev/null; then
    echo "== building Verilator 5.030 (~15 min)"
    # make install runs help2man for man pages; it isn't available, so stub it
    if ! command -v help2man >/dev/null; then
        printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = "-o" ] && touch "$2"; shift; done\n' > /usr/local/bin/help2man
        chmod +x /usr/local/bin/help2man
    fi
    cd "$SRC"
    [ -d verilator ] || git clone -q --depth 1 -b v5.030 https://github.com/verilator/verilator
    cd verilator
    autoconf && ./configure --prefix=/usr/local >/dev/null
    make -j"$(nproc)" >/tmp/verilator_build.log 2>&1
    make install >/tmp/verilator_install.log 2>&1
fi
verilator --version

if [ ! -x /opt/tools/dis68k ]; then
    echo "== building a 68000 disassembler (Musashi): /opt/tools/dis68k ROM.bin HEXADDR COUNT"
    cd "$SRC"
    [ -d Musashi ] || git clone -q --depth 1 https://github.com/kstenerud/Musashi
    cd /opt/tools
    cp "$SRC"/Musashi/*.c "$SRC"/Musashi/*.h . && cp -r "$SRC/Musashi/softfloat" .
    gcc -O1 -o m68kmake m68kmake.c && ./m68kmake . m68k_in.c >/dev/null
    cat > dis.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include "m68k.h"
static unsigned char rom[0x400000];
unsigned int m68k_read_disassembler_8(unsigned int a){return rom[a%sizeof rom];}
unsigned int m68k_read_disassembler_16(unsigned int a){a%=sizeof rom;return (rom[a]<<8)|rom[a+1];}
unsigned int m68k_read_disassembler_32(unsigned int a){return (m68k_read_disassembler_16(a)<<16)|m68k_read_disassembler_16(a+2);}
unsigned int m68k_read_memory_8(unsigned int a){return 0;} unsigned int m68k_read_memory_16(unsigned int a){return 0;}
unsigned int m68k_read_memory_32(unsigned int a){return 0;} void m68k_write_memory_8(unsigned int a,unsigned int v){}
void m68k_write_memory_16(unsigned int a,unsigned int v){} void m68k_write_memory_32(unsigned int a,unsigned int v){}
int main(int c,char**v){FILE*f=fopen(v[1],"rb");if(!f)return 1;fread(rom,1,sizeof rom,f);fclose(f);
 unsigned pc=strtoul(v[2],0,16); int n=atoi(v[3]); char buf[128];
 for(int i=0;i<n;i++){int l=m68k_disassemble(buf,pc,M68K_CPU_TYPE_68000);printf("%06X  %s\n",pc,buf);pc+=l;}}
EOF
    gcc -O1 -w -I. -o dis68k dis.c m68kdasm.c m68kcpu.c m68kops.c softfloat/softfloat.c -lm
fi

echo "== Python: Pillow + numpy are needed by the frame comparison scripts"
python3 -c "import PIL, numpy; print('  ok: Pillow', PIL.__version__, 'numpy', numpy.__version__)" \
    || pip install --break-system-packages pillow numpy

echo "== done"
