# Changelog

Versions follow two conventions:

- **Git tags** (`v0.1.0` …) mark milestones in this repo:
  - 0.x until the core is fully working on hardware
  - 1.0.0 for the first public release
- **Date stamps** are the MiSTer convention:
  - Each Quartus build stamps its date into the core automatically (`sys/build_id.tcl`); the OSD shows it as `vYYMMDD`.
  - Released core files are named `Shanghai3_YYYYMMDD.rbf` in `releases/`. The MRA's `<rbf>Shanghai3</rbf>` picks up the newest one.

Each entry below gives both: version, then date stamp.

---

## v0.1.4 — 20261022

Fixes from Aaron's hardware testing, plus HDMI rotation.

**Fixed**
- **Start and Service buttons.** Start added a credit (it was wired to the board's "service coin" input) and Service acted as Start. The SYSTEM port bits are now in MAME's order: coin 1, coin 2, service, start 1, start 2, service-mode switch.
- **CRTs lost sync while a game loads.** The board is held in reset during the ROM download, and that used to stop the video timing as well. The pixel clock and video timing now run through every reset and download (only a power-up/PLL reset stops them), so the picture is black but in sync.
- **Draw buffer cleared on every board reset,** as MAME starts with an empty bitmap: no leftover picture from before a reset or a reload. The sweep takes 0.9 ms; the blitter waits for it.

**Added**
- **Loading bar** while the ROMs download (256 × 16 pixels, centred).
- **Orientation: Horizontal / Vertical CW / Vertical CCW** (OSD). For vertical (TATE) monitors on HDMI, using the MiSTer framework's `screen_rotate` (as in Kyle's cores). The 15 kHz analog output is never rotated.
  - `screen_rotate` needs the DDR3 port, which the display buffer already uses. The new `rtl/shangha3_ddr_arb.sv` shares it: rotation writes are queued in a 64-entry FIFO and sent between the display buffer's bursts.
  - Tested in simulation with a second master writing every visible pixel (37 M writes): all arrived, none dropped, and the game's frames were unchanged.
  - `MISTER_FB` is now enabled in the qsf.

**Checked**
- **Flip Screen DIP:** in simulation the core flips the picture exactly like MAME. The game reads the switch once, at the end of its power-on self-test (about 12 s), so a change only shows after a reset and the self-test.

## v0.1.3 — 20261021

**Added**
- **Pause when the menu is open.** Opening the MiSTer OSD freezes the game and silences it; closing the OSD resumes exactly where it stopped. It can be turned off in the menu ("Pause when OSD is open: On/Off"; default On).
  - Inspired by Raki's CV1000 core.
  - Tested in simulation: a 60-frame pause, after which the game continues frame-for-frame identical to an unpaused run.
- Board testbench option `--pause FROM LEN`.

## v0.1.2 — 20261021

First fix from real-hardware testing.

**Fixed**
- Boot: after "ADPCM CHECK OK." the screen filled with rows of the letter "A" for a few frames, where the PCB shows "--- INTTURUPT WAIT ---".
  - Cause: the game starts the blitter twice, 8 µs apart, then reuses that RAM. The core queued the second run, which then read RAM the game had already changed.
  - Fix: while a run is queued, CPU writes to the list and tilemap areas wait until that run has copied them, so every run sees RAM as it was at its own start, as MAME's instant blitter does. Up to 3 starts are queued.
  - The CPU pauses only in this double-start case, which is rare (mostly at boot).
  - Over 1,700 simulated frames, only the 4 affected frames changed. They now show "INTTURUPT WAIT", as MAME and the PCB do.

**Tested on hardware**
- Two full games played on the MiSTer: gameplay feels right, all controls and Service Mode work.

**Confirmed on the PCB**
- The green stripes during "COLOR RAM CHECK" are real. The PCB shows them too, because palette changes take effect mid-frame. MAME shows solid flashes instead because it applies the palette once per frame. The core matches the PCB here, and the remaining frame differences from MAME during screen transitions are likely the same effect.

## v0.1.1 — 20261021

Timing fix after the first successful Quartus build. That build fit, but missed timing on the core's 96 MHz clock: worst slack −8.8 ns, total −500 ns. With this version the 96 MHz clock meets timing (+1.118 ns setup slack), and **the game runs on a real MiSTer** (first boot 20261021).

**Fixed**
- Video: the shadow darkening (×0.6) used a divider. It was the 200 worst failing paths, about 17 ns at a 10.4 ns clock. It is now a 32-entry lookup table with identical results.
- Blitter: the tilemap position and clip/flip multiplications are split into register stages, with two wait states before each tile is drawn. 505 real blitter runs remain pixel-exact; the worst run takes 16.9% of a frame (was 16.8%).

**Added**
- `scripts/quartus/post_flow.tcl`: after every compile, writes `output_files/timing_paths.txt`, listing every failing endpoint (setup and hold) with its worst path.

## v0.1.0 — 20261021

First version expected to compile in Quartus. Not yet tested on a MiSTer.

**Changed**
- Display frame buffer moved from block RAM to the MiSTer's DDR3 (address 0x30000000).
  - The first Quartus build (20261020) failed: the design needed more than the 553 M10K blocks of block RAM.
  - This frees about 130 blocks; the core now uses about 270.
  - The draw buffer stays in block RAM. Scan-out reads each line from DDR3 one line ahead. The copy goes through a 128-word FIFO, so DDR3 stalls don't slow the blitter.
  - Simulation with a DDR3 model (random stalls): 1,900 frames and all 9.44 M CPU writes identical to the previous design.

**Added**
- Real MAME as a reference: `scripts/build_mame.sh` (headless single-driver MAME), `tools/mame/frame_log.lua` (every frame plus blitter starts) and `scripts/mame_latency.py` (frame-timing comparison).
- `CLAUDE.md`: steering file for future Claude sessions.
- `docs/SAME_BOARD_GAMES.md`: plan for Hebereke no Popoon and Blocken.
- `CHANGELOG.md`: this file.

**Known issues**
- Each blitter result appears **one frame later than in MAME** (confirmed against real MAME, 700 of 700 matched frames). To be fixed after hardware bring-up; see `docs/HANDOFF.md` §10.
- 96 of 1,001 compared frames differ from MAME during title-screen transitions, some only by a few color levels. (v0.1.2: most likely mid-frame palette changes, which the PCB also shows.)
- Never run on real hardware: SDRAM clock phase, DDR3 access, sync positions, centering and audio levels are untested.

## Before v0.1.0 (unversioned)

- **20261020** — OKI M6295 phrase table kept in block RAM. jt6295 dropped sound commands when table lookups went through SDRAM.
- **20261020** — Initial import: 68000 (fx68k), GA9201 blitter (two-phase snapshot design), frame buffers, YM2149, OKI M6295, SDRAM ROM loading with CPU cache, CRT Adjust, MiSTer wrapper, MRA. Verified in simulation only.
