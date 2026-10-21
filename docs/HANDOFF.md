# Shanghai III MiSTer core: project handoff and retrospective

**Purpose of this file:** everything a new Claude session needs to continue this project without the original conversation. Give the new session this file **and** the project zip (`shangha3_mister_core.zip`). ROM files are not included; the owner has them.

- **Owner:** Aaron.
  - Owns a real Shanghai III (Japan) PCB. Has no measuring tools beyond basic electrical ones.
  - Works on a Mac. Has a Windows/Linux PC being set up for Quartus.
  - Has a MiSTer.
  - A friend, Kyle (github.com/kyledlester), has built several MiSTer arcade cores with AI assistance. His Nostradamus core (68000 + MAME-as-reference + simulation) was the workflow model for this project.
- **State as of the handoff:** the core is written and simulated end to end, but **not yet compiled in Quartus or run on a MiSTer**.

---

## 1. Status at a glance

| Area | State | Confidence |
|---|---|---|
| 68000 CPU (fx68k), memory map, I/O, IRQ, protection | Done | High: 1.17 M CPU writes identical to the reference model during boot |
| GA9201 blitter (sprites, zoom, tilemaps, shadows, flip) | Done | High: pixel-exact on 587 real blitter runs |
| Frame buffers + palette video out | Done | High: full-board video matches the reference through the title and demo |
| YM2149 (jt49), DIPs through its ports | Done | High |
| OKI M6295 (jt6295) | Done | Medium: plays in the direct-ROM simulation. **The run reading samples from SDRAM was still in progress at handoff.** |
| ROM download to SDRAM, CPU cache, SDRAM controller | Done | Medium-high: simulated with a pin-level SDRAM model. Real SDRAM clock phase is untested. |
| MiSTer wrapper (`Shanghai3.sv`), Quartus project, MRA | Written | **Untested:** never synthesized. Quartus couldn't be installed in the sandbox. |
| CRT Adjust (analog H-Size / H-Pos / V-Shift) | Done | High in simulation: 59-setting bench passes; never synthesized |
| Real hardware | Not yet | — |

**Next action:** Aaron builds in Quartus 17.0.2 Lite (open `Shanghai3.qpf`, Start Compilation) and reports:
1. the first error, or
2. "Total block memory bits" plus any failing timing paths, then tests on the MiSTer.

---

## 2. The original hardware (from MAME `src/mame/sunelectronics/shangha3.cpp`)

- **Games on this board:** Shanghai III (1993, Sunsoft; sets `shangha3`, `shangha3u`, `shangha3up`, `shangha3j`). Same board family: Hebereke no Popoon, and Blocken, which adds a Z80 + YM3438 sound board.
- **Clocks:** 48 MHz crystal.
  - 68000 at 16 MHz (48/3)
  - YM2149 at 1.5 MHz (48/32)
  - OKI M6295 from a 1.056 MHz resonator, pin 7 high (8 kHz)
  - Pixel clock 8 MHz (48/6)
- **Video:** 512 × 263 total, 384 × 224 visible (lines 16–239), 59.41 Hz. MAME notes the refresh rate is unverified, and the sync positions are unknown.
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
| 300000–30FFFF | Work + graphics RAM (64 KB). Holds the blitter command list and tilemap. |
| 340001 | Flip screen (bit 7) |
| 360000 | Blitter command-list address ("gfxlist"; list starts at gfxlist × 16 bytes) |

- **IRQ4** at vblank start, held until acknowledged.
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
- **DIP defaults (MAME):** DSW1 = 0xFF, DSW2 = 0xBF. DSW2 bit 6 = 0 means demo sounds on.
- **ROMs for `shangha3j`, with CRCs:**

| File | CRC | Contents |
|---|---|---|
| `s3j_v11.ic3` | e98ce9c8 | Program, high bytes |
| `s3j_v11.ic2` | 09174620 | Program, low bytes |
| `s3j_char-a1.ic43` | 2dbf9d17 | Graphics, 2 MB |
| `s3j_v10.ic75` | f0cdc86a | OKI samples, 256 KB |

  Aaron's copies match these CRCs.

---

## 3. Core architecture (what's in the zip)

All logic runs on one **96 MHz** clock (2 × 48 MHz) with clock enables.

| File | Role |
|---|---|
| `rtl/shangha3_board.sv` | The PCB: fx68k, address decode, work RAM (dual port), palette RAM (dual port), I/O, protection, IRQ, jt49, jt6295 + mixer, CPU write arbitration against the blitter |
| `rtl/shangha3_blitter.sv` | GA9201 re-creation (two-phase, see below) |
| `rtl/shangha3_video.sv` | Draw buffer + display buffer (each 384 × 224 × 12 bit), vblank copy, palette scan-out |
| `rtl/shangha3_video_timing.sv` | Counters, blanking, placeholder syncs |
| `rtl/shangha3_mem.sv` | ROM download writer, 68000 program cache, graphics-row port, OKI byte port |
| `rtl/sdram.sv` | Sorgelig's 4-channel SDRAM controller (GPL-3.0, from MiSTer-devel/Arcade-IremM92_MiSTer @68a4683), with Verilator-only port splitting |
| `rtl/shangha3_top.sv` | Board + memory + SDRAM; shared by the MiSTer wrapper and the end-to-end simulation |
| `Shanghai3.sv` | MiSTer `emu` module: hps_io menu, PLL (96 MHz), DIPs (ioctl index 254), joystick mapping, arcade_video, audio |
| `rtl/pll*`, `sys/` | From MiSTer-devel/Template_MiSTer @5dda373. PLL output hand-edited from 20 to 96 MHz. |
| `Shanghai3.qpf/.qsf/.sdc`, `files.qip` | Quartus project. The SDC sets a 3-cycle multicycle path for fx68k-internal paths. |
| `releases/Shanghai III (Japan).mra` | ROM stream (4 files in order, no interleave) + DIP definitions |
| `microrom.mem`, `nanorom.mem` | fx68k microcode. Quartus loads these from the project folder. |
| `rtl/vendor/crt_adjust.sv`, `rtl/s3_crt_adjust.sv` | CRT Adjust: rmonic79's module (unmodified, @c682de9) plus glue adapted from Kyle's Nostradamus core. Sits in front of `arcade_video`. OSD bits 96, 101–108, 112–116. The H-Position clamp table depends on HS_START (416, a placeholder). Bench: `scripts/crt_test.sh`. |

**Key design points:**

- **CPU timing:** fx68k's phase enables pulse every 3rd clock, giving 16 MHz. Bus timing is cycle-exact. DTACK counts from AS, not DS, so writes get no extra wait state (bug found and fixed).
- **Blitter, two phases:**
  1. **Snapshot:** walk the list in RAM, reading words 6, 7, 10, 13 first and skipping disabled commands. Valid commands (11 words) go into an internal buffer (2048 × 176 bit). If any command is a tilemap, the 8K-word tilemap area is copied too. This takes about 1% of a frame.
  2. **Draw:** a shared scaled-tile engine (MAME-equivalent 16.16 stepping) with a one-row ROM cache plus a prefetch of the next row. Shadows are a read-modify-write of the frame buffer.

  The worst case is about 16.8% of a frame.
- **CPU write arbitration:** a CPU write waits only if it targets RAM the snapshot hasn't copied yet (`scan_from`, `tm_from`). This reproduces MAME's instantaneous blitter with about 0.01% CPU loss. Holding the CPU for the whole draw halved the game's frame rate, because the stack lives inside the list and tilemap ranges.
- **Frame buffers:** the draw buffer is copied to the display buffer at vblank start (86,016 clocks = 0.9 ms of the 2.5 ms vblank). Drawing, but not snapshotting, waits during the copy. This gives tear-free output with MAME's frame latency. The real PCB method is unknown.
- **SDRAM layout (bytes):**
  - 000000 program (big-endian words)
  - 080000 graphics (file byte order, little-endian words)
  - 280000 OKI samples

  The download stream is ic3 → ic2 → gfx → oki. The core interleaves the program bytes with byte-masked writes.
- **SDRAM channels** (priority order): ch2 = CPU cache line (64-bit), ch1 = OKI, ch3 = download writes, ch4 = blitter rows (64-bit).
- **CPU cache:** direct-mapped, 512 lines × 4 words.
- **Audio:**
  - The YM2149 is high-passed (DC removal), then mixed: `snd = oki × 2 + ay × 12`, saturated to 16-bit signed. These levels are a guess.
  - jt6295 uses `INTERPOL=0` and ss = 1. Its 1.056 MHz enable comes from a 96 MHz × 11/1000 accumulator.
- **Inputs:** MiSTer joystick bits 0–3 directions, 4 = B1, 5 = B2, 6 = Start, 7 = Coin, 8 = Service. The OSD has a "Service Mode" toggle (status[6]).
- **Estimated block RAM:** about 3.1 Mbit of 5.6 Mbit before the MiSTer framework. This is the biggest fit risk; the fallback is moving the display buffer to DDR.

---

## 4. Verification setup (all in `sim/` and `scripts/`)

| Tool | What it does | Typical speed |
|---|---|---|
| `scripts/sim.sh test` | 68000 boots a hand-assembled test ROM; 13 automated checks | ~15 s |
| `scripts/sim.sh game N [opts]` | Full board on the real program ROM (ROMs served directly). Bus trace, `--frames-out`, `--wav` | ~1.25 s per frame |
| `scripts/sim_top.sh ROMDIR N [opts]` | **End to end:** emulated MiSTer download → pin-level SDRAM model → boot from SDRAM. `--check-sdram` | ~1.3–2 s per frame |
| `scripts/blit_test.sh EVERY MAX [--dump-filter zoom\|tilemap]` | Replays real blitter runs (RAM + frame-buffer snapshots from the reference model) through the HDL blitter; must be pixel-exact | Seconds |
| `sim/refmodel/refmodel` (`scripts/build_refmodel.sh`) | Musashi 68000 + MAME memory map + software blitter. Traces, PPM frames, snapshot dumps | ~250× faster than HDL |
| `scripts/compare_traces.py`, `compare_frames.py` | Write-order comparison; frame matching within ±N frames | — |
| `scripts/romtool.py extract` | Checks ROM CRCs and builds `sim/roms/prog.bin`, `blitter.bin`, `oki.bin` | — |

**Results:**
- Boot writes: 1.17 M identical to the reference.
- Blitter: 517 + 40 zoom + 30 tilemap runs pixel-exact. A deliberately broken shadow makes 25 of 52 fail, so the test catches errors.
- Full board, 1800 frames: every frame up to 1110 is identical to a reference frame (time-shifted). Later frames show the same screens at different moments; the demo shuffle depends on timing.
- SDRAM path: all 2,883,584 bytes correct, and 400 boot frames match.
- The HDL runs the title at 60 fps. The Musashi reference drops frames, because it isn't cycle-exact. The real PCB looks smooth, which matches the HDL.

**Pending at handoff:** (the first attempt was killed by a workspace restart) the 1750-frame `sim_top.sh` run with `-DOKI_PROBE`, which confirms OKI samples are read from SDRAM and produce non-zero output during the demo (from about frame 1550). To re-run it:

```
VFLAGS="--public-flat-rw -CFLAGS -DOKI_PROBE" scripts/sim_top.sh <romdir> 1750 --wav sim/top_audio.wav
```

---

## 5. Decisions and why

1. **Re-implementation, not a port:** MAME is used as a behavioral reference only. No MAME code is in the core (license and cleanliness).
2. **Reuse proven parts:** fx68k, jt49, jt6295, the MiSTer Template, and Sorgelig's SDRAM controller. Custom work is limited to the board glue, blitter, video and memory hub.
3. **A software golden model before the HDL blitter:** this gave the first pictures in one session and made pixel-exact unit tests possible.
4. **96 MHz single clock:** integer enables for the CPU (÷6), pixel (÷12) and PSG (÷64); OKI uses a fractional accumulator. The cost is an SDC multicycle constraint for fx68k (about 40 MHz single-cycle Fmax).
5. **Two-phase snapshot blitter:** the only design found that both matches MAME's instant semantics and leaves the CPU free. The game runs at its CPU limit.
6. **Byte-masked download interleave:** avoids depending on MRA `<interleave map>` byte-order semantics.
7. **A program cache in front of the SDRAM:** the 68000 needs ROM data within about 10 clocks to avoid wait states, and SDRAM latency is about 11 or more.

---

## 6. Bugs found along the way (worth knowing)

- **DTACK waited for UDS/LDS:** the 68000 asserts these late on writes, which added a wait state to every write (about 2.4% slow).
- **Frame-buffer row offset computed in 16 bits:** 223 × 384 overflows.
- **Flipped sprite strips:** later tiles kept the negated step.
- **RAM write strobe fired at cycle start:** holding DTACK didn't delay the write itself.
- **CPU cache:** the tag read is stale for 2 clocks after a fill, which caused a duplicate fill. Fixed with a guard.
- **Simulation-model bug:** the SDRAM model returned data one cycle early. The design was right.
- **DSW2 default was 0xFF:** demo sounds were off. MAME's default is 0xBF.
- **Verilator quirk:** an in-block initializer in `sdram.sv` (`reg state = ...`) was moved to module scope so it isn't re-run every clock.

---

## 7. Sandbox and environment notes (if the new session also runs in a cloud sandbox)

- **Blocked:**
  - apt mirrors (archive.ubuntu.com)
  - raw.githubusercontent.com
  - Intel download sites (no Quartus)
  - PyPI was intermittent (py7zr and capstone failed)
- **Worked:**
  - git over HTTPS to github.com, including a sparse checkout of MAME
  - curl to github.com release assets
  - npm was flaky
- **Tools built from source:**
  - flex 2.6.4 (GitHub release)
  - Verilator **5.030**: `autoconf && ./configure && make -j2`, about 15 minutes. `make install` needs a `help2man` stub script.
  - A Musashi-based disassembler (`/opt/tools/dis68k`)
- **fx68k under Verilator 5:** needs `-Wno-BLKANDNBLK` and related waivers (see `scripts/sim.sh`). It loads `microrom.mem` from the working directory, so the scripts `cd ext/fx68k`.
- **Process management:** `pkill -f <pattern>` kills the calling shell if the pattern appears in its own command line. Use `pkill -x Vshangha3_board`, and give every long run its own output directory.
- **Resources:** 2 CPU cores. Long full-board runs take 40–60 minutes. Simulation stdout from `nohup` is buffered until exit.

---

## 8. Open items and risks (priority order)

1. **First Quartus build:** block-RAM fit, M10K inference of the buffers (written in the standard pattern on purpose), and timing at 96 MHz (fx68k multicycle constraint, blitter, SDRAM).
2. **SDRAM on real hardware:** CAS latency 3, SDRAM_CLK through an inverted DDR output (as in M92). If ROM data is corrupt on real hardware, suspect clock phase.
3. **Confirm OKI-from-SDRAM** (the pending simulation), then tune the mix levels by ear against MAME or the PCB.
4. **Video:** sync positions are guesses (HS at 416–447, VS on lines 244–246). Check centering on CRT and HDMI. The refresh rate is unverified (59.41 Hz assumed).
5. **CPU cache miss cost:** about 1.6% slower during the boot ROM checksum. Watch for slowdown in gameplay, where the game is at its CPU limit.
6. **Unknowns that need the PCB** (logic analyzer about $15–30, EPROM programmer about $50–70):
   - real blitter speed and CPU/blitter arbitration
   - frame buffering
   - refresh rate
7. **Later:** Hebereke no Popoon and Blocken. These need a Z80 + YM3438 sound board, OKI banking, no shadows (`shadow_en = 0`), a different memory map, and for Blocken, rotation/zoom work.

---

## 9. Retrospective: what could have been better, easier or faster

### What worked well (keep doing)
- **A fast software reference model** (Musashi + MAME memory map + software blitter). It produced the first pictures early, ran 250× faster than the HDL, and made pixel-exact blitter unit tests possible.
- **Snapshot-based unit tests:** dumping real blitter runs (RAM + frame buffer before/after) and replaying them through the HDL. Each iteration took seconds instead of a 40-minute full-board run, and a deliberate sabotage test showed the test was meaningful.
- **Measuring before redesigning,** once we started: stall counters, a per-frame PC sample, and the disassembler turned two wrong theories into a correct root cause (the stack inside the list region).
- **Reusing proven cores** (fx68k, jt49, jt6295, Sorgelig's SDRAM controller, the MiSTer Template).

### What cost the most time, and what to do instead
1. **No version control.** The project lived in a folder and was re-zipped each time; there was no history, diffs or easy rollback (blitter versions were saved by hand to `/tmp`).
   *Do instead:* `git init` on day one, commit at every verified milestone, and push to a private GitHub repo Aaron owns. That also gives Kyle and other collaborators access.
2. **Slow full-board simulations dominated the wall-clock time:** about 1.25–2 s per frame, with interesting events at frames 700–1800, so 40–60 minutes per answer.
   *Do instead:*
   - Use **Verilator `--savable` checkpoints** (save after the 12 s self-test and restore for each experiment).
   - Run the reference model first to find the exact frames of interest.
   - Prefer unit-level replays (like the blitter snapshots) for any new block.
   - Consider skipping the self-test by patching the RAM test loop in a simulation-only ROM copy.
3. **Fixing before diagnosing.** The boot garbage led to "stall the CPU for the whole blit" (halved the frame rate). Then the stall was narrowed (still lagged), then tilemap guards (still lagged), and only then the snapshot design. Each step cost a 40-minute run.
   *Do instead:* when a real-time HDL block replaces an instantaneous MAME model, start from **MAME's semantics** ("atomic at the go write") and design for that (snapshot or copy-on-write) from the beginning. When a problem appears, add instrumentation first (stall counters, CPU PC, write logs) and form a hypothesis from data.
4. **Process hygiene:** two simulations wrote to the same trace file (a `pkill -f` pattern killed the shell instead of the process). The trace was corrupted, and a run had to be redone.
   *Do instead:* use a unique output directory per run, `pkill -x` by exact name, and a small run wrapper that refuses to start if one is active.
5. **The reference model isn't cycle-exact.** Musashi's instruction timing differs slightly from a real 68000, which made frame-rate comparisons ambiguous (the HDL ran 60 fps where Musashi dropped frames).
   *Do instead:* use **MAME itself** as the timing reference. Aaron can run `mame shangha3j -debug` with `trace` and `-aviwrite`/snapshots on his own machine. Building MAME in a 2-core sandbox isn't practical.
6. **Checking MAME defaults up front:** the DIP default (demo sounds off) was only discovered at the audio stage.
   *Do instead:* derive every default (DIPs, input polarity, clocks) from the driver into a checklist at the start.
7. **Environment discovery happened piecemeal** (apt blocked, PyPI flaky, raw GitHub blocked, Intel blocked).
   *Do instead:* probe all needed hosts in the first minutes. Ask the admin to allowlist `archive.ubuntu.com`, `raw.githubusercontent.com` and Intel's download hosts, which would also allow building in Quartus in the cloud. Or install Verilator and Quartus on Aaron's PC and run the heavy parts there.
8. **Simulation models need the same care as the design:** the SDRAM model's off-by-one cost a debug cycle.
   *Do instead:* derive the model's latency from the controller's documented expectations (and its real-hardware track record) before writing it.
9. **Lint consistently with `-Wall`:** width bugs (frame-buffer row overflow, 38-bit multiplier operands) were caught by review, not tools. A strict lint on every file at every change catches these immediately.
10. **Synthesis feedback came late:** the design reached "complete" without a single Quartus run, so BRAM inference, fit and timing are still open.
    *Do instead:* do a first Quartus build of a skeleton (CPU + RAM + video) early, then build incrementally.
11. **Communication:** long silent waits during simulations led Aaron to ask whether anything was needed.
    *Do instead:* post a short status with an ETA when starting any run over 10 minutes, and say up front which decisions need Aaron.

### Suggested workflow for the next phase
1. Put the project in git and push to a private repo.
2. Aaron: first Quartus build, then send errors or the fit and timing summary.
3. Fix synthesis issues. Each fix gets a quick re-run of `blit_test.sh` and `sim.sh test`.
4. MiSTer test: boot → title → demo. Check controls, DIPs, audio levels and centering.
5. Only then: polish (audio mix, sync), and next games on the board family.

---

## 10. References

- MAME driver: `src/mame/sunelectronics/shangha3.cpp` (copy in `docs/mame/`, MAME @ab2d1ca)
- fx68k: github.com/ijor/fx68k @0602ee4
- jt49: github.com/jotego/jt49 @6f1247f
- jt6295: github.com/jotego/jt6295 @7d76b0b
- MiSTer Template: github.com/MiSTer-devel/Template_MiSTer @5dda373
- SDRAM controller: github.com/MiSTer-devel/Arcade-IremM92_MiSTer `rtl/sdram.sv` @68a4683
- MRA syntax reference: MiSTer-devel/Arcade-IremM72_MiSTer `releases/*.mra`
- Musashi (reference model only): github.com/kstenerud/Musashi @313ebf1
- Workflow inspiration and CRT Adjust glue: github.com/kyledlester (Nostradamus_Magical_Cat_Adventure_MiSTer)
- CRT Adjust: github.com/rmonic79/MiSTer-CRT-Adjust @c682de9
