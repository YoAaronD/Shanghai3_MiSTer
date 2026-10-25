# Shanghai III MiSTer core: development notes

How to build the core, run the simulations, and how it was verified. For installing and playing, see the [README](../README.md); for what changed in each version, [CHANGELOG.md](../CHANGELOG.md).

## Building the core (Quartus)

1. Install **Quartus Prime Lite Edition 17.0.2** with Cyclone V device support. It's free from Intel; the Lite edition needs no license. Newer Quartus versions also work for many MiSTer cores, but 17.0 is the MiSTer standard.
2. Clone or download this repo somewhere with **no spaces in the path**, for example `C:\cores\Shanghai3_MiSTer`.
3. In Quartus: **File > Open Project**, choose `Shanghai3.qpf`.
4. **Processing > Start Compilation**. A full build takes roughly 15–40 minutes.
5. The result is `output_files/Shanghai3.rbf`.

After each build, `scripts/quartus/post_flow.tcl` writes `output_files/timing_paths.txt`, listing any failing timing paths. Check that the 96 MHz clock (`emu|pll…divclk`) has positive setup slack in the Timing Analyzer's Setup Summary; block RAM use is under Compilation Report → Fitter → Summary ("Total RAM Blocks", 520 of 553 in v0.1.7).

To install a build, rename it `Shanghai3_YYYYMMDD.rbf` and follow the installation steps in the README.

## Making a release

1. Build in Quartus and check the timing (above).
2. In PowerShell, from the repo folder:
   `powershell -ExecutionPolicy Bypass -File scripts\make_release.ps1 -Date YYYYMMDD` (the date defaults to today; use the build date).
   - It copies `output_files\Shanghai3.rbf` to `releases\Shanghai3_YYYYMMDD.rbf`. Commit that file.
   - It writes `output_files\Shanghai3_MiSTer_YYYYMMDD.zip`, laid out like the SD card (`_Arcade/Shanghai III (Japan).mra`, `_Arcade/cores/Shanghai3_YYYYMMDD.rbf`).
3. Add an entry to `CHANGELOG.md`, commit, and tag the version (`vX.Y.Z`).
4. On GitHub: Releases → Draft a new release → choose the tag, paste the changelog entry, attach the zip.

## The hardware (from MAME)

| Part | Detail | Status in this core |
|---|---|---|
| CPU | 68000 @ 16 MHz (48 MHz / 3) | Done (fx68k) |
| Program ROM | 512 KB, two interleaved EPROMs | Done: SDRAM, with a 32 KB instruction cache |
| Work/graphics RAM | 64 KB @ 300000 | Done |
| Palette RAM | 2048 colors, RGB555 @ 100000 | Done (drives the video output) |
| Inputs / DIPs | 200000, 200002; DIPs through the YM2149 I/O ports | Done |
| Protection | Fixed read sequence @ 20004E | Done |
| Interrupts | IRQ4 at vblank, ack @ 20000A | Done |
| Video timing | 8 MHz pixel clock, 512 × 262, 384 × 224 visible, 59.64 Hz | Done. Line count measured on the PCB with an OSSC (262-p, 59.63 Hz); MAME uses 263. Sync positions not measured; centering is right on the CRTs tested |
| YM2149 sound | 1.5 MHz | Done (jt49) |
| OKI M6295 sound | 1.056 MHz, 8 kHz samples | Done (jt6295); samples from SDRAM |
| GA9201 blitter | Custom chip that draws tiles into a frame buffer | Done: sprites, zoom, tilemaps, shadows, flip (no rotation). Pixel-exact against the software model |
| Frame buffers | Draw buffer (block RAM) plus display buffer (DDR3), copied at vblank | Done (PCB method unknown) |
| CRT Adjust | Analog CRT H-Size / H-Position / V-Shift from the OSD | Done (rmonic79's module + glue adapted from Kyle's Nostradamus core); bench-verified on this raster |
| Sound mix | YM2149 + OKI | Balance measured against a recording of the PCB (v0.1.6), trimmed by ear (v0.1.7) |
| MiSTer wrapper | Video out, controls, ROM loading, MRA, pause, HDMI rotation, CRT Adjust | Done; tested on hardware |

## Folder layout

```
Shanghai3.qpf/.qsf/.sdc   Quartus project (open Shanghai3.qpf)
Shanghai3.sv              MiSTer top level (menu, inputs, DIPs, video, audio)
files.qip                 list of source files for Quartus
sys/                      MiSTer framework (from the MiSTer Template)
rtl/                      the core: board, blitter, video, ROM storage, SDRAM controller, PLL
releases/                 MRA file and released cores (Shanghai3_YYYYMMDD.rbf)
sim/                      Verilator testbenches, reference model, simulation output
scripts/                  build/sim/ROM helper scripts
docs/                     this file, the MAME driver (for reading), images
tools/mame/               MAME Lua scripts: per-frame capture, sound-register logs (golden references)
tools/audio/              balance_fit.py: YM2149/OKI balance from a PCB recording
ext/                      reused open-source cores (fx68k, jt49, jt6295), see ext/README.md
microrom.mem, nanorom.mem fx68k microcode (Quartus loads them from the project folder)
```

## Running the simulation

You need Linux (or WSL on Windows), Verilator 5.x, Python 3 and g++. On a fresh Ubuntu machine without root, `scripts/setup_sandbox.sh` builds what's missing (Verilator 5.030, flex, dis68k).

```
scripts/sim.sh test       # boots the 68000 on a small test program and checks results
scripts/blit_test.sh      # HDL blitter vs software blitter, pixel-for-pixel (needs ROMs, see below)
scripts/crt_test.sh       # CRT Adjust: every H-Size at both H-Position extremes + V-Shift (~3 min)
scripts/oki_test.sh       # OKI samples via download -> SDRAM vs. direct ROM, all 56 phrases (~20 min; --max N for less)
scripts/sim_top.sh ROMDIR N   # end to end: MiSTer download -> SDRAM model -> boot -> DDR3 model
scripts/snd_replay.sh LOG OUT.raw [OUT.wav]   # sound only: YM2149/OKI register log through jt49 + jt6295 + mixer
scripts/osd_test.sh       # the MiSTer OSD's info box (sys/osd.v) over the core's video, CRT Adjust off and on
```

MAME comparisons: `scripts/build_mame.sh` builds a headless MAME with only this driver; `tools/mame/frame_log.lua` captures every frame and blitter start, `scripts/mame_latency.py` compares frame timing and pixels, and `tools/mame/snd_regs.lua` logs every sound-chip write for `snd_replay.sh`.

Expected output ends with `0 failure(s)`. The test checks reset, RAM, palette writes, the protection sequence, the input ports, DIP reads through the YM2149, the blitter registers, and one vblank interrupt per frame.

### With the real game program

Use ROMs dumped from your own board, or a MAME `shangha3j` set. ROMs are not included here.

```
python3 scripts/romtool.py extract --out sim/roms shangha3j.zip shangha3.zip
scripts/sim.sh game 60     # run 60 frames (about 1 second of game time)
```

`romtool.py` checks every file against MAME's CRCs. The bus trace goes to `sim/game_trace.txt`. Look for `BLITTER_GO` events: they show the game building its draw lists, even though nothing is drawn yet.

### Reference model

`sim/refmodel/` is a fast software model of the CPU side of the board: the Musashi 68000 emulator plus MAME's memory map. It runs about 250× faster than the HDL simulation. `scripts/compare_traces.py` checks that both produce the same sequence of CPU writes.

```
scripts/build_refmodel.sh
sim/refmodel/refmodel sim/roms/prog.bin 1500 sim/ref_trace.txt --no-rom-log
scripts/compare_traces.py sim/game_trace.txt sim/ref_trace.txt
```

The reference model also contains a software blitter (`sim/refmodel/blitter.c`), written from the behavior MAME documents. It is the "golden" model that the HDL blitter will be checked against pixel by pixel. To render the attract mode, saving every 30th frame:

```
mkdir -p sim/frames
sim/refmodel/refmodel sim/roms/prog.bin 3600 sim/ref_trace.txt --no-rom-log \
    --gfx sim/roms/blitter.bin --frames-out sim/frames --every 30
```

Frames are written as `.ppm` images (384 × 224). Most image viewers open them.

## Design notes and verification history

**Real game boot (shangha3j, ROMs verified against MAME CRCs)**

- The game boots and runs its full power-on self-test: ROM checksum, then RAM pattern tests. The test takes about 12 seconds.
- During boot, all 1.17 million CPU writes match the reference model exactly.
- After the self-test the game enables vblank interrupts and starts the blitter about once per frame, at the same rate as the reference model.
- After that point the write order diverges, because interrupts land at slightly different instructions; this is expected. The two models agree on timing to within 0.3%. fx68k is cycle-exact, so the remaining difference is most likely Musashi's.
- Fixed: write cycles were picking up an extra wait state, because DTACK waited for UDS/LDS, which the 68000 asserts late on writes.

**Software blitter (step 1 of the blitter work)**

- The whole attract mode renders correctly: boot messages, the dragon title with fades, the logo and credits, a demo game, the ranking table, then the loop back to the dragon. Sample frames are in `docs/images/`.
- What the game actually uses, measured over 60 seconds of attract mode:
  - Sprites (horizontal strips of 16×16 tiles): 814,191
  - Tilemaps: 7,023
  - Zoomed sprites: 891 (the floating score)
  - Rectangle fills, condensed 8×8 tilemaps, rotation: none
  - Pen 14 shadows: used (tile drop shadows). A shadow sets bit 7 of the palette index (colours 0–127 → 128–255, where the game keeps darkened copies); shadows over shadows don't darken further, as on the PCB (v0.1.9; MAME darkens them again)
- Workload: the busiest blitter run visits 172,032 pixels (about 2× the visible screen) across 614 commands. At 96 MHz with one run per frame, that leaves a budget of about 9 clocks per pixel. The budget should be fine, but graphics ROM fetches from SDRAM need to be burst reads, one 16-pixel tile row (8 bytes) at a time.

**HDL blitter (`rtl/shangha3_blitter.sv`) and video (`rtl/shangha3_video.sv`)**

- The blitter works in two phases:
  1. **Snapshot:** walk the command list in work RAM and copy the valid commands into an internal buffer. Disabled commands are skipped after 4 reads. If any command is a tilemap, the 8K-word tilemap area is copied too. This takes about 1% of a frame.
  2. **Draw:** draw from the snapshots. A shared scaled-tile engine handles sprites, fills and tilemap cells. Graphics ROM rows are prefetched while the previous row draws. Shadows are a read-modify-write of the frame buffer.
- CPU arbitration: only CPU writes to RAM words the snapshot hasn't reached yet are held, which reproduces MAME's instantaneous blitter. Reads, and writes anywhere else, run at full speed. Without arbitration, the boot RAM test overwrites tilemap codes mid-draw and garbage appears.
- An earlier design that held the CPU for the whole draw made the game drop to 30 fps. The game's stack sits inside the list/tilemap areas. The real board runs the attract mode smoothly, which is consistent with the two-phase design.
- Unit test (`scripts/blit_test.sh`): the reference model saves RAM plus the frame buffer before and after real blitter runs, and the HDL blitter must reproduce the "after" frame exactly. Results:
  - 517 runs across 60 seconds of attract mode, 40 zoomed-sprite runs and 30 tilemap runs: all pixel-exact.
  - Deliberately breaking the shadow logic makes 25 of 52 cases fail, so the test does catch errors.
- Speed: the worst run takes 16.8% of a frame at 96 MHz with an 8-clock graphics ROM latency.
- Frame buffers: the draw buffer is copied to the display buffer at the start of vblank (0.9 ms of the 2.5 ms vblank). Drawing waits for the copy to finish; the snapshot phase doesn't. This gives tear-free output, but each blitter result appears one frame (about 17 ms) later than in MAME (measured against real MAME with `scripts/mame_latency.py`). The real board's frame buffering is unknown; the delay isn't noticeable in play.
- The display buffer is in the MiSTer's DDR3 (at 0x30000000). The first Quartus build ran out of block RAM with both buffers on-chip. Scan-out reads each line from DDR3 one line ahead. In simulation (DDR3 model with random stalls) this is frame- and timing-identical to the all-block-RAM version.
- Full-board run (`scripts/sim.sh game N --frames-out DIR`) captures the real RGB output; `scripts/compare_frames.py` matches it against the reference model's frames.
- Full-board results, 1800 frames (30 s) from power-on through the title screen into demo play:
  - Every frame up to 1110 is pixel-identical to a reference frame, sometimes shifted a few frames in time.
  - Later frames show the same screens, but at different moments. The demo deal differs because the game's random shuffle depends on timing.
  - CPU time lost to blitter arbitration: 0.01%.
  - The HDL board runs the title sequence at a steady 60 fps (100 blitter runs per 100 frames). The Musashi reference drops frames (75–86 per 100). The game is right at its CPU limit, and fx68k is cycle-exact while Musashi isn't. The real board's attract mode looks smooth, which matches the HDL.

**Sound, SDRAM and MiSTer wrapper**

- OKI M6295 (`jt6295`): 1.056 MHz from 96 MHz × 11/1000 (exact), pin 7 high (8 kHz). The mixer (`rtl/shangha3_mixer.sv`) high-passes the YM2149 at about 58 Hz and mixes `(oki × 90 + ay × 180) / 16`. The balance was measured against a recording of the real PCB (v0.1.6), then the overall level and bass were trimmed by ear (v0.1.7). Since v0.1.8 the OSD option "OKI (drums/FX)" moves the OKI ±3 / ±6 dB relative to the YM2149 (coefficient table in the file); PCB is the default. In the demo tune, 65 % of the OKI's energy is between 40 and 150 Hz (the kick drum), while the YM2149's is mostly 150 Hz – 2 kHz.
- DIP default for bank 2 is now 0xBF (MAME's default). With 0xFF, demo sounds were off.
- ROM storage (`rtl/shangha3_mem.sv`): Sorgelig's 4-channel SDRAM controller (`rtl/sdram.sv`, from the Irem M92 core) at 96 MHz. Channels:
  - CPU cache-line fills (highest priority)
  - OKI sample bytes
  - ROM download writes
  - blitter tile rows

  The 68000 reads through a 512-line × 4-word cache, so hits answer in about 1 clock.
- End-to-end simulation (`scripts/sim_top.sh`): emulates the MiSTer ROM download byte by byte into a pin-level SDRAM model, checks every byte of the SDRAM contents, then boots the game from SDRAM. Results:
  - All 2,883,584 ROM bytes land at the right SDRAM addresses.
  - 400 frames of boot from SDRAM match the reference frames.
  - "ROM 2 CHECK OK" appears 5 frames later than with the direct ROM port. The boot ROM checksum reads the whole program ROM as data, which misses the CPU cache every 4th word. Normal game code runs from the cache.
- Audio (full board, 32 s): attract mode is silent by design (the game writes YM2149 register 7 = 0x3F, all channels off). The demo game turns on YM2149 music (register 7 = 0x38) and OKI effects. The output peaks at 18% of full scale with no clipping. The game now sends OKI "stop" commands because it sees real channel-busy bits; the reference model's OKI stub always reported idle.
- Timing: `Shanghai3.sdc` relaxes paths inside fx68k to 3 clocks, because its registers only update on phase enables, every 3rd clock. Two blitter multiplies were narrowed to single DSP blocks. All blitter tests are still pixel-exact.

**OKI samples through SDRAM (`scripts/oki_test.sh`)**

- Two jt6295 chips receive identical commands. One reads samples through the real path (download → `shangha3_mem` → `sdram.sv` → SDRAM model); the other reads the ROM directly. Their outputs must match sample for sample.
- **Bug found and fixed:** after each "start" command, jt6295 reads 6 bytes from the phrase table, and it drops the next command if that lookup is still running. The game writes OKI commands 2 µs apart, but SDRAM-speed lookups took longer. The 1 KB phrase table is now also kept in block RAM, filled during the download. Sample data stays in SDRAM.
- Result: all 56 phrases, at the game's 2 µs command spacing, under heavy background SDRAM traffic (111 M blitter rows, 1.2 M CPU cache misses). 19.9 M samples (18.9 s): identical, with no busy-flag differences.

**CRT Adjust**

- `rtl/vendor/crt_adjust.sv`: MiSTer-CRT-Adjust @c682de9 by Umberto Parisi (rmonic79), unmodified.
- `rtl/s3_crt_adjust.sv`: glue adapted from Kyle Lester's Nostradamus core. It provides:
  - controls sampled once per frame, inside vblank;
  - an exact read-clock NCO (1% H-Size steps);
  - HPOS_SYNCSHIFT, with an H-Position clamp table derived for this raster;
  - true bypass when Off;
  - automatic disable while the scandoubler is on.
- Placed in front of `arcade_video` in `Shanghai3.sv`. OSD page "CRT Adjust" (status bits 96, 101–108, 112–116).
- `scripts/crt_test.sh` checks every H-Size at both H-Position extremes, plus V-Shift:
  - constant 6144-clock line period;
  - 262 lines and 38 blank lines per frame;
  - no picture during HSync;
  - all 224 source lines complete, with x running 0..383.

  Result: 59 settings, 5.1 M checks, all pass. The bench caught one marginal limit (H-Size +5), which was tightened.
- The clamp table assumes HSync starts at dot 416, a placeholder. If the sync position is changed after measuring the PCB, recompute the table (formula in the file) and re-run the bench.
- H-Position moves in 6-pixel steps (16 OSD settings cover −48 … +42 pixels), the same layout as the Nostradamus core.

**Sound balance (v0.1.6)**

- The attract demo plays the same tune as a game recorded on the real PCB. MAME logged its YM2149/OKI register writes (`tools/mame/snd_regs.lua`); `scripts/snd_replay.sh` replays them through the core's own jt49 + jt6295 + `rtl/shangha3_mixer.sv`, giving the two sources separately.
- `tools/audio/balance_fit.py` aligns the recording with the replay in 1-second pieces and fits PCB band power = a·YM2149 + b·OKI + noise per frequency band (trimmed least squares, so clicks and voices drop out).
- The first-guess mix had the OKI about 8 dB too quiet relative to the YM2149; the season/flower pair sound (OKI phrase 24) about 11 dB. The new mix fits within about 1 dB. A phone recording limits this to a few dB.
- OKI phrases: 3 = tile pick, 24 = season/flower pair, 27 = ending jingle, 32–61 = the music's drums.

**Hardware testing**

- Boot checks match the PCB on video, in order and timing. The green stripes during COLOR RAM CHECK are real: palette changes take effect mid-frame on the PCB (MAME shows whole-frame flashes instead).
- Tested on a DE10-Nano with CRT and HDMI: gameplay, controls, Service Mode, DIP switches including Flip Screen, pause, HDMI rotation, CRT Adjust, and sync held through ROM loading.

## Licenses

- fx68k: GPL-3.0 (Jorge Cwik)
- jt49 / jt6295: GPL-3.0 (Jose Tejada, jotego)
- MiSTer template and `sys/`: GPL (Sorgelig and contributors)
- `rtl/vendor/crt_adjust.sv`: GPL-3.0-or-later (Umberto Parisi / rmonic79), github.com/rmonic79/MiSTer-CRT-Adjust
- `rtl/s3_crt_adjust.sv`, `sim/tb_crt.sv`: GPL-3.0-or-later, adapted from Kyle Lester's Nostradamus core
- `rtl/sdram.sv`: GPL-3.0 (Sorgelig), from MiSTer-devel/Arcade-IremM92_MiSTer, with simulation-only changes
- Musashi (reference model only, downloaded by the build script): Karl Stenerud, MIT-style license
- This core: intended GPL-3.0-or-later
