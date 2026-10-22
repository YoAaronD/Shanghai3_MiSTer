# Shanghai III MiSTer core: handoff, retrospective, and playbook for the next cores

**What this is:** everything a new Claude session needs to continue this project, or to start the next arcade core, without the original conversations. The repo itself (`github.com/YoAaronD/Shanghai3_MiSTer`, private) is the master copy of the code. This file lives in it as `docs/HANDOFF.md`.

**Companion files:**
- `CLAUDE.md` (repo root): short steering rules and the regression gate.
- `docs/SAME_BOARD_GAMES.md`: the implementation plan for Hebereke no Popoon and Blocken, the next work.
- `CHANGELOG.md`: what changed in each version.

**2026-10-22: account switch.** Development moves from Aaron's work Claude account (where v0.1.0–v0.1.3 were built) to his personal Claude account. Nothing from the old sessions is needed beyond this repo. The old sandbox (built tools, MAME, ROM extracts) does not carry over; §0 lists how to rebuild it.

- **Owner:** Aaron (GitHub `YoAaronD`, commits as "AjaxHC" with the GitHub noreply email).
  - Owns a real Shanghai III (Japan) PCB and a MiSTer.
  - Has a Mac, plus a Windows PC laptop with GitHub Desktop and Quartus Prime Lite 17.0.2 (project at `C:\cores\Shanghai3_MiSTer`). The PC also has MAME.
  - Has no measuring tools beyond basic electrical ones.
  - Wants to build **several more arcade cores** after this one.
- **Friend:** Kyle (github.com/kyledlester) has built several MiSTer arcade cores with AI assistance. His Nostradamus core was the model for this project's workflow and CRT Adjust glue.
- **State (v0.1.3, 20261021):** Shanghai III (Japan) **runs on Aaron's MiSTer**.
  - It meets timing at 96 MHz.
  - Its boot checks match his real PCB on video.
  - He played two full games: "feels right"; all controls, Service Mode and pause-on-OSD work.
  - Remaining before v1.0.0: sound balance against the PCB (he has a 4-minute PCB video to share), a CRT Adjust check, and the optional one-frame timing decision (§10).
  - Next big step: the same-board games (`docs/SAME_BOARD_GAMES.md`).

---

## 0. Starting the next session (do this first)

### Checklist for Aaron (new account)
1. **Make sure GitHub has everything.** Every zip from the old account must be committed and pushed, through v0.1.3 plus the docs update that added this section. The latest tag should be `v0.1.3`, and `docs/SAME_BOARD_GAMES.md` should mention "Path of least resistance". The old sandbox can't push, so GitHub is the only copy that carries over.
2. **Connect GitHub to the personal Claude account** (Settings → Connectors / GitHub), with access to the private repo `YoAaronD/Shanghai3_MiSTer`.
3. **Start the session with the repo attached.** Then Claude can commit and push directly. Without it, changes come back as zips for GitHub Desktop.
4. **Attach ROMs:** `shangha3j.zip` (for regressions) plus `heberpop.zip` and/or `blocken.zip` (MAME sets; CRCs in `docs/SAME_BOARD_GAMES.md` §2.3). Or link the Mac folder that holds them. ROMs never go in the repo.
5. **Say** which PCBs you own (heberpop? blocken?) and what you can do this session (Quartus build, MiSTer test).

### Kickoff prompt (paste into the new session)
> Continue my MiSTer core for the Sunsoft GA9201 board. The repo `YoAaronD/Shanghai3_MiSTer` is attached. Read `CLAUDE.md`, then `docs/HANDOFF.md` §0–§1, then `docs/SAME_BOARD_GAMES.md`. Shanghai III (Japan) already works on my MiSTer (v0.1.3). Next I want Hebereke no Popoon, then Blocken, in the same core. ROMs: [attached zips / folder]. Start with the setup in HANDOFF §0, then milestone 0–1 of SAME_BOARD_GAMES §7. Ask me the §9 decisions in one batch.

### Checklist for Claude at session start
1. Read `CLAUDE.md`, this file (§0, §1, §4, §8, §10), then `docs/SAME_BOARD_GAMES.md`.
2. **Tools.** Start both builds in the background while reading:
   - `scripts/setup_sandbox.sh`: flex, Verilator 5.030, dis68k, Pillow/numpy; about 15–20 min. It prints which hosts are reachable. The personal account's network allowlist may differ from the work account's; github.com is the one host that must work.
   - `scripts/build_mame.sh`: SDL2 + headless MAME with just this driver (shangha3*, heberpop, blocken); about 2 h on 2 cores.
3. **ROMs:** `python3 scripts/romtool.py extract --out sim/roms <shangha3j zip or folder>` (shangha3j only until romtool gets per-set tables). Check the new sets' CRCs against `docs/SAME_BOARD_GAMES.md` §2.3.
4. **Quick regressions** (about 5 min; all must pass before changing anything):
   - `scripts/sim.sh test` → "0 failure(s)"
   - `scripts/blit_test.sh 50 20` → "0 failed"
   - `scripts/oki_test.sh --no-stress --max 8` → "PASS"
5. **Baselines** for later comparisons, saved outside the repo: `scripts/sim.sh game 1900 --frames-out DIR --every 30`, about 50 min in the background. With MAME built: `S3_OUT=DIR S3_FRAMES=1700 /opt/src/mame/s3 shangha3j -rompath R -video none -sound none -nothrottle -snapview native -autoboot_script tools/mame/frame_log.lua`.
6. Ask Aaron the open decisions in one batch (`docs/SAME_BOARD_GAMES.md` §9), then work. For any run over 10 minutes, send a status line with an ETA.

---

## 1. Status at a glance

| Area | State | Confidence |
|---|---|---|
| 68000 CPU (fx68k), memory map, I/O, IRQ, protection | Done | High: 1.17 M CPU writes identical to the reference model during boot |
| GA9201 blitter (sprites, zoom, tilemaps, shadows, flip) | Done | High: pixel-exact on 587 real blitter runs |
| Frame buffers + palette video out | Done | High: full-board video matches the reference through the title and demo. Display buffer now in DDR3 (see §4); frames identical to the all-BRAM version in simulation |
| YM2149 (jt49), DIPs through its ports | Done | High |
| OKI M6295 (jt6295) | Done | High: all 56 phrases through download → SDRAM match a direct-ROM chip sample for sample, at game command speed under heavy SDRAM load |
| ROM download to SDRAM, CPU cache, SDRAM controller | Done | Medium-high: simulated with a pin-level SDRAM model. Real SDRAM clock phase is untested. |
| CRT Adjust (analog H-Size / H-Position / V-Shift) | Done | High in simulation: 59-setting bench passes |
| MiSTer wrapper (`Shanghai3.sv`), Quartus project, MRA | Done | Builds in Quartus 17.0.2 Lite; fits after moving the display buffer to DDR3 (v0.1.0); meets 96 MHz timing, +1.118 ns setup slack (v0.1.1) |
| Pause when OSD is open | Done (v0.1.3) | High in simulation (60-frame pause resumes frame-exact); hardware check pending |
| Real hardware | **Runs** (v0.1.1+) | Boots; self-test order and timing match the PCB on video; two full games played; all controls and Service Mode work. The DDR3 and SDRAM paths therefore work on hardware |
| Sound balance | Unverified | Mix levels are a guess; PCB video exists, not yet analysed |
| CRT Adjust on hardware | Untested | Picture position is correct on Aaron's display |

**Next actions:**
1. **Block RAM is nearly full:** v0.1.4 uses 520 of 553 M10K blocks (94%), with +0.366 ns setup slack. Get the per-entity M10K breakdown (Fitter → Resource Utilization by Entity) before adding the new games' memories (`docs/SAME_BOARD_GAMES.md` §6).
2. **Same-board games:** follow `docs/SAME_BOARD_GAMES.md` §7, milestones 0–7.
3. **Shanghai III v1.0.0, in parallel:**
   - sound balance from Aaron's PCB video (AirDrop it to the Mac's linked folder; it's too large for the phone app)
   - a CRT Adjust check on hardware
   - the one-frame timing decision
   - release prep (§13 phase 7)

---

## 2. What was done, in order (session timeline)

1. **Scoping.** MAME-to-MiSTer means re-implementing the hardware in HDL, using MAME as a behavioral reference. Shanghai III (Japan) was picked; no existing MiSTer core for it was found. The MAME driver `shangha3.cpp` was studied.
2. **Starter project.** fx68k, jt49, jt6295 and the MiSTer Template were pulled in. Wrote the board (CPU, memory map, RAM, palette, I/O, protection, IRQ, timing). A hand-assembled 68000 test ROM passes 13 checks.
3. **Real game boot.** Aaron's ROMs match MAME's CRCs. The game boots and passes its own 12 s self-test. A Musashi-based reference model confirmed 1.17 M identical writes. Found and fixed a wait state on every CPU write (the DTACK timing bug).
4. **Software blitter (golden model).** Written from MAME's description. Rendered the whole attract mode correctly and measured the workload (the busiest run visits 172 K pixels).
5. **HDL blitter.** Pixel-exact against the golden model on 587 real runs. Integrated with frame buffers and palette video out.
6. **Real-time vs. instant blitter.** Garbage at boot, then the game dropping to 30 fps, led through three wrong fixes before the root cause: CPU writes racing the blitter, and the CPU stack living inside the list and tilemap ranges. Final design: a two-phase snapshot blitter, with CPU writes held only for not-yet-copied words (0.01% CPU loss, steady 60 fps).
7. **Sound.** jt6295 and the mixer were added; the DSW2 default was corrected to 0xBF (demo sounds on).
8. **MiSTer integration.**
   - SDRAM controller (Sorgelig's, from the M92 core).
   - Memory hub with the ROM download, a 32 KB CPU cache, and tile-row and OKI ports.
   - `emu` wrapper, 96 MHz PLL, Quartus project, MRA with DIPs.
   - Simulated end to end: download → pin-level SDRAM model → boot.
9. **Timing hardening.** SDC multicycle constraint for fx68k-internal paths; narrowed multipliers; block RAMs restructured for M10K inference.
10. **First handoff + retrospective** written.
11. **CRT Adjust** added: rmonic79's module plus glue adapted from Kyle's Nostradamus core, with an H-Position limit table recomputed for this raster and verified by an adapted bench (59 settings, 5.1 M checks).
12. **GitHub.**
    - Repo `YoAaronD/Shanghai3_MiSTer` (private until the core works on hardware).
    - The reused cores are vendored as plain files, and the project is GPL-3.0.
    - Pushed by Aaron from GitHub Desktop, because the sandbox can't push to repos not attached to the session.
13. **OKI-through-SDRAM test** (`scripts/oki_test.sh`). It found a real bug: jt6295 drops commands while it is still reading its phrase table. Fixed with a 1 KB block-RAM copy of the table. Verified on all 56 phrases (19.9 M samples identical).
14. **First Quartus build** (Aaron's PC, Quartus Prime Lite 17.0.2). Synthesis passed; the Fitter failed with error 170048: the design needs more than the 553 M10K blocks. Fix: the display frame buffer moved from BRAM to the MiSTer's DDR3, with a DDR3 model added to both Verilator benches. 1,900 simulated frames are identical to the all-BRAM design.
15. **Real MAME as a reference.** Built a headless single-driver MAME in the sandbox (`scripts/build_mame.sh`, about 2 h). `tools/mame/frame_log.lua` saves every frame and logs blitter starts; `scripts/mame_latency.py` compares them with the board sim. Results:
    - **Confirmed: the core shows each blitter run's result one frame later than MAME** (700 of 700 matched animation frames, +1 in every case; see §10).
    - At that offset, 905 of 1,001 frames (frames 700–1700) are pixel-identical to MAME. The rest differ during title-screen transitions, some by only a few color levels. Not investigated yet (§10).
16. **Steering files for future sessions:** `CLAUDE.md` (repo root, read automatically by Claude) and `docs/SAME_BOARD_GAMES.md` (plan for Hebereke no Popoon and Blocken).
17. **v0.1.1: timing met, and the game runs on Aaron's MiSTer** (20261021). The timing fix (shadow lookup table, pipelined blitter multiplies) took the 96 MHz clock from −8.8 ns to +1.118 ns setup slack. Detailed hardware checks (sound, controls, centering, stability) are pending.
18. **First hardware comparison (PCB video vs. MiSTer video):**
    - The boot checks match the PCB in order and timing (ROM 1 → ROM 2 about 2.5 s → VIEW WORK about 4.7 s → COLOR RAM about 1.75 s).
    - The green stripes during COLOR RAM CHECK appear on the PCB too: palette changes take effect mid-frame on real hardware. MAME shows whole-frame flashes instead, so here the core is more accurate than MAME.
    - Found and fixed the "A" junk screen (v0.1.2, queued blitter start; see §8).
19. **First play test by Aaron (20261021),** who knows the game well:
    - two full games, about three levels each; "feels right"
    - all controls work, and the core menu's Service Mode works
    - the one-frame difference vs. MAME isn't noticeable in play
    - still to check: sound balance against the PCB, picture position on a CRT
20. **v0.1.3: pause when the OSD is open** (Aaron's request, after seeing it in Raki's CV1000 core). See §4.
21. **Handoff for the account switch** (20261022):
    - `docs/SAME_BOARD_GAMES.md` rewritten as a detailed plan
    - draft MRAs for heberpop and blocken in `docs/drafts/`, ROMs and DIPs generated from the driver
    - `tools/mame/frame_log.lua` given a configurable blitter-go address
    - `tools/mame/sound_log.lua` added for the sound section's golden reference

---

## 3. The original hardware (from MAME `src/mame/sunelectronics/shangha3.cpp`)

- **Games:**
  - Shanghai III (1993, Sunsoft; developed by Success): sets `shangha3`, `shangha3u`, `shangha3up`, `shangha3j`. PCB label SUN04C.
  - Hebereke no Popoon (SUN-06).
  - Blocken (KID-07; KID/Visco).

  These share the GA9201 KA01-0249 blitter; the later two add a Z80 + YM3438 sound section. No official platform name was found, so the repo is named after the main game.
- **Clocks:** 48 MHz crystal.
  - 68000 at 16 MHz (48/3)
  - YM2149 at 1.5 MHz (48/32)
  - OKI M6295 from a 1.056 MHz resonator, pin 7 high (8 kHz)
  - Pixel clock 8 MHz (48/6)
- **Video:** 512 × 263 total, 384 × 224 visible (lines 16–239), 59.41 Hz. The refresh rate and sync positions are unverified.
- **Memory map (68000):**

| Address | Function |
|---|---|
| 000000–07FFFF | Program ROM (2 × 256 KB EPROMs, ic3 = high byte, ic2 = low byte) |
| 100000–100FFF | Palette RAM, 2048 × RGBx_555 (R 15–11, G 10–6, B 5–1) |
| 200000 | INPUTS (active low): P1 bits 0–5 = R, L, D, U, B1, B2; P2 bits 8–13 |
| 200002 | SYSTEM (active low): 0 coin1, 1 coin2, 2 service, 3 start1, 4 start2, 5 test, 7 = vblank (low during vblank) |
| 200008 (w) | Blitter go |
| 20000A (w) | IRQ4 acknowledge |
| 20000C (w, even byte) | Coin control |
| 20001F (r) / 20002F (w) / 20003F (w) | YM2149 data read / data write / address. Ports A/B = DSW1/DSW2. |
| 20004E | Protection: successive reads return 0,1,3,7,F,E,C,8,0 |
| 20006F | OKI M6295 |
| 300000–30FFFF | Work + graphics RAM (64 KB). Holds the blitter command list, the tilemap, **and the CPU stack**. |
| 340001 | Flip screen (bit 7) |
| 360000 | Blitter command-list address ("gfxlist"; list starts at gfxlist × 16 bytes) |

- **IRQ4** at vblank start, held until acknowledged. The game's main loop waits for an IRQ-driven frame counter (code at 0x1846).
- **Blitter command format:** 16 words per command; the list runs from gfxlist × 8 words to the end of RAM.

| Word | Meaning |
|---|---|
| 1 | Tile code |
| 2, 3 | x, y in bits 12–4. x ≥ 0x180 means −512; y ≥ 0x100 means −512. |
| 4 | bit 0 flipx, bit 1 flipy, bit 2 condensed 8×8 tilemap, bit 3 tilemap |
| 5 | Color (7 bits) |
| 6, 7 | Width−1, height−1. Both 0 means disabled. |
| 8, 9 | Tilemap source position × 16 |
| 10, 13 | Zoom x/y. Scale = (0x200 − zoom)/0x100. Zoom ≤ 1 on both means a 256× "fill". |
| 11, 12 | Rotation (unused by Shanghai III) |

  - Invalid commands are skipped: width ≥ 512, height ≥ 256, or zoom ≥ 0x1F0.
  - Tiles: 16×16, 4 bpp packed, low nibble = left pixel, 128 bytes per tile, 2 MB graphics ROM.
  - Pen 15 is transparent. Pen 14 is a shadow on sprites (Shanghai III only): destination colors 0–127 become +128, everything else goes to a darkened bank (×0.6).
  - The frame buffer is never cleared.
- **What the game actually uses** (60 s of attract mode):
  - sprites (814 K)
  - tilemaps (7 K)
  - zoomed sprites (891, the floating score)
  - shadows

  It never uses fills, condensed 8×8 tilemaps or rotation.
- **OKI usage:**
  - Attract mode is silent by design (YM2149 register 7 = 0x3F).
  - The demo game enables YM2149 music (register 7 = 0x38) plus OKI effects.
  - The game writes OKI commands as little as **2 µs apart** and polls the channel-busy bits.
- **DIP defaults (MAME):** DSW1 = 0xFF, DSW2 = 0xBF.
- **ROMs for `shangha3j`, with CRCs:**

| File | CRC | Contents |
|---|---|---|
| `s3j_v11.ic3` | e98ce9c8 | Program, high bytes |
| `s3j_v11.ic2` | 09174620 | Program, low bytes |
| `s3j_char-a1.ic43` | 2dbf9d17 | Graphics, 2 MB |
| `s3j_v10.ic75` | f0cdc86a | OKI samples, 256 KB (phrase table in the first 1 KB; 56 valid phrases) |

---

## 4. Core architecture

All logic runs on one **96 MHz** clock (2 × 48 MHz) with clock enables.

| File | Role |
|---|---|
| `rtl/shangha3_board.sv` | The PCB: fx68k, address decode, work RAM (dual port), palette RAM (dual port), I/O, protection, IRQ, jt49, jt6295 + mixer, CPU write arbitration against the blitter |
| `rtl/shangha3_blitter.sv` | GA9201 re-creation (two-phase, see below) |
| `rtl/shangha3_video.sv` | Draw buffer (384 × 224 × 12 bit, BRAM), vblank copy to the display buffer in DDR3, line prefetch into a 2-line BRAM buffer, palette scan-out |
| `rtl/shangha3_video_timing.sv` | Counters, blanking, placeholder syncs, `vblank_next` for CRT Adjust |
| `rtl/shangha3_mem.sv` | ROM download writer, 68000 program cache, tile-row port, OKI port with a block-RAM phrase table |
| `rtl/sdram.sv` | Sorgelig's 4-channel SDRAM controller (GPL-3.0, MiSTer-devel/Arcade-IremM92_MiSTer @68a4683), with Verilator-only port splitting |
| `rtl/shangha3_top.sv` | Board + memory + SDRAM + DDR3 arbiter; shared by the MiSTer wrapper and the end-to-end simulation |
| `rtl/shangha3_ddr_arb.sv` | Shares the DDRAM port between the display buffer (bursts) and the framework's `screen_rotate` (single-beat writes, queued in a 64-entry FIFO, sent between bursts) |
| `rtl/vendor/crt_adjust.sv` | rmonic79's CRT Adjust (unmodified, @c682de9) |
| `rtl/s3_crt_adjust.sv` | CRT Adjust glue adapted from Kyle's Nostradamus core; H-Position limit table for this raster |
| `Shanghai3.sv` | MiSTer `emu` module: hps_io menu, PLL (96 MHz), DIPs (ioctl index 254), joystick mapping, CRT Adjust, arcade_video, `screen_rotate` (Orientation), audio |
| `rtl/pll*`, `sys/` | From MiSTer-devel/Template_MiSTer @5dda373. PLL output hand-edited from 20 to 96 MHz. |
| `Shanghai3.qpf/.qsf/.sdc`, `files.qip` | Quartus project. The SDC sets a 3-cycle multicycle path for fx68k-internal paths. |
| `releases/Shanghai III (Japan).mra` | ROM stream (4 files in order, no interleave) + DIP definitions |
| `microrom.mem`, `nanorom.mem` | fx68k microcode. Quartus loads these from the project folder. |
| `ext/` | fx68k, jt49 (hdl only), jt6295 (hdl only), vendored as plain files; `ext/README.md` records upstream commits |

**Key design points:**

- **CPU timing:** fx68k's phase enables pulse every 3rd clock, giving 16 MHz. Bus timing is cycle-exact. DTACK counts from AS, not DS.
- **Blitter, two phases:**
  1. **Snapshot:** walk the list (reading words 6, 7, 10, 13 first; disabled commands are skipped). Valid commands go into a 2048 × 176-bit buffer. If any command is a tilemap, the 8K-word tilemap area is copied too. This takes about 1% of a frame.
  2. **Draw:** a shared scaled-tile engine (MAME-equivalent 16.16 stepping), with a one-row ROM cache plus a next-row prefetch. The clip/flip and tilemap-position multiplies are registered pipelines; two wait states (`S_D_PRE0/1`) before each tile let them settle (v0.1.1 timing fix).

  The worst case is about 16.9% of a frame.
- **Queued starts (v0.1.2):** a "go" that arrives while a run is in progress is queued (`pend_cnt`, up to 3, with the list address latched in `pend_list`). While a run is queued, `scan_from` is lowered to that run's list start and `tm_from` to 0, so CPU writes to anything it will read wait until its own snapshot. Without this, the boot screen showed rows of "A" instead of "INTTURUPT WAIT" (the game issues two gos 8 µs apart, then reuses that RAM).
- **CPU write arbitration:** a CPU write waits only for RAM words the snapshot hasn't copied yet (`scan_from`, `tm_from`). This matches MAME's instantaneous blitter; CPU loss is about 0.01%.
- **Frame buffers:** draw → display copy at vblank start (0.9 ms of the 2.5 ms vblank). Drawing waits while the draw buffer is read; snapshotting doesn't. Tear-free, but one frame later than MAME (measured; see §10, item 2).
  - The display buffer lives in the MiSTer's DDR3 (`DDRAM_*` port, byte address 0x30000000, `DDRAM_CLK` = the 96 MHz core clock). The copy packs 4 pixels per 64-bit word (96 words per line), goes through a 128-word FIFO (MLAB) and is written in 8-word bursts. Scan-out reads each line during the previous line (12 bursts of 8) into a 2-line BRAM buffer. The screen stays black until the first complete copy.
  - Why: the first Quartus fit ran out of M10K blocks with both buffers in BRAM (each is about 126–132 M10K).
  - Simulated with `sim/ddr_model.h` (random waitrequest, stalls of 50–250 clocks, 10–50 clock read latency). Over 1,900 frames (32 s of attract), every captured frame and all 9.44 M CPU writes, with timestamps, match the all-BRAM design. The end-to-end run (download → SDRAM → boot → DDR3 video) also matches. A 16-word FIFO was too small: DDR3 stalls slowed the copy and with it the blitter (by up to 213 µs). That is why the FIFO is 128 words.
- **SDRAM layout (bytes):**
  - 000000 program (big-endian words)
  - 080000 graphics (little-endian words)
  - 280000 OKI samples

  The download stream is ic3 → ic2 → gfx → oki; the core interleaves the program bytes with byte-masked writes.
- **SDRAM channels** (priority order): ch2 = CPU cache line, ch1 = OKI, ch3 = download, ch4 = blitter rows.
- **CPU cache:** direct-mapped, 512 lines × 4 words.
- **OKI phrase table:** the first 1 KB of the sample ROM is copied into block RAM during download. jt6295 drops a command that arrives mid-lookup, so table reads must be fast. Sample data stays in SDRAM.
- **Audio:** YM2149 high-passed, mixed as `snd = oki × 2 + ay × 12`, saturated to 16-bit signed. The levels are a guess.
- **Inputs:** MiSTer joystick bits 0–3 directions, 4 = B1, 5 = B2, 6 = Start, 7 = Coin, 8 = Service. OSD "Service Mode" is status[6].
- **Pause when OSD is open** (status[7], 0 = On by default): `OSD_STATUS & ~status[7]` freezes the CPU clock enables (mid-cycle, resuming exactly), the YM2149 and OKI enables, and mutes the output. Video timing, the frame-buffer copy and the blitter keep running, so the screen holds the last picture. Requested by Aaron after seeing it in Raki's CV1000 core (that repo publishes only its simulation, so this uses the standard MiSTer `OSD_STATUS` signal). Verified: `sim.sh game ... --pause 900 60` gives 60 frozen frames and then exactly the normal run shifted by 60 frames.
- **Resets (v0.1.4):** `vid_reset` (= `sdram_init`, i.e. PLL not locked) is the only reset of the pixel clock, video timing, display path and DDR3 master, so sync never stops. The board reset (`reset || ioctl_download || sdram_init || !mem_ready`) resets the CPU, blitter, sound and I/O. In the video module it only acts as `clear`: black screen, a 0.9 ms sweep that zeroes the draw buffer (blitter held), and the picture returns with the first complete copy made after the sweep. Never reset the DDR3 master mid-burst; that's why it isn't on the board reset.
- **Loading progress:** the MiSTer menu draws its own progress box during ROM downloads, as long as the core keeps sync (it does since v0.1.4). Don't draw a second bar in the core; one was tried and showed up twice on Aaron's CRT.
- **Orientation (v0.1.4):** status[9:8] = Horizontal / Vertical CW / Vertical CCW. `screen_rotate` (in `sys/arcade_video.v`) writes the rotated picture to DDR3 at 0x24000000 and switches the HDMI scaler to framebuffer mode. Requires `MISTER_FB` in the qsf. Aspect ratio swaps to 3:4 when rotated. `screen_rotate` ignores `DDRAM_BUSY`, so the arbiter queues its writes.
- **Inputs (fixed in v0.1.4):** SYSTEM = {1, service-mode switch (OSD), start2, start1, service1, coin2, coin1}, with joystick 6 = Start, 7 = Coin, 8 = Service (service1 is a service credit). Before v0.1.4 Start and Service were in the wrong bits.
- **OSD status bits used:** 0 reset; 3–5 scandoubler fx; 6 service; 7 pause-when-OSD-open (0 = on); 8–9 orientation; 96 CRT Adjust on; 101–104 H-Position; 105–108 V-Shift; 112–116 H-Size; 121–122 aspect.
- **Invariants: don't break these**
  - **Instant-at-go semantics:** every blitter run must draw RAM exactly as it was when its "go" was written, including queued runs. Enforced only by the CPU write arbitration in `shangha3_board.sv` (`blit_wr_conflict`, using `scan_from`/`tm_from`). CPU *reads* are never held.
  - **The CPU stack lives inside the list/tilemap RAM area.** Any rule that holds CPU writes for long (e.g. the whole list while queued) stalls the CPU; that's correct, but only acceptable because double gos are rare.
  - **fx68k phases must alternate:** `en_phi1` and `en_phi2` come from `cpu_div`/`cpu_phase`. Pause freezes the counters themselves, not just the enables, so the phase order survives a pause.
  - **DTACK counts from AS**, not UDS/LDS. A held RAM write must also delay its write strobe (`ram_wr_done`).
  - **The OKI phrase table is read from BRAM, never SDRAM** (jt6295 drops commands during slow table reads). `oki_rom_ok` may only be high while the address is unchanged and the data matches.
  - **CPU cache:** the tag read is stale for 2 clocks after a fill (`fill_we_d` guard). A hit needs `addr_q == prog_addr`.
  - **DDR3 display buffer:** the copy holds the blitter only while the draw buffer is being *read*. The 128-word FIFO absorbs DDR3 stalls. A new copy starts only if the previous one finished; otherwise that frame is skipped. The screen is black until `disp_valid`.
  - **Palette is read live during scan-out,** so palette writes take effect mid-frame. That matches the PCB (green stripes at COLOR RAM CHECK) and differs from MAME; don't "fix" it.
  - **Timing hygiene at 96 MHz:** no dividers; register both sides of every multiplier; check TimeQuest Setup Summary on each build (`output_files/timing_paths.txt` lists failing endpoints).
- **Estimated block RAM:**

| Item | Size |
|---|---|
| Draw buffer | 1.03 Mbit (about 126–132 M10K) |
| Display buffer | in DDR3 (was another 1.03 Mbit) |
| Line buffer + copy FIFO | about 2 M10K |
| Command snapshot | 352 Kbit |
| Tilemap snapshot | 128 Kbit |
| Work RAM | 512 Kbit |
| Palette | 32 Kbit |
| Cache | about 36 Kbit |
| OKI table | 8 Kbit |
| CRT Adjust | about 1 M10K |
| **Total** | **about 2.1 Mbit (about 270 M10K of 553)**, before the MiSTer framework |

  The first fit (both frame buffers in BRAM, about 395 M10K for the core) failed: core plus framework needed more than 553 M10K. Moving the display buffer to DDR3 frees about 130.
  If it still doesn't fit, the next levers, in order:
  1. Uncomment `MISTER_DISABLE_ADAPTIVE` in `Shanghai3.qsf` (drops the HDMI scaler's adaptive-scanline line buffers; few people use it).
  2. Shrink `cmdbuf` in the blitter from 2048 to 1024 commands (about 18 M10K; the game uses at most 614 valid commands).
  3. `MISTER_DISABLE_ALSA` (small).

---

## 5. Verification tools and results

| Tool | What it does | Time |
|---|---|---|
| `scripts/setup_sandbox.sh` | Builds and installs the simulation tools in a fresh sandbox; prints which hosts are reachable | 15–20 min first time |
| `scripts/romtool.py extract --out sim/roms ZIP_OR_DIR...` | Checks CRCs; writes `prog.bin`, `blitter.bin`, `oki.bin` | seconds |
| `scripts/sim.sh test` | 68000 boots a hand-assembled test ROM; 13 automated checks | ~15 s |
| `scripts/sim.sh game N [--frames-out DIR --every K --wav F --no-rom-log --log-from F]` | Full board on the real ROMs (served directly); bus trace, frames, audio | ~1.25 s per frame |
| `scripts/sim_top.sh ROMDIR N [--frames-out DIR --every K --check-sdram --wav F]` | **End to end:** emulated MiSTer download → pin-level SDRAM model → boot from SDRAM | ~1.3–2 s per frame |
| `scripts/build_mame.sh` | Builds SDL2 + a headless MAME with only this driver (`/opt/src/mame/s3`) | ~2 h once |
| `S3_OUT=DIR /opt/src/mame/s3 shangha3j -rompath R -video none -sound none -nothrottle -snapview native -autoboot_script tools/mame/frame_log.lua` | Real MAME: every frame as PNG + blitter-start log (`-wavwrite F` for audio). `S3_GO=100008` for blocken | ~10 s for 1,700 frames |
| `S3_OUT=DIR S3_FRAMES=N /opt/src/mame/s3 heberpop ... -autoboot_script tools/mame/sound_log.lua` | Real MAME: 68000 sound-latch writes and every Z80 I/O read/write, timestamped (`S3_LATCH=10000F` for blocken). Z80 taps untested | seconds |
| `sim.sh game N ... --pause FROM LEN` | Holds the pause input for LEN frames from frame FROM | — |
| `sim_top.sh ROMDIR N --rotate-traffic` | Adds a second DDR3 master writing every visible pixel (like `screen_rotate`) and checks every write arrived intact | as `sim_top.sh` |
| `scripts/mame_latency.py MAME_DIR HDL_DIR TRACE [first last]` | Frame latency of the core vs. MAME (HDL frames from `sim.sh game N --frames-out DIR --every 1`) | ~1 min |
| `scripts/blit_test.sh EVERY MAX [--dump-filter zoom\|tilemap]` (`LATENCY=16` env) | Replays real blitter runs through the HDL blitter; pixel-exact check | seconds to minutes |
| `scripts/oki_test.sh [--no-stress] [--max N] [--gap CLK] [--wav F]` | Two jt6295s, one through download → SDRAM, one direct; every valid phrase, sample-for-sample | ~1 min (`--max 8 --no-stress`), ~20 min full |
| `scripts/crt_test.sh` | CRT Adjust bench: every H-Size at both H-Position extremes, plus V-Shift | ~3 min |
| `scripts/build_refmodel.sh`, `sim/refmodel/refmodel` | Musashi 68000 + memory map + software blitter: traces, PPM frames, blitter snapshot dumps | ~250× faster than HDL |
| `scripts/compare_traces.py`, `scripts/compare_frames.py` | Write-order comparison; frame matching within ±N frames | — |
| `/opt/tools/dis68k ROM HEXADDR COUNT` | 68000 disassembler (built by the setup script) | — |

**Results:**
- **Boot:** 1.17 M writes identical.
- **Blitter:** 517 + 40 zoom + 30 tilemap runs pixel-exact. A deliberately broken shadow makes 25 of 52 fail, so the test catches errors.
- **Full board, 1800 frames:** every frame up to 1110 is identical to a reference frame (time-shifted). The HDL runs the title at 60 fps, while the Musashi reference drops frames. The real PCB looks smooth, which matches the HDL.
- **SDRAM path:** all 2,883,584 bytes correct, and boot frames match.
- **OKI via SDRAM:** all 56 phrases at 2 µs command spacing, under 111 M blitter-row reads and 1.2 M CPU cache misses. 19.9 M samples identical.
- **CRT Adjust:** 59 settings, 5.1 M checks pass.

---

## 6. GitHub and day-to-day workflow

- **Repo:** `github.com/YoAaronD/Shanghai3_MiSTer`, private, GPL-3.0. Make it public in Settings → General → Change visibility once the core works on hardware.
- **Not in the repo:** ROMs, simulation output, and Quartus build output (see `.gitignore`).
- **The sandbox can only push to repos attached to the session.** It cannot create repos, and it cannot push to a repo created mid-session. Attach the repo at session start.
- **If not attached:** Claude sends a zip of the changed files (paths preserved). Aaron unzips it into the repo folder, then in GitHub Desktop: write a summary → Commit to main → Push origin.
- Aaron's local repo folder (e.g. `C:\cores\Shanghai3_MiSTer`) is also the Quartus project folder. Quartus output folders are git-ignored.
- **History so far:** every change was delivered as a zip and committed by Aaron from GitHub Desktop. Tags: `v0.1.0` (DDR3 display buffer), `v0.1.1` (timing), `v0.1.2` (boot "A" fix), `v0.1.3` (pause on OSD). The account-switch docs update follows v0.1.3, untagged.
- **Delivering builds:** Quartus writes `output_files/Shanghai3.rbf`. **Project → Clean Project deletes it** until the next compile finishes; `output_files/` is git-ignored. Releases go in `releases/` as `Shanghai3_YYYYMMDD.rbf`.
- **Quartus leaves `c5_pin_model_dump.txt` in the project folder;** it's git-ignored now. If GitHub Desktop ever lists a build file, ignore it rather than committing it.

---

## 7. Decisions and why

1. **Re-implementation, not a port:** MAME is a behavioral reference only; no MAME code is in the core.
2. **Reuse proven parts:** fx68k, jt49, jt6295, the MiSTer Template, Sorgelig's SDRAM controller, and rmonic79's CRT Adjust with Kyle's glue.
3. **A software golden model before the HDL blitter:** this gave the first pictures in one session, and pixel-exact unit tests.
4. **96 MHz single clock**, with integer enables (CPU ÷6, pixel ÷12, PSG ÷64) and a fractional OKI enable. The cost is an fx68k multicycle constraint.
5. **Two-phase snapshot blitter:** the only design that matches MAME's instant blitter without starving the CPU.
6. **Byte-masked download interleave:** avoids MRA `<interleave map>` byte-order subtleties.
7. **Program cache in front of SDRAM:** the 68000 needs data within about 10 clocks.
8. **OKI phrase table in block RAM:** jt6295 command handling needs fast table reads.
9. **CRT Adjust in front of `arcade_video`, HPOS_SYNCSHIFT, clamped H-Position:** Kyle's hardware-proven pattern.
10. **Vendored dependencies:** so a GitHub zip download builds without submodules.
11. **Display buffer in DDR3, draw buffer in BRAM:** the blitter does read-modify-write at full speed, so its buffer must stay in BRAM. The display side only needs one sequential write per frame and one line read per line, which DDR3 handles easily. Single-buffering instead would save the same memory but tear: in the attract run, about 2% of blitter runs would still be drawing when the screen starts.

---

## 8. Bugs found (and the lesson in each)

| Bug | Lesson |
|---|---|
| DTACK waited for UDS/LDS; the 68000 asserts these late on writes (a wait state on every write) | Time bus handshakes from AS |
| Frame-buffer row offset computed in 16 bits (223 × 384 overflows) | Lint with `-Wall`; size products explicitly |
| Flipped sprite strips: later tiles kept the negated step | Reload per-tile state |
| RAM write strobe fired at cycle start, so holding DTACK didn't delay it | A stalled write must also delay the strobe |
| CPU cache tag stale for 2 clocks after a fill (duplicate fill) | BRAM read-after-write needs a guard |
| SDRAM model returned data one cycle early | Derive model latency from the controller's expectations |
| Boot garbage, then 30 fps: the real-time blitter raced the CPU, and the stack is inside the list region | Start from MAME's semantics (atomic at "go"); measure before fixing |
| DSW2 default 0xFF (demo sounds off) | Take every default from the driver at the start |
| OKI dropped commands: jt6295 ignores a command during its phrase-table lookup, and SDRAM lookups were too slow for 2 µs command spacing | Check reused cores' timing assumptions against the game's real access patterns |
| Verilator re-ran an in-block initializer in `sdram.sv` | Keep initialized declarations at module scope |
| First Quartus fit: out of M10K (two 384 × 224 frame buffers plus the MiSTer framework) | Count M10K blocks, not bits, against the 553 available, and leave room for the framework; do an early Quartus build with the big memories in place |
| First fitting build missed 96 MHz timing by 8.8 ns: a divide-by-10 (shadow colour) in one clock, plus unregistered multiplies in the blitter | Use no dividers and register around every multiplier; check TimeQuest's Setup Summary on every build. `output_files/timing_paths.txt` lists every failing endpoint |
| Start added credits and Service acted as Start: SYSTEM port bits wired in the wrong order (start1 on the service1 bit) | Check every input bit against the driver's `INPUT_PORTS` with a table, and test each button on hardware |
| CRT lost sync during every ROM load: the video timing was reset with the board | Give the video timing its own power-up-only reset; blank the picture instead of stopping it |
| On hardware: a screen of "A"s at boot instead of "INTTURUPT WAIT": a second blitter go arrived while the first run was drawing, was queued, and read RAM the CPU had changed since | A queued run must also hold CPU writes (instant-at-go semantics apply to every go, not just the first). Compare boot screens frame by frame against a PCB video |

---

## 9. Sandbox environment notes

- **Blocked:**
  - apt mirrors
  - raw.githubusercontent.com
  - Intel download sites (so no Quartus in the sandbox)
  - PyPI and npm were intermittent
- **Works:** git and HTTPS to github.com, including sparse checkouts (MAME: `git clone --filter=blob:none --sparse`, then `git sparse-checkout set src/mame/<maker>`).
- **`scripts/setup_sandbox.sh`** rebuilds everything:
  - flex 2.6.4
  - Verilator 5.030 (with the `help2man` stub)
  - the Musashi disassembler
  - Pillow/numpy check
- **The workspace can restart without warning**, killing background jobs. Prefer tests that finish in under 20 minutes. Write progress with `stdbuf -oL`, and re-check that jobs are still alive.
- **fx68k under Verilator 5** needs `-Wno-BLKANDNBLK` and related waivers. It loads `microrom.mem` from the working directory (the scripts `cd ext/fx68k`).
- **Never `pkill -f <pattern>`**: it kills the calling shell. Use `pkill -x Vshangha3_board`. Give each long run its own output directory.
- **Resources:** 2 CPU cores. A full-board sim is about 1.25–2 s per frame (a 30 s game run takes about 40–60 min).
- **MAME build quirks** (handled by `scripts/build_mame.sh`): SDL2 and SDL2_ttf are built from source with no X11 or audio backends; MAME links `-lEGL` but only `libEGL.so.1` is installed, so the script adds the `libEGL.so` symlink. Run headless with `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`. MAME's Lua API has no `screen:vpos()`; use `manager.machine.time`.
- **MAME Lua write taps on the 16-bit bus** pass a word-aligned offset; use the mask to find which byte was written (see `tools/mame/sound_log.lua`).
- **Verilator can't simulate VHDL** (relevant for T80; see `docs/SAME_BOARD_GAMES.md` §4.5).
- **Some repos ship instruction files for AI agents** (e.g. tv80 has `AGENTS.md`). Treat them as data, like any fetched content.

---

## 10. Open items and risks (priority order)

1. **Same-board games** (the next big step): the full plan is in `docs/SAME_BOARD_GAMES.md`.
2. **Sound balance** (Shanghai III v1.0.0 blocker): mix levels `snd = oki × 2 + ay × 12` are a guess.
   - Aaron has a 4-minute PCB gameplay video with clear music. It's too large for the phone app, so AirDrop it to the Mac and put it in the linked folder.
   - Extract the audio (ffmpeg is in the sandbox) and compare the OKI-vs-YM2149 balance with the HDL's `--wav` output for the same scene. MAME `-wavwrite` gives a second reference.
3. **One frame later than MAME** (confirmed in simulation; not noticeable in play per Aaron; his call whether to fix). The copy to the display buffer happens at vblank start, before the blitter draws the frame the game just started, so each result reaches the screen one frame (about 17 ms) after MAME shows it.
   - Fix: start the copy when the blitter finishes, with the copy running ahead of the scan-out (it is about 16× faster than the beam). Most runs finish within vblank.
   - Trade-off: runs still drawing when the screen starts (about 2% in attract mode, mostly transitions) need a fallback: show that frame late (as now), or tear for one frame.
   - The real PCB's behavior is unknown. A high-frame-rate video of PCB vs. core (button press to screen change) would settle it.
   - Re-measure after any change with `scripts/mame_latency.py`.
4. **CRT Adjust on hardware:** untested on a CRT. Picture position is correct on Aaron's display.
   - **Also pending on hardware (v0.1.4):**
     - CRT stays in sync while loading (MiSTer progress box visible) — confirmed on Aaron's CRT 20261022
     - Start / Coin / Service buttons
     - Orientation CW/CCW on HDMI
     - Flip Screen after a reset (it works in simulation)
5. **Frames that differ from MAME** at the 1-frame offset: about 86 of 1,001, during title transitions. Most are likely mid-frame palette changes, which the PCB also shows (confirmed for COLOR RAM CHECK). Some differ by only a few color levels; check the shadow rounding against MAME's palette shadow table.
6. **Video:** sync positions are guesses (HS 416–447, VS lines 244–246). Centering looks right on Aaron's display. If HS_START changes, recompute the CRT Adjust table (formula in `rtl/s3_crt_adjust.sv`) and run `scripts/crt_test.sh`.
7. **CPU cache miss cost:** about 1.6% slower during the boot ROM checksum. Gameplay felt right to Aaron.
8. **Unknowns that need the PCB** (logic analyzer about $15–30, EPROM programmer about $50–70): real blitter speed and arbitration, frame buffering, refresh rate.
9. **Release:**
   - README with screenshots and install steps
   - dated `.rbf` in `releases/`
   - make the repo public (Settings → General → Change visibility)
   - tag `v1.0.0`

---

## 11. Observations

What we noticed along the way: facts, not rules. The retrospective and playbook below turn them into recommendations.

**About MAME as a reference**
- MAME describes behavior, not timing. Several of its devices act instantly: the blitter draws the whole list the moment "go" is written; the OKI reads its ROM with no latency. The game code quietly depends on that, for example by rewriting the list right after "go". Every place where MAME is instant and hardware isn't became a bug or a design problem.
- MAME's comments are the best risk list. "Refresh rate is unknown", "pin 7 not verified" and "zoom is very rough" pointed straight at the parts that are still uncertain.
- MAME's defaults matter for testing. The DIP default decided whether the attract mode made any sound at all.

**About this game and board**
- Shanghai III runs right at the edge of its CPU budget. Small timing differences (a wait state per write, cache misses, the CPU being held for the blitter) visibly change its frame rate. That made frame rate a sensitive health check for the whole core.
- The game keeps its CPU stack inside the same RAM area as the blitter's command list and tilemap. Nothing in MAME says so; we found it with a disassembler.
- The game sends sound commands only 2 µs apart, faster than the reused OKI core tolerates with slow ROM. The game's real access patterns, measured from a trace, were more informative than any datasheet.
- On the real board, attract mode looks smooth (Aaron's observation). That one remark settled a design question the simulations couldn't.

**About reused cores**
- Reusable cores (fx68k, jt49, jt6295, Sorgelig's SDRAM controller, CRT Adjust) saved most of the work. But each carries assumptions from the systems it was proven on: fx68k's ~40 MHz single-cycle limit, jt6295's fast-ROM expectation, the SDRAM controller's read latency. Problems showed up exactly where our use differed from theirs.
- Kyle's repos were unusually valuable: working MiSTer integration for the same building blocks, plus test benches that already encode what matters to a CRT.

**About verification**
- Comparing against a golden model at the level of whole frames or whole runs gave clear pass/fail answers. Comparing timing-dependent things (frame numbers, write order after interrupts start) mostly produced noise.
- Every bench that compared two implementations side by side (HDL vs. software blitter, SDRAM OKI vs. direct OKI) found something, or confirmed a fix, within minutes to an hour.
- Simulation models and testbenches had bugs of their own (the SDRAM latency, overlapping runs, buffered logs). About a third of debugging time went into the test setup, not the design.

**About the working environment**
- Most of the session's wall-clock time was spent waiting on long simulations, not writing code.
- The cloud workspace restarted at least twice without warning, killing background runs and changing some environment details.
- The workspace can reach github.com but not Ubuntu's package mirrors, Intel's downloads, or (reliably) PyPI. Setting up tools took about an hour of trial and error the first time.
- GitHub access is per session, and only for repos attached at the start. The sandbox can't create a repo, or push to one created mid-session.
- Quartus can't run in the sandbox, so synthesis results (fit, timing, block RAM) depend on Aaron's PC. That splits every hardware iteration between two machines.
- The first Quartus build came very late (after every subsystem was finished) and failed on block RAM, which the handoff had already flagged as the biggest fit risk. The Quartus error only says "more than 553" without a breakdown; the per-memory numbers are in the Fitter report (Resource Section).
- The linked computer for file access was the Mac; Quartus runs on the Windows laptop, so its reports weren't reachable from the session.

**About hardware testing**
- Phone videos of the PCB and the MiSTer at the same moment were the most useful hardware data. One 10-second clip each settled the COLOR RAM stripes question and exposed the "A" junk bug, by comparing frames extracted with ffmpeg.
- MAME isn't raster-accurate: it applies the palette once per frame, so mid-frame palette effects that the real PCB shows look different in MAME. "Differs from MAME" isn't automatically a bug; the PCB decides.
- The game's own power-on self-test is a free timing check: the PCB showed the same check order and the same seconds between checks as the core.
- Aaron, who has played the game a lot, judged gameplay feel immediately. Expert play testing is cheap and catches what simulation can't.

**About working together**
- Short status messages mattered. Aaron asked "do you need anything?" during long silent runs.
- Decisions that were Aaron's to make (repo name, visibility, public vs. private, which game) were quick once asked plainly. The slow part was discovering mid-task that a decision was needed.
- Aaron's PCB is the only source for some facts: refresh rate, sync positions, sound balance, blitter speed. Even rough observations by eye or ear are useful data.

---

## 12. Retrospective

### What worked well (keep doing)
- **A fast software reference model:** first pictures early, 250× faster than HDL, golden data for unit tests.
- **Unit-level replay benches** for each block: blitter snapshots, the two-chip OKI comparison, the CRT Adjust bench. Each runs in seconds to minutes and gives an exact pass/fail. The OKI bench found a real bug in one hour that a full-game run hadn't produced after two killed attempts.
- **Sabotage tests:** break the design on purpose to prove a test can fail.
- **Measuring before redesigning,** once we started: stall counters, PC sampling, the disassembler.
- **Reusing proven cores and a friend's hardware-proven glue** (Kyle's CRT Adjust integration).

### What cost the most time, and what to do instead
1. **No version control until the end.** *Instead:* create the GitHub repo first, attach it to every session, and commit at every verified milestone.
2. **Hour-long full-board simulations,** and the workspace restarting kills them. *Instead:*
   - Build a unit bench for each block before any full-game run.
   - Use Verilator `--savable` checkpoints after the boot self-test.
   - Use the reference model to locate frames of interest.
3. **Fixing before diagnosing** (the blitter race took four 40-minute runs). *Instead:* when an HDL block replaces an instantaneous MAME model, design for MAME's semantics from the start, and instrument before changing anything.
4. **Trusting reused cores' interface assumptions** (jt6295's command handling during table lookups). *Instead:* for every reused core, list its timing assumptions (ROM latency, command spacing) and test them against the game's real access pattern, measured from a trace.
5. **Process hygiene:** overlapping runs corrupted traces. *Instead:* unique output directories, `pkill -x`, and line-buffered logs.
6. **Musashi isn't cycle-exact,** which made speed comparisons ambiguous. *Instead:* use MAME as the timing reference (`mame <set> -debug`, `trace`, snapshots on Aaron's machine).
7. **Defaults discovered late** (DIP switches). *Instead:* a driver-derived checklist at the start (see the playbook).
8. **Environment discovered piecemeal.** *Instead:* run `scripts/setup_sandbox.sh` first. Ask the admin to allowlist the Ubuntu archive, raw.githubusercontent.com and Intel downloads (which would allow Quartus builds in the cloud), or run Verilator and Quartus on Aaron's PC.
9. **Simulation models need design-level care** (the SDRAM model off-by-one).
10. **Synthesis feedback came late.** *Instead:* do a Quartus build of a skeleton (CPU + RAM + video out) in the first week, then build incrementally.
11. **Communication:** silent long waits. *Instead:* a status line with an ETA for anything over 10 minutes; batch the questions that need Aaron.
12. **GitHub access was set up mid-project,** and the sandbox couldn't create or push to the new repo. *Instead:* create the empty repo on github.com before the session and attach it.

---

## 13. Playbook for the next arcade core

### Phase 0: before the first session (Aaron, about 15 min)
- Pick the game. Find its MAME driver file and set name.
- Check for an existing core (MiSTer-devel, Jotego's jtcores, Kyle's repos, the MiSTer forum).
- Create an **empty private repo** on github.com (`<Game>_MiSTer`, or `<Board>_MiSTer` for a platform).
- Have the ROM zip ready (split or merged MAME set). Have Quartus 17.0.2 Lite installed on the PC.

### Phase 1: research (first session, about 1–2 h)
- Sparse-clone MAME and read the driver. Fill in this **checklist** in `docs/HARDWARE.md`:
  - CPUs and clocks; the crystal → every derived clock
  - Full memory map, including mirrors and unmapped reads
  - Interrupts: sources, levels, acknowledge
  - Video: total and visible size, refresh rate, sync if known, palette format, layers/sprites/blitter description
  - Sound chips, clocks, routing, mix levels; any sound CPU and latches
  - Inputs: polarity, bit layout; DIP banks and **MAME defaults**
  - Protection or custom chips, and how MAME handles them (instant? simplified?)
  - ROM regions, CRCs, interleaving, byte order
  - MAME TODOs and "not verified" notes (these are the risk list)
- Decide the system clock: a multiple of the crystal that gives integer enables (use 96 MHz for 48 MHz boards when possible).
- List reusable cores for each chip (fx68k, T80, jt12/jt49/jt51/jt6295 etc.), and note each one's timing assumptions.

### Phase 2: skeleton plus an early Quartus build (about 1 session)
- Copy from this repo as a starting template:
  - `sys/`, `rtl/pll*`, `rtl/sdram.sv`
  - the `shangha3_mem.sv` pattern (download writer, CPU cache, ROM ports)
  - the `Shanghai3.sv` wrapper (OSD, DIPs, inputs, CRT Adjust)
  - `scripts/` (romtool, sim scripts, compare scripts, setup)
  - the Verilator testbench patterns (`tb_main.cpp`, `top_tb.cpp` with the SDRAM model)
- Bring up CPU + RAM + ROM + video timing with a test-pattern output.
- **Aaron runs the first Quartus build now** to catch fit, timing and tooling problems early. Put placeholder memories of the final sizes in (frame buffers, work RAM) so the M10K count is realistic.
- Budget block RAM in **M10K blocks** (553 on the DE10-Nano; a 12-bit-wide 86K-deep buffer costs about 126–132), keep about 100–150 for the MiSTer framework, and plan frame buffers in DDR3 from the start if they don't fit.
- Ask Aaron to link the PC that runs Quartus (or connect its project folder), so the session can read `output_files/*.rpt` directly.

### Phase 3: board logic plus the reference model
- Hand-assembled CPU test ROM: reset vectors, RAM, I/O, IRQ.
- Software reference model (Musashi or another CPU core plus the memory map). Compare write traces against the HDL from boot.
- Disassemble the game's boot code with `dis68k` to understand self-tests, wait loops and the main loop.

### Phase 4: custom chips, each with its own golden model and replay bench
- Write the software model of each custom chip from MAME. Get pictures and sound out of it.
- Write the HDL. Dump real inputs and outputs from the reference model; replay them through the HDL and require exact output. Add a sabotage test.
- **Check MAME's semantics:** if MAME does something instantly, design the HDL so the CPU sees the same atomic behavior.
- Measure the game's real access patterns (command spacing, burst rates) and test reused cores against them.

### Phase 5: integration
- Full-board sim with frame and audio capture; compare frames with the reference (±N frames).
- SDRAM path: download emulation + pin-level model + content check + boot.
- Unit benches for the SDRAM-fed paths (like `oki_test.sh`).
- CRT Adjust: recompute the H-Position table for the new raster and run the bench.

### Phase 6: hardware bring-up
- Quartus build: fit, timing, M10K inference. Then the MiSTer:
  1. boot / self-test
  2. title
  3. demo
  4. controls and DIPs
  5. audio levels
  6. video centering on HDMI and CRT
- If the PCB is available: compare refresh rate, centering, sound balance and frame pacing by eye, or with a logic analyzer.

### Phase 7: release
- README with install steps, the MRA(s), credits and licenses.
- Make the repo public and tag a release with the `.rbf`.

### Rough effort guide (from this project)
- Research + skeleton: 1 session.
- CPU board + reference model: 1 session.
- Main custom chip: 1–2 sessions, with most of the time in integration surprises.
- Sound + SDRAM + wrapper: 1 session.
- Hardware bring-up: unknown until the first build. Budget several short build-test-fix cycles.

---

## 14. References

- MAME driver: `src/mame/sunelectronics/shangha3.cpp` (copy in `docs/mame/`, MAME @ab2d1ca)
- fx68k: github.com/ijor/fx68k @0602ee4
- jt49: github.com/jotego/jt49 @6f1247f
- jt6295: github.com/jotego/jt6295 @7d76b0b
- MiSTer Template: github.com/MiSTer-devel/Template_MiSTer @5dda373
- SDRAM controller: github.com/MiSTer-devel/Arcade-IremM92_MiSTer `rtl/sdram.sv` @68a4683
- MRA syntax reference: MiSTer-devel/Arcade-IremM72_MiSTer `releases/*.mra`
- CRT Adjust: github.com/rmonic79/MiSTer-CRT-Adjust @c682de9
- Kyle's cores (workflow, CRT Adjust glue and bench): github.com/kyledlester, especially Nostradamus_Magical_Cat_Adventure_MiSTer
- Musashi (reference model and disassembler only): github.com/kstenerud/Musashi @313ebf1
- Hardware background: nicole.express, "The other type of mahjong" (the 1988 Shanghai hardware is a different design: V30 + HD63484)
- For the next games:
  - jt12 (YM2612/YM3438): github.com/jotego/jt12 @efa4068
  - tv80 (Verilog Z80): github.com/hutch31/tv80 @66a131c
  - T80 (VHDL Z80): github.com/MiSTer-devel/Arcade-Galaga_MiSTer `rtl/cpu/T80se.vhd` @7f89f57
- Raki's CV1000 core (the pause-on-OSD idea; its public repo has only the simulation): github.com/ika-musume/ikacore_CV1k
