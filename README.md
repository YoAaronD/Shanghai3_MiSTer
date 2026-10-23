# Shanghai III — MiSTer core (work in progress)

An FPGA re-creation of Sunsoft's Shanghai III arcade board (1993), starting with the Japanese set `shangha3j`. The same board design also runs Hebereke no Popoon and Blocken.

MAME's `shangha3.cpp` driver (BSD-3-Clause, Nicola Salmoria) is used as a behavioral reference. No MAME code is included. A copy of the driver is in `docs/mame/` for reading. This core is being built with AI assistance.

## Building the core (Windows or Linux PC)

1. Install **Quartus Prime Lite Edition 17.0.2** with Cyclone V device support. It's free from Intel; the Lite edition needs no license. Newer Quartus versions also work for many MiSTer cores, but 17.0 is the MiSTer standard.
2. Clone or download this repo somewhere with **no spaces in the path**, for example `C:\cores\Shanghai3_MiSTer`.
3. In Quartus: **File > Open Project**, choose `Shanghai3.qpf`.
4. **Processing > Start Compilation**. A full build takes roughly 15–40 minutes.
5. The result is `output_files/Shanghai3.rbf`.

If the build fails, copy the first red error message from the Messages window and send it over. If it builds, also note the "Total block memory bits" line from the Fitter summary.

## Installing on the MiSTer

1. Copy `Shanghai3.rbf` to `/media/fat/_Arcade/cores/` on the SD card. Rename it `Shanghai3_YYYYMMDD.rbf` with today's date; MiSTer finds the core by the start of the name.
2. Copy `releases/Shanghai III (Japan).mra` to `/media/fat/_Arcade/`.
3. Put your ROM zip in `/media/fat/games/mame/`. Either a split `shangha3j.zip` containing the four `s3j_*` files, or a merged `shangha3.zip`, works.
4. On the MiSTer: **Arcade > Shanghai III (Japan)**.

CRT Adjust (for analog CRT output): **OSD > CRT Adjust**. Turn it On, then set H-Size (−12 … +10 %), H-Position (6-pixel steps) and V-Shift (lines). It works only with Scandoubler Fx = None. With CRT Adjust Off, the video is passed through untouched. HDMI also follows the adjustment while it's On.

What to expect:
- The game runs its own 12-second power-on self-test first. A black screen, then "ROM 1 CHECK OK" and so on, is normal.
- DIP switches are in the OSD menu (F12 or the menu button) under "DIP Switches".
- Default controls: button A/B = Button 1/2, Start = Start, Select = Coin.

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
| Video timing | 8 MHz pixel clock, 512 × 263, 384 × 224 visible | Done (sync positions are guesses) |
| YM2149 sound | 1.5 MHz | Done (jt49) |
| OKI M6295 sound | 1.056 MHz, 8 kHz samples | Done (jt6295); samples from SDRAM |
| GA9201 blitter | Custom chip that draws tiles into a frame buffer | Done: sprites, zoom, tilemaps, shadows, flip (no rotation). Pixel-exact against the software model |
| Frame buffers | Draw buffer (block RAM) plus display buffer (DDR3), copied at vblank | Done (PCB method unknown) |
| CRT Adjust | Analog CRT H-Size / H-Position / V-Shift from the OSD | Done (rmonic79's module + glue adapted from Kyle's Nostradamus core); bench-verified on this raster |
| MiSTer wrapper | Video out, controls, ROM loading, MRA file | Written, simulated up to the MiSTer framework; **not yet built in Quartus** |

## Folder layout

```
Shanghai3.qpf/.qsf/.sdc   Quartus project (open Shanghai3.qpf)
Shanghai3.sv              MiSTer top level (menu, inputs, DIPs, video, audio)
files.qip                 list of source files for Quartus
sys/                      MiSTer framework (from the MiSTer Template)
rtl/                      the core: board, blitter, video, ROM storage, SDRAM controller, PLL
releases/                 MRA file
sim/                      Verilator testbenches, reference model, simulation output
scripts/                  build/sim/ROM helper scripts
docs/                     HANDOFF.md (full technical handoff), SAME_BOARD_GAMES.md (plan for
                          Hebereke no Popoon and Blocken), drafts/ (their draft MRAs), MAME driver, images
tools/mame/               MAME Lua scripts: per-frame capture, sound-traffic log (golden references)
CLAUDE.md                 steering notes for Claude sessions working on this repo
ext/                      reused open-source cores (fx68k, jt49, jt6295), see ext/README.md
microrom.mem, nanorom.mem fx68k microcode (Quartus loads them from the project folder)
```

## Running the simulation

You need Linux (or WSL on Windows), Verilator 5.x, Python 3 and g++. In a fresh Claude cloud sandbox, `scripts/setup_sandbox.sh` installs everything.

```
scripts/sim.sh test       # boots the 68000 on a small test program and checks results
scripts/blit_test.sh      # HDL blitter vs software blitter, pixel-for-pixel (needs ROMs, see below)
scripts/crt_test.sh       # CRT Adjust: every H-Size at both H-Position extremes + V-Shift (~3 min)
scripts/oki_test.sh       # OKI samples via download -> SDRAM vs. direct ROM, all 56 phrases (~20 min; --max N for less)
```

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

## Progress log

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
  - Pen 14 shadows: used (tile drop shadows)
- Workload: the busiest blitter run visits 172,032 pixels (about 2× the visible screen) across 614 commands. At 96 MHz with one run per frame, that leaves a budget of about 9 clocks per pixel. The budget should be fine, but graphics ROM fetches from SDRAM need to be burst reads, one 16-pixel tile row (8 bytes) at a time.

**HDL blitter (`rtl/shangha3_blitter.sv`) and video (`rtl/shangha3_video.sv`)**

- The blitter works in two phases:
  1. **Snapshot:** walk the command list in work RAM and copy the valid commands into an internal buffer. Disabled commands are skipped after 4 reads. If any command is a tilemap, the 8K-word tilemap area is copied too. This takes about 1% of a frame.
  2. **Draw:** draw from the snapshots. A shared scaled-tile engine handles sprites, fills and tilemap cells. Graphics ROM rows are prefetched while the previous row draws. Shadows are a read-modify-write of the frame buffer.
- CPU arbitration: only CPU writes to RAM words the snapshot hasn't reached yet are held, which reproduces MAME's instantaneous blitter. Reads, and writes anywhere else, run at full speed. Without arbitration, the boot RAM test overwrites tilemap codes mid-draw and garbage appears.
- An earlier design that held the CPU for the whole draw made the game drop to 30 fps. The game's stack sits inside the list/tilemap areas. Your real board runs the attract mode smoothly, which is consistent with the two-phase design.
- Unit test (`scripts/blit_test.sh`): the reference model saves RAM plus the frame buffer before and after real blitter runs, and the HDL blitter must reproduce the "after" frame exactly. Results:
  - 517 runs across 60 seconds of attract mode, 40 zoomed-sprite runs and 30 tilemap runs: all pixel-exact.
  - Deliberately breaking the shadow logic makes 25 of 52 cases fail, so the test does catch errors.
- Speed: the worst run takes 16.8% of a frame at 96 MHz with an 8-clock graphics ROM latency.
- Frame buffers: the draw buffer is copied to the display buffer at the start of vblank (0.9 ms of the 2.5 ms vblank). Drawing waits for the copy to finish; the snapshot phase doesn't. This gives tear-free output, but each blitter result appears one frame later than in MAME (measured against real MAME; see `docs/HANDOFF.md` §10).
- The display buffer is in the MiSTer's DDR3 (at 0x30000000). The first Quartus build ran out of block RAM with both buffers on-chip. Scan-out reads each line from DDR3 one line ahead. In simulation (DDR3 model with random stalls) this is frame- and timing-identical to the all-block-RAM version.
- Full-board run (`scripts/sim.sh game N --frames-out DIR`) captures the real RGB output; `scripts/compare_frames.py` matches it against the reference model's frames.
- Full-board results, 1800 frames (30 s) from power-on through the title screen into demo play:
  - Every frame up to 1110 is pixel-identical to a reference frame, sometimes shifted a few frames in time.
  - Later frames show the same screens, but at different moments. The demo deal differs because the game's random shuffle depends on timing.
  - CPU time lost to blitter arbitration: 0.01%.
  - The HDL board runs the title sequence at a steady 60 fps (100 blitter runs per 100 frames). The Musashi reference drops frames (75–86 per 100). The game is right at its CPU limit, and fx68k is cycle-exact while Musashi isn't. The real board's attract mode looks smooth, which matches the HDL.

**Sound, SDRAM and MiSTer wrapper**

- OKI M6295 (`jt6295`): 1.056 MHz from 96 MHz × 11/1000 (exact), pin 7 high (8 kHz). The mixer (`rtl/shangha3_mixer.sv`) high-passes the YM2149 at about 15 Hz and mixes `oki × 8 + ay × 16`. The balance was measured against a recording of the real PCB (v0.1.6).
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
  - 263 lines and 39 blank lines per frame;
  - no picture during HSync;
  - all 224 source lines complete, with x running 0..383.

  Result: 59 settings, 5.1 M checks, all pass. The bench caught one marginal limit (H-Size +5), which was tightened.
- The clamp table assumes HSync starts at dot 416, a placeholder. If the sync position is changed after measuring the PCB, recompute the table (formula in the file) and re-run the bench.

## Versions

See `CHANGELOG.md`. Git tags (`v0.1.0` …) mark milestones; following MiSTer custom, released cores are date-stamped (`releases/Shanghai3_YYYYMMDD.rbf`), and the core's OSD shows its build date.

## Next steps

Status: v0.1.6 runs on a real MiSTer (it meets timing, its boot matches the PCB, and full games were played).

1. Shanghai III v1.0.0:
   - listening check of the sound balance (measured against the PCB in v0.1.6)
   - check CRT Adjust on a CRT
   - decide on the one-frame difference vs. MAME (`docs/HANDOFF.md` §10)
   - release
2. Grow the core into a platform core for Hebereke no Popoon and Blocken (`docs/SAME_BOARD_GAMES.md`).
3. Later, measure on the real PCB: refresh rate, sync timing, and blitter speed.

## Licenses

- fx68k: GPL-3.0 (Jorge Cwik)
- jt49 / jt6295: GPL-3.0 (Jose Tejada, jotego)
- MiSTer template and `sys/`: GPL (Sorgelig and contributors)
- `rtl/vendor/crt_adjust.sv`: GPL-3.0-or-later (Umberto Parisi / rmonic79), github.com/rmonic79/MiSTer-CRT-Adjust
- `rtl/s3_crt_adjust.sv`, `sim/tb_crt.sv`: GPL-3.0-or-later, adapted from Kyle Lester's Nostradamus core
- `rtl/sdram.sv`: GPL-3.0 (Sorgelig), from MiSTer-devel/Arcade-IremM92_MiSTer, with simulation-only changes
- Musashi (reference model only, downloaded by the build script): Karl Stenerud, MIT-style license
- This core: intended GPL-3.0-or-later
