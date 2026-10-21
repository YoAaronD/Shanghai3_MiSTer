#!/usr/bin/env bash
# Build a headless MAME containing only the Shanghai III / Hebereke no Popoon /
# Blocken driver, in the cloud sandbox (no apt). Used as the golden reference:
# frame dumps, blitter logs, WAV output (see tools/mame/frame_log.lua).
#
#   scripts/build_mame.sh        -> /opt/src/mame/s3 (binary), ~1.5-2 h on 2 cores
#
# Run (example):
#   S3_OUT=/abs/out S3_FRAMES=1700 /opt/src/mame/s3 shangha3j -rompath ROMDIR \
#     -video none -sound none -nothrottle -snapview native \
#     -autoboot_script tools/mame/frame_log.lua
# Add "-sound none" -> "-wavwrite out.wav" (and drop -sound none) for audio.
set -euo pipefail
SRC=/opt/src
mkdir -p "$SRC"

# SDL2 + SDL2_ttf from source (MAME's Linux OSD needs them; no X11/audio backends)
if ! pkg-config --exists sdl2; then
    cd "$SRC"
    [ -d SDL2 ] || git clone -q --depth 1 -b release-2.30.9 https://github.com/libsdl-org/SDL SDL2
    cmake -S SDL2 -B SDL2/build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF \
        -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_VULKAN=OFF -DSDL_ALSA=OFF -DSDL_PULSEAUDIO=OFF \
        -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF -DSDL_SNDIO=OFF -DSDL_OSS=OFF -DSDL_DUMMYVIDEO=ON \
        -DSDL_OFFSCREEN=ON -DSDL_DUMMYAUDIO=ON -DSDL_DISKAUDIO=ON >/dev/null
    ninja -C SDL2/build >/dev/null && ninja -C SDL2/build install >/dev/null
fi
if ! pkg-config --exists SDL2_ttf; then
    cd "$SRC"
    [ -d SDL2_ttf ] || git clone -q --depth 1 -b release-2.22.0 https://github.com/libsdl-org/SDL_ttf SDL2_ttf
    cmake -S SDL2_ttf -B SDL2_ttf/build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release \
        -DSDL2TTF_HARFBUZZ=OFF -DSDL2TTF_VENDORED=OFF -DSDL2TTF_SAMPLES=OFF >/dev/null
    ninja -C SDL2_ttf/build >/dev/null && ninja -C SDL2_ttf/build install >/dev/null
fi
# MAME links -lEGL; only the runtime libEGL.so.1 is installed
ln -sf /usr/lib/x86_64-linux-gnu/libEGL.so.1 /usr/lib/x86_64-linux-gnu/libEGL.so 2>/dev/null || true
ldconfig

# MAME source: shallow, blob-less clone (about 1.2 GB checked out)
cd "$SRC"
if [ ! -f mame/makefile ]; then
    rm -rf mame
    git clone -q --depth 1 --filter=blob:none https://github.com/mamedev/mame mame
fi
cd mame
git sparse-checkout disable 2>/dev/null || true

make SUBTARGET=s3 SOURCES=src/mame/sunelectronics/shangha3.cpp NOWERROR=1 \
     NO_X11=1 NO_USE_XINPUT=1 NO_OPENGL=1 NO_USE_MIDI=1 NO_USE_PORTAUDIO=1 \
     NO_USE_PULSEAUDIO=1 NO_USE_PIPEWIRE=1 USE_QTDEBUG=0 OPTIMIZE=2 SYMBOLS=0 \
     TOOLS=0 TESTS=0 -j"$(nproc)"
ls -la s3
