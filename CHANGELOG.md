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

## Unreleased — Hebereke no Popoon and Blocken (branch `multigame`, work in progress)

The core becomes a platform core for the Sunsoft GA9201 board family. The MRA
selects the game with one byte (ioctl index 1): 0 Shanghai III, 1 Hebereke no
Popoon (`heberpop`), 2 Blocken (`blocken`).

**Changed**
- **The core is renamed SunsoftGA9201** (was Shanghai3), after the boards' custom
  graphics chip, since it now runs three games: the Quartus project
  (`SunsoftGA9201.qpf/.qsf/.sdc/.srf`), the top level `SunsoftGA9201.sv`, the OSD
  name, the MRAs' `<rbf>`, released files `releases/SunsoftGA9201_YYYYMMDD.rbf`, and
  `make_release.ps1` (whose zip now carries every MRA). MiSTer keeps settings per
  core name, so OSD options and button mappings start fresh. The GitHub repo is to
  be renamed SunsoftGA9201_MiSTer (GitHub redirects the old name).
- **New ROM layout for every game** (`rtl/shangha3_mem.sv`): program 1 MB, Z80
  64 KB, graphics 3.5 MB, OKI 512 KB, padded with FF by the MRA. **Shanghai III
  needs its new MRA** (`releases/Shanghai III (Japan).mra`); the v1.0.0 MRA won't
  work with this core.
- Controls: a third button (Blocken). The core's button list is now Button 1,
  Button 2, Button 3, Start, Coin, Service, so saved MiSTer button mappings for
  this core need redoing.

**Added**
- `rtl/ga9201_sound.sv`: the heberpop/blocken sound CPU section: Z80 (tv80 with a
  clock enable, `rtl/tv80_cen.v`, 6 MHz), 2 KB RAM, YM3438 (jt12, 8 MHz), sound
  latch; IM 0 interrupts with FF (RST 38h) on the bus, NMI from the YM3438. The
  Z80 program comes from SDRAM (ch3, idle after the download) through a 2 KB cache.
- `rtl/ga9201_mixer.sv`: YM3438 + OKI mix at MAME's balance and level, measured
  (`scripts/snd2_replay.sh` + `scripts/mix_fit.py`: 0.297 × (FM L + R) + 15.8 × OKI,
  5.6 % residual, loudness within 0.3 dB of MAME), with the same OSD balance option.
- Board (`rtl/shangha3_board.sv`): per-game address decode (Blocken's I/O page at
  1000xx and palette at 200000), 16-bit DSW port, sound latch, vblank on INPUTS
  bits 7/15, OKI ROM banking from the coin-control write (heberpop: 256 KB halves;
  blocken: 4 × 128 KB banks above a fixed 128 KB), 68000 reads of the graphics ROM
  at 800000–B7FFFF (byte-swapped from SDRAM), no pen-14 shadows.
- The blitter bus-hold speed model (v0.1.10) applies to Shanghai III only, where
  it was measured on a PCB. On Hebereke no Popoon it halved the attract mode's
  speed against MAME; without a PCB to check, the new games run at MAME's speed.
- Blitter: tile numbers wrap at 28,672 (3.5 MB) on the new games, as MAME's
  `code % total`.
- MRAs for all three games; `scripts/mra_stream.py` builds the download stream
  from an MRA, so `scripts/sim_top.sh MRA ROMDIR N` now tests the MRA too.
- Tests: `scripts/snd_z80_test.sh` (Z80 section: latch interrupts, YM3438 timer
  NMIs, RAM), `scripts/snd2_replay.sh` (MAME sound log through jt12 + jt6295 +
  mixer), `scripts/mix_fit.py`, `scripts/stream_split.py`; `oki_test.sh` plays
  both banks of a 512 KB OKI ROM.

**Verified so far (simulation)**
- Shanghai III unchanged: 900 frames of the board simulation give identical frames
  and an identical CPU write trace to v1.0.0; the end-to-end download → SDRAM →
  boot simulation with the new MRA checks every SDRAM byte; `sim.sh test`,
  `blit_test.sh 50 20` and `oki_test.sh --no-stress --max 8` pass.
- Hebereke no Popoon:
  - boots through all self-tests (ROM 1–2, VIEW WORK, COLOR RAM, CG ROM 1–4,
    which also checks the 68000's graphics-ROM reads) and runs its attract mode;
    attract frames are pixel-identical to MAME (lag 9 frames: boot timing plus
    the core's one-frame display delay) through the title and logo animation;
  - coin, start, mode select, world map, story scene and gameplay (the CPU
    opponent playing) all work with simulated inputs;
  - Z80 I/O writes identical to MAME's (first 4,642 in the board simulation, first
    318 through the full download/SDRAM path);
  - OKI through SDRAM sample-exact on both 256 KB banks with background traffic.
- Blocken: not yet run (needs ROMs).
- No Quartus build yet.

## v1.0.0 — 20261026

First public release.

**Changed**
- `README.md` is now for players: installing, controls, OSD options, DIP switches, what to expect, credits. Build and simulation notes moved to `docs/DEVELOPMENT.md`.
- The development notes for AI-assisted sessions moved to a separate private repo; nothing in the core changed.
- MRA: added `<mameversion>0289</mameversion>`, `<players>2</players>` and a header comment (including which ROM zips a split set needs).
- MRA comment and README: Demo Sounds stays **On** by default (`<switches default="FF BF">`). A stock PCB, with every switch off, has it Off and plays the attract demo silently; the README says how to match that.

**Verified on hardware** (v0.1.10, side by side with Aaron's PCB from the same coin-up, filmed on one phone)
- Shadows under the cursor stay steady, as on the PCB (the v0.1.9 fix).
- The OKI (drums/FX) option works at every setting, and PCB sounds as before.
- Refresh identical: 59.619 Hz (PCB) and 59.618 Hz (core), from the camera's flicker beat.
- The core stayed 0.2–1 s behind the PCB through a full game, the continue countdown, the ranking and the attract loop. The gap goes up and down rather than accumulating: about +0.2 s over the zodiac wheel, +0.35 s over the 85 s of gameplay (0.4 %), about +0.4 s from the time-over box to the ranking, −0.35 s over the dragon intro, +0.3 s over the attract demo.

**Added**
- `scripts/make_release.ps1`: copies the Quartus build to `releases/Shanghai3_YYYYMMDD.rbf` and makes a release zip laid out like the MiSTer SD card (`_Arcade/…`). Steps in `docs/DEVELOPMENT.md`.

## v0.1.10 — 20261025

Game speed matched to the PCB.

**Fixed**
- **The title screen, mode select and zodiac wheel now run at 30 updates per second, as on the PCB** (the core and MAME ran them at 60). Their timers follow: the mode-select timeout now takes about 15 s, as on Aaron's PCB (14.9 s), instead of 7.4 s. Gameplay and the demo stay at 60, as on the PCB.

**How the game paces itself** (from its 68000 code, disassembled with MAME's debugger)
- At the end of each update the main loop raises a "done" flag (307906) and waits. The vblank interrupt starts the graphics chip on the new picture, reads the controls and releases the main loop, but only if that flag is up. An update that isn't finished by the next vblank waits a whole extra frame, so that screen runs at 30.
- Early in each update the main loop also waits for vblank (10A42) before doing some screen work.
- The music driver runs in the vblank interrupt every frame, so the music tempo never changes.

**The model** (`rtl/shangha3_board.sv`)
- On the real board the CPU stops while the much slower GA9201 draws. The core now holds the CPU for 6.875 clocks (72 ns) per pixel its blitter processes, applied from the end of vblank (the CPU must get through vblank first, or every screen would drop to 30).
- Calibrated from Aaron's videos and per-screen measurements (game logic per update from MAME, pixels per picture):
  - mode select: 44 % of a frame of logic, 1.78 screens of pixels: must miss the frame;
  - the busiest demo screen: 26 % and 1.76 screens: must not.
  - That leaves 5.9 to 7.9 clocks per pixel (about 12 to 16 Mpixel/s for the real chip); 6.875 is in the middle.
- Verified in simulation: title, mode select and zodiac at 29.8 updates/s, gameplay at 59.6 (its update takes 76 % of a frame), the attract demo at 58–60 (the PCB video also shows an occasional dropped update there).

**Added**
- `scripts/frame_budget.py`: updates per second, work per update and blitter time, from a board trace.
- `sim/tb_main.cpp`: `--press MASK FROM LEN` (coin/start) and `--pressin MASK FROM LEN` (player buttons), to reach the menus and gameplay in simulation.
- `tools/mame/blit_load.lua`: per-frame blitter workload and update timing in MAME.
- `scripts/sim.sh`: `SIM_OBJ=dir` builds into another folder, so two simulations can run side by side.

## v0.1.9 — 20261024

Two differences from the PCB, found in Aaron's side-by-side videos (PCB and MiSTer on the same display through an OSSC).

**Fixed**
- **Shadows over shadows no longer darken further.** On the PCB, where tile shadows overlap, or where the hand cursor's shadow passes over them, the shadow stays the same. The core, following MAME, darkened them a second time, so overlapping areas went nearly black and changed as the cursor moved.
  - The rule now: a shadow sets bit 7 of the pixel's palette index. Colours 0–127 move to 128–255, where the game keeps their darkened copies (MAME's table for these colours is the same), and a second shadow changes nothing. MAME instead runs already-shadowed colours through a generic ×0.6 darkening.
  - In MAME's gameplay screen about 5 % of the pixels were double shadows.
  - Blitter test against the updated software model: 300 runs, pixel-exact.
- **Refresh rate 59.64 Hz (262 lines per frame),** as measured on the PCB with an OSSC: "262-p, 15.62 kHz, 59.63 Hz". The core used MAME's 263 lines (OSSC: "263-p, 59.40 Hz"), so the whole game ran 0.4 % slow. One blank line less per frame; the picture position is unchanged.
  - CRT Adjust bench: 59 settings, 5.1 M checks pass. Boot frames identical to the previous version.

**Found** (fixed in v0.1.10)
- **The title screen, mode select and zodiac wheel run at 30 updates per second on the PCB,** and at 60 on the core (and MAME). The scrolling text moves and blinks half as fast there. The demo game and gameplay run at 60 on both. Measured frame by frame from Aaron's videos.

## v0.1.8 — 20261023

**Added**
- **OSD option "OKI (drums/FX)":** the balance between the two sound chips. The OKI M6295 plays the sound effects and the music's drums; the YM2149 plays the melody and bass line.
  - Settings: **PCB** (default, the balance measured against the real board, identical to v0.1.7), OKI+ / OKI++ (+3 / +6 dB), OKI− / OKI−− (−3 / −6 dB).
  - Each step moves the OKI half up and the YM2149 half down, so the overall loudness stays about the same (−2.3 … +2.8 dB RMS in the demo music, where the drums carry most of the energy) and nothing clips.
  - Checked in the sound replay bench: PCB is bit-identical to v0.1.7; all five settings, no clipping.

**Build:** 96 MHz setup slack +0.615 ns; every clock passes setup, and `timing_paths.txt` reports no failing setup or hold paths.

**Checked**
- **MiSTer loading box (still open):** the new `scripts/osd_test.sh` runs the framework's own OSD module (`sys/osd.v`) on the core's video, drawing an info box the way the MiSTer menu does. Text shows at every CRT Adjust setting tried (Off, On at 0, and the extremes), so neither the core's video timing nor CRT Adjust should hide it. Next: compare with another arcade core that loads its ROMs the usual way, and with the v0.1.4 core, on the same MiSTer.

## v0.1.7 — 20261022

Aaron's hardware check of v0.1.6 on his CRT: "looks great, sounds great, plays great".

**Changed (by ear, Aaron's request)**
- **Overall volume −3 dB**, with the YM2149/OKI balance unchanged: `(oki × 45 + ay × 90) / 8`. The mixer now has three register stages, because these constant multiplies are no longer free shifts and the 96 MHz clock has little slack (+0.094 ns in v0.1.6).
- **A little less bass:** the YM2149 DC-blocker corner moved from 15 Hz to 58 Hz. The lowest notes (around 100 Hz) are about 1.3 dB quieter.

**Confirmed on hardware**
- v0.1.6 on Aaron's CRT: picture, sound balance and gameplay; CRT Adjust works.
- Kyle (kyledlester) tested v0.1.4: Start/Coin/Service, CRT sync during loading, the Flip Screen DIP and CW/CCW rotation all work. He also reported the double loading bar, fixed in v0.1.5.
- v0.1.6 build: 96 MHz setup slack +0.094 ns. v0.1.7 build: +0.570 ns, 520 / 553 M10K blocks (94 %).

**Checked**
- CRT Adjust H-Position moves in 6-pixel steps (H-Size in 1 % steps, V-Shift in 1-line steps). That's intended: the step size and OSD layout come from Kyle's Nostradamus glue, and 16 settings × 6 pixels cover −48 … +42 pixels.

**Open**
- During a ROM load the MiSTer progress box appears on the CRT (sync held), but Aaron sees no text or bar in it. In his v0.1.4 video, the box showed "Loading / Assembling ROM #0" and "Sending ROM #0" with MiSTer's progress bar. The only video change since then is that the core's own bar was removed (v0.1.5). Under investigation.

## v0.1.6 — 20261022

Sound balance, measured against Aaron's PCB gameplay video.

**Changed**
- **OKI (drums, voices and effects) louder relative to the YM2149 music:** now ×3 (+9.5 dB) compared with before. The mix is `oki × 8 + ay × 16` (was `oki × 2 + ay × 12`).
  - Measured on the PCB recording, the old mix had the OKI 8.4 dB too quiet (median over frequency bands). The season/flower pair sound alone measured about 11 dB too quiet. The new mix lands within about 1 dB.
  - The overall level is about 11 dB higher; the old mix peaked near −13 dBFS. There's no clipping in the replayed demo music with effects.
- **YM2149 bass:** the filter that removes the chip's DC offset cut at 233 Hz, which thinned low notes. It now cuts at about 15 Hz, like the coupling capacitor on a real board.
- The mixer moved to its own file, `rtl/shangha3_mixer.sv` (added to `files.qip`).

**How it was measured**
- MAME's attract demo plays the same tune as the PCB clip. Its YM2149/OKI register writes (`tools/mame/snd_regs.lua`) were replayed through the core's own sound chips and mixer (`scripts/snd_replay.sh`, new). `tools/audio/balance_fit.py` (new) then fitted the PCB audio as YM2149 + OKI, band by band. Details: `docs/DEVELOPMENT.md` (Sound balance).
- Limits: a phone microphone in a room. The ratio is reliable to a few dB, not better.

**Found along the way**
- The season/flower pair sound is OKI phrase 24 (seen in MAME removing a winter + autumn pair). It plays in the PCB clip at 51.6 s.

## v0.1.5 — 20261022

**Changed**
- **Removed the core's own loading bar.** With sync kept during the download (v0.1.4), the MiSTer menu's "Loading / Sending ROM" progress box is visible, and the core's bar appeared as a second one behind it (Aaron's CRT video).

**Confirmed on hardware**
- The CRT stays in sync while the ROMs load.

**Build:** 96 MHz setup slack +0.410 ns.

## v0.1.4 — 20261022

Fixes from Aaron's hardware testing, plus HDMI rotation.

**Fixed**
- **Start and Service buttons.** Start added a credit (it was wired to the board's "service coin" input) and Service acted as Start. The SYSTEM port bits are now in MAME's order: coin 1, coin 2, service, start 1, start 2, service-mode switch.
- **CRTs lost sync while a game loads.** The board is held in reset during the ROM download, and that used to stop the video timing as well. The pixel clock and video timing now run through every reset and download (only a power-up/PLL reset stops them), so the picture is black but in sync.
- **Draw buffer cleared on every board reset,** as MAME starts with an empty bitmap: no leftover picture from before a reset or a reload. The sweep takes 0.9 ms; the blitter waits for it.

**Added**
- **Loading bar** while the ROMs download (256 × 16 pixels, centred). Removed again in v0.1.5.
- **Orientation: Horizontal / Vertical CW / Vertical CCW** (OSD). For vertical (TATE) monitors on HDMI, using the MiSTer framework's `screen_rotate` (as in Kyle's cores). The 15 kHz analog output is never rotated.
  - `screen_rotate` needs the DDR3 port, which the display buffer already uses. The new `rtl/shangha3_ddr_arb.sv` shares it: rotation writes are queued in a 64-entry FIFO and sent between the display buffer's bursts.
  - Tested in simulation with a second master writing every visible pixel (37 M writes): all arrived, none dropped, and the game's frames were unchanged.
  - `MISTER_FB` is now enabled in the qsf.
- **Build (Quartus 17.0.2):** 520 / 553 M10K blocks (94%); 96 MHz setup slack +0.366 ns.

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
- Development notes and a plan for Hebereke no Popoon and Blocken (moved out of this repo in v1.0.0).
- `CHANGELOG.md`: this file.

**Known issues**
- Each blitter result appears **one frame later than in MAME** (confirmed against real MAME, 700 of 700 matched frames). Kept for now: not noticeable in play.
- 96 of 1,001 compared frames differ from MAME during title-screen transitions, some only by a few color levels. (v0.1.2: most likely mid-frame palette changes, which the PCB also shows.)
- Never run on real hardware: SDRAM clock phase, DDR3 access, sync positions, centering and audio levels are untested.

## Before v0.1.0 (unversioned)

- **20261020** — OKI M6295 phrase table kept in block RAM. jt6295 dropped sound commands when table lookups went through SDRAM.
- **20261020** — Initial import: 68000 (fx68k), GA9201 blitter (two-phase snapshot design), frame buffers, YM2149, OKI M6295, SDRAM ROM loading with CPU cache, CRT Adjust, MiSTer wrapper, MRA. Verified in simulation only.
