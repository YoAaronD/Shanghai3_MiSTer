# Next cores: Hebereke no Popoon and Blocken (same GA9201 platform)

**What this is:** the implementation plan for adding the two other games that run on Shanghai III's hardware design, written so a new Claude session can start work without the original conversations. Read `docs/HANDOFF.md` first for how the Shanghai III core works; this file only covers what changes.

Facts come from MAME's driver `src/mame/sunelectronics/shangha3.cpp`. A copy is in `docs/mame/shangha3.cpp` (MAME @ab2d1ca); names in parentheses below point into it. Before starting, check whether the driver has changed (`git -C /opt/src/mame log -1 -- src/mame/sunelectronics/shangha3.cpp` after `scripts/build_mame.sh`). Also search GitHub and the MiSTer forum for an existing core for either game; quick web searches on 2026-10-22 found none.

| Set | Year | Maker | PCB | MAME status | Parent |
|---|---|---|---|---|---|
| `shangha3j` (done, v0.1.3, runs on MiSTer) | 1993 | Sunsoft | SUN04C | working | `shangha3` |
| `heberpop` | 1994 | Sunsoft / Atlus | SUN-06 | working | none |
| `blocken` | 1994 | Visco / KID | KID-07 | **imperfect graphics**: zoom incomplete, no rotation | none |

---

## 0. Path of least resistance (summary)

1. **One platform core, one repo.** Keep developing in `Shanghai3_MiSTer`. Add a `game_id` (0 = shangha3j, 1 = heberpop, 2 = blocken), sent by the MRA as a one-byte ROM at `ioctl_index == 1`. Every difference below becomes a `game_id`-selected path. Renaming the repo or core (e.g. to `SunsoftGA9201`) is Aaron's decision. GitHub keeps redirects; `.rbf`/MRA names can change at release.
2. **One download layout for all games** (§3.1). The MRA pads smaller ROMs with FF, so the download writer and SDRAM map stay identical for every game. Draft MRAs with ROM CRCs and DIPs from the driver are in `docs/drafts/`.
3. **heberpop first.** It works in MAME, so every step has a golden reference. The real MAME is buildable in the sandbox (`scripts/build_mame.sh`, about 2 h) and already includes heberpop and blocken.
4. **Order:**
   1. 68000 side boots with sound stubbed.
   2. Graphics match MAME.
   3. Early Quartus build.
   4. Z80 + YM3438 + OKI banking.
   5. Blocken.
   6. Blocken's zoom/rotation research (open-ended; needs a real PCB).
5. **Do the Quartus build early:** as soon as the Z80 and its memory exist, even if sound doesn't work yet. Block RAM (M10K) is the known tight resource (§6).

---

## 1. What carries over unchanged

All three boards have:

- 68000 at 16 MHz (48/3) with IRQ4 at vblank, acknowledged by a write to `…0A`
- the GA9201 blitter, flip at 0x340001, gfxlist at 0x360000
- 64 KB work/graphics RAM at 0x300000, holding the command list, the tilemap and the CPU stack
- RGBx_555 palette, 2048 entries
- the same raster: 8 MHz pixel clock, 512 × 263, visible 384 × 224 on lines 16–239
- OKI M6295 at 1.056 MHz, pin 7 high

These need no change, or only a port tie-off:

- `rtl/shangha3_blitter.sv`: the two-phase snapshot, the queue of starts, and the CPU write arbitration. Set `shadow_en = 0` for both new games (blitter notes: "heberpop definitely doesn't use them, pen 14 is supposed to be solid black (outlines)"). Two small changes are in §4.6.
- `rtl/shangha3_video.sv`, `rtl/shangha3_video_timing.sv`: draw buffer, DDR3 display buffer, palette, shadow LUT, timing.
- `rtl/sdram.sv`, CRT Adjust (`rtl/vendor/crt_adjust.sv`, `rtl/s3_crt_adjust.sv`), pause-on-OSD, DIP handling (ioctl index 254), `sys/`.
- All verification tooling (§7 lists what needs extending).

---

## 2. Differences, item by item

### 2.1 68000 memory map (`*_state::program_map`)

| Address | shangha3j | heberpop | blocken |
|---|---|---|---|
| Program ROM | 000000–07FFFF (2 × 256 KB) | 000000–0FFFFF (2 × 512 KB) | 000000–0FFFFF, only 2 × 128 KB populated, **rest reads FF** |
| Palette | 100000–100FFF | 100000–100FFF | **200000–200FFF** |
| INPUTS | 200000 | 200000 | **100000** |
| SYSTEM | 200002 | 200002 | **100002** (writes ignored) |
| DSW (16-bit, read directly) | — (YM2149 ports A/B) | **200004** | **100004** |
| Blitter go | 200008 | 200008 | 100008 |
| IRQ4 ack | 20000A | 20000A | 10000A (reads ignored) |
| Coin control | 20000C (high byte) | **20000D (low byte)**, bit 3 = OKI bank | **10000D (low byte)**, bits 5:4 = OKI bank |
| Sound latch (write) | — | **20000F** | **10000F** |
| YM2149 1F/2F/3F, protection 4E, OKI 6F | yes | **no** | **no** |
| Work/gfx RAM | 300000–30FFFF | same | same |
| Flip / gfxlist | 340001 / 360000 | same | same |
| Graphics ROM readable by the CPU | no | **800000–B7FFFF** | **800000–B7FFFF** |

Coin control on all three: bit 0/1 coin counters, bit 2 coin lockout (inverted). The core can ignore these, as it does now.

### 2.2 Inputs (`INPUT_PORTS_START( heberpop )`, `( blocken )`)

- **vblank moves into INPUTS** on both new games: bit 7 and bit 15 = vblank, same polarity as shangha3j's SYSTEM bit 7, i.e. `!vblank`. MAME: "vblank?? has to toggle". The game hangs if these don't toggle.
- **INPUTS:** P1 bits 0–5 = R, L, D, U, B1, B2; P2 bits 8–13. Blocken adds **Button 3** on bits 6 / 14.
- **SYSTEM:**
  - bits 0–4: coin1, coin2, service1, start1, start2
  - bit 5: heberpop service switch (`PORT_SERVICE_NO_TOGGLE`); blocken service ("keeping this pressed on boot generates BAD DIPSW")
  - shangha3j's vblank bit 7 isn't used by the new games
- **DSW:** one 16-bit port, SW1 = bits 0–7, SW2 = bits 8–15. In the core: `dsw = {sw[1], sw[0]}` from ioctl index 254, as today.

| Game | MAME DSW default | MRA `<switches default>` | Notes |
|---|---|---|---|
| heberpop | FFFF | `FF FF` | Demo sounds on by default |
| blocken | FFBF | `BF FF` | Demo sounds = bit 6, default **On (0)**; bit 0 is the Service Mode DIP |

The full DIP definitions are already converted into MRA `<dip>` lines in `docs/drafts/*.mra`, generated from the driver.

### 2.3 ROMs (`ROM_START( heberpop )`, `( blocken )`)

**heberpop** (`heberpop.zip`):

| File | CRC32 | Size | Region |
|---|---|---|---|
| `hbp_ic31.ic31` | c430d264 | 512 KB | 68000, even bytes (high) |
| `hbp_ic32.ic32` | bfa555a8 | 512 KB | 68000, odd bytes (low) |
| `hbp_ic34_v1.0.ic34` | 0cf056c6 | 64 KB | Z80 |
| `hbp_ic98_v1.0.ic98` | a599100a | 512 KB | graphics 000000 |
| `hbp_ic99_v1.0.ic99` | fb8bb12f | 512 KB | graphics 080000 |
| `hbp_ic100_v1.0.ic100` | 05a0f765 | 512 KB | graphics 100000 |
| `hbp_ic101_v1.0.ic101` | 151ba025 | 512 KB | graphics 180000 |
| `hbp_ic102_v1.0.ic102` | 2b5e341a | 512 KB | graphics 200000 |
| `hbp_ic103_v1.0.ic103` | efa0e745 | 512 KB | graphics 280000 |
| `hbp_ic104_v1.0.ic104` | bb896bbb | 512 KB | graphics 300000 |
| `hbp_ic53_v1.0.ic53` | a4483aa0 | 512 KB | OKI |

**blocken** (`blocken.zip`):

| File | CRC32 | Size | Region |
|---|---|---|---|
| `ic31j.ic31` | ec8de2a3 | 128 KB | 68000, even bytes |
| `ic32j.ic32` | 79b96240 | 128 KB | 68000, odd bytes |
| `ic34.ic34` | 23e446ff | 64 KB | Z80 |
| `ic98j.ic98` | 35dda273 | 512 KB | graphics 000000 |
| `ic99j.ic99` | ce43762b | 512 KB | graphics 080000 (100000–1FFFFF empty = FF) |
| `ic100j.ic100` | a34786fd | 512 KB | graphics **200000** (280000–37FFFF empty = FF) |
| `ic53.ic53` | 86108c56 | 512 KB | OKI |

Both have a 3.5 MB graphics region (`ROM_REGION16_BE 0x380000, ROMREGION_ERASEFF`), so 28,672 tiles of 128 bytes; shangha3j has 2 MB, 16,384 tiles.

### 2.4 Sound section (`sound_program_map`, `sound_io_map`, `heberpop()` / `blocken()` configs, `init_heberpop`)

Identical on both games:

- **Z80 at 6 MHz** (48/8; MAME marks it "???")
  - Program 0000–F7FF from the 64 KB ROM; RAM F800–FFFF (2 KB).
  - I/O, address masked to 8 bits:
    - 00–03 YM3438 (read = status)
    - 80 OKI (read = status, write = command)
    - C0 sound latch (read)
    - heberpop also writes ports 40/41 (MAME TODO "unknown"): ignore them, but log them in simulation.
  - Interrupts:
    - **INT** = sound latch "data pending" (cleared when the Z80 reads C0). The Z80 runs in **IM 0, and MAME supplies vector FF = `RST 38h`**, so the core must drive FF on the data bus during the interrupt acknowledge cycle (M1 + IORQ).
    - **NMI** = YM3438 IRQ.
- **YM3438 at 8 MHz** (48/6, "8 MHz?").
- **OKI M6295:** same chip and clock as shangha3j, but now **on the Z80 bus** and **banked** (§2.5).
- **MAME mix:** YM3438 outputs 0 and 1 → mono at 0.40 each; OKI at 1.0. No YM2149.

### 2.5 OKI banking (`heberpop_state::coinctrl_w`, `blocken_state::coinctrl_w`, `oki_map`, `init_blocken`)

The bank is written by the **68000** (coin control register), not the Z80.

- **heberpop:** `coinctrl` bit 3 selects which 256 KB half of the 512 KB ROM the OKI sees (`okim6295::set_rom_bank`). OKI address A17..A0 maps to ROM `{bank, A17..A0}`.
- **blocken:** OKI 00000–1FFFF is always ROM 00000–1FFFF. OKI 20000–3FFFF is ROM `bank × 0x20000 + (A & 0x1FFFF)`, with bank = `coinctrl` bits 5:4 (`configure_entries(0, 4, base, 0x20000)`: bank 0 is ROM 00000, bank 1 is 20000, and so on).
- **Phrase table:** the BRAM copy in `shangha3_mem.sv` exists because jt6295 drops commands while a slow table lookup is running. The table is the first 1 KB the OKI sees.
  - heberpop: the table moves with the bank. Keep **two** 1 KB copies (ROM 00000 and 40000) and select one by bank.
  - blocken: the table is in the fixed area, so one copy (ROM 00000) suffices.
  - Bank state at reset: presumably bank 0. Confirm from the game's first coin-control write in a MAME trace (`sound_log.lua` can be extended to tap it).

### 2.6 CPU reads of the graphics ROM (800000–B7FFFF)

New on both games: `map(0x800000, 0xb7ffff).rom().region("blitter", 0)`. The region is `ROM_REGION16_BE`, so a CPU word at byte offset `o` is `(rom[o] << 8) | rom[o+1]`.

The SDRAM stores graphics in file byte order: byte `o` lands in the low byte of SDRAM word `o/2` (`shangha3_mem.sv`, "byte order kept"). **CPU reads must byte-swap.**

Why the game reads it is unknown (decompression, checks, or tables). Measure the access rate in the reference model or MAME before choosing a design. The simplest design: let these reads go through the existing CPU cache (`ch2`) by caching on the SDRAM address instead of the CPU address (§4.3).

### 2.7 Blitter differences

- `shadow_en = 0` (both).
- **Tile-code wrap:** MAME draws tile `code % total_tiles`. With 3.5 MB that is `% 28672`, not a power of two. The core currently uses `e_code[13:0]` (16,384 tiles; `rtl/shangha3_blitter.sv`, `row_addr` / `next_row_addr`).
  - For the new games, compute the code modulo 28,672 (`code ≥ 28672 ? code − 28672 : code`, applied twice to cover all 16 bits) and widen the row address from 18 to 19 bits.
  - Check in a trace whether the games ever use codes ≥ 28,672.
- Command word 5 bit 7 is "unknown (used by blocken)". Ignored by MAME.
- **Blocken zoom and rotation:** MAME's zoom is "definitely wrong for Blocken" (comment in `blitter_go_w`), and rotation (words 0xB/0xC) isn't implemented. MAME is **not a valid reference** for those commands. Plan:
  - Phase 1: match MAME (no rotation), and mark the core imperfect, like MAME does.
  - Phase 2 needs ground truth from a real Blocken PCB. MAME suggests "Game Mode B, start a play" as a test case; photos or video of those screens would be the reference.

### 2.8 Clocks

Same 48 MHz crystal and raster. The core's 96 MHz scheme gives integer enables:

- Z80 6 MHz: ÷16
- YM3438 8 MHz: ÷12
- OKI: the same 11/1000 fractional enable as today

A MAME note says Blocken "is definitely too slow at 8 MHz" (CPU), which is consistent with the 16 MHz 68000.

---

## 3. Proposed design

### 3.1 One download layout and SDRAM map for all games

The MRA stream offset equals the SDRAM byte address, except for the program, which is interleaved into 16-bit words as today.

| Stream / SDRAM offset | Size | Content | Notes |
|---|---|---|---|
| 000000–07FFFF | 512 KB | Program **high** bytes (even EPROM) | shangha3j: 256 KB + 256 KB FF pad; blocken: 128 KB + 384 KB FF |
| 080000–0FFFFF | 512 KB | Program **low** bytes (odd EPROM) | same padding |
| → SDRAM 000000–0FFFFF | 1 MB | Program as big-endian words | written with byte masks, as `shangha3_mem.sv` does now |
| 100000–10FFFF | 64 KB | Z80 program | shangha3j: omit, or 64 KB FF |
| 110000–48FFFF | 3.5 MB | Graphics, file byte order | shangha3j: 2 MB + 1.5 MB FF; blocken: FF holes as in MAME |
| 490000–50FFFF | 512 KB | OKI samples | shangha3j: 256 KB + 256 KB FF |
| index 1 | 1 byte | `game_id` | 0 = shangha3j, 1 = heberpop, 2 = blocken |

- Padding is done in the MRA with `<part repeat="0x…">FF</part>`, so the download writer has no per-game logic. FF padding also reproduces MAME's `ROMREGION_ERASEFF`, which blocken needs: its attract mode reads 080000–0FFFFF, and returning 0 freezes the demo (driver TODO, MAME bug MT00985).
- `docs/drafts/Hebereke no Popoon (Japan).mra` and `docs/drafts/Blocken (Japan).mra` implement this layout. Both parse as XML; neither has run on a MiSTer yet.
- **Shanghai III would need a new MRA in the same layout.** It's the same four files, padded. Do it when `game_id` lands, keeping its CRCs; test that shangha3j still boots in `sim_top.sh` and on the MiSTer.
- The total grows to 5.06 MB. Download time grows accordingly; MiSTer arcade downloads of this size are normal.

### 3.2 `game_id`

- Latch `game_id` from `ioctl_index == 1` (one byte) in `Shanghai3.sv`, and pass it to `shangha3_top` → board/mem.
- Reset the board while downloading, as now.
- In simulation, the testbenches set it with a `--game` option.

---

## 4. File-by-file change list

Line numbers are for v0.1.3.

### 4.1 `rtl/shangha3_board.sv`

- **Decode** (`sel_rom`, `sel_pal`, `sel_io`, …, about lines 200–225):
  - add `game_id`
  - ROM: 512 KB vs 1 MB (`prog_addr` grows to `[19:1]`)
  - palette: 100000 or 200000
  - I/O page: 2000xx or 1000xx
  - `IO_DSW` = …04
  - coin control on the low byte (…0D) for the new games
  - sound latch write at …0F
  - `sel_gfxrom` = 800000–B7FFFF
  - Unmapped program space reads FF; that comes for free from the padded SDRAM image.
- **Read mux** (about lines 515–525):
  - INPUTS for the new games: `{!vblank, in_inputs[14:8], !vblank, in_inputs[6:0]}`, with bits 6/14 = Button 3 for blocken
  - DSW read
  - no YM2149 / protection / OKI on the 68000 side
- **Sound:** keep jt49 + jt6295 for shangha3j. For the new games, a new `ga9201_sound.sv` (Z80, RAM, YM3438, OKI, latch, interrupt logic, mixer). Select the output by `game_id`, or instantiate both and mux. Check the M10K cost (§6).
- `shadow_en` = (`game_id == 0`).
- **Pause:** freeze the Z80, YM3438 and OKI enables too (the same `pause_q` gating as `en_phi*`, `ce_psg`, `ce_oki` now).

### 4.2 `rtl/shangha3_blitter.sv`

- Tile code wrap and the 19-bit `gfx_addr` (§2.7).
- Nothing else for heberpop. Blocken rotation later (§2.7).

### 4.3 `rtl/shangha3_mem.sv`

- **Constants:**
  - `GFX_BASE` 0x110000, `OKI_BASE` 0x490000, `Z80_BASE` 0x100000
  - download accepted below 0x510000
  - the program interleave split moves from 0x40000 to 0x80000
- **CPU cache:** tag on SDRAM word address bits. The program is 1 MB and graphics up to 0x48FFFF, so the tag grows from 7 to about 11 bits; `c_tag` width +4 (still one M10K).
  - The CPU path maps 000000–0FFFFF → SDRAM 000000+ and 800000–B7FFFF → SDRAM 0x110000 + (addr − 0x800000).
  - Byte-swap for graphics reads (§2.6).
- **Graphics port:** row address 19 bits; `GFX_BASE` changes.
- **OKI port:**
  - The address goes through the bank logic (§2.5) before the SDRAM request.
  - Two phrase tables for heberpop.
  - The table fill during download must use the new offsets.
- **Z80 ROM:** either a 64 KB BRAM filled during download (simplest, zero latency, about 64 M10K), or SDRAM through `ch3`, which is idle after the download, with Z80 `WAIT_n`. Decide after the first Quartus M10K count (§6).

### 4.4 `rtl/shangha3_top.sv`, `Shanghai3.sv`

- Plumb `game_id`.
- Inputs: add Button 3 (joystick bit 6 is Start now; reorder `J1` to `Button 1,Button 2,Button 3,Start,Coin,Service` and remap `in_inputs`/`in_system`, keeping shangha3j unchanged). Keep the v0.1.4 SYSTEM bit order (coin1, coin2, service1, start1, start2, service switch) and test every button on hardware.
- The loading bar scales `ioctl_addr` for a 0x2C0000-byte stream; change it to the uniform layout's 0x510000.
- `CONF_STR`: core name (if renamed); "Pause when OSD is open" stays.
- Audio: the new sound section produces 16-bit signed output; mix as today.

### 4.5 `files.qip`, `ext/`, `Shanghai3.sdc`

- **Vendor a Z80.** Verilator can't simulate VHDL, so the choice matters:
  - **tv80** (Verilog, github.com/hutch31/tv80 @66a131c, MIT-style license): simulates in Verilator. `tv80s.v` ties `cen = 1`, so add a small wrapper that brings `cen` out (`tv80_core` has a `cen` input). Recommended for both simulation and synthesis to keep one source of truth.
  - **T80** (VHDL; e.g. `MiSTer-devel/Arcade-Galaga_MiSTer rtl/cpu/T80se.vhd` @7f89f57, with `CLKEN`): the most-used Z80 in MiSTer cores, but not simulable in Verilator without GHDL.
- **Vendor jt12** (github.com/jotego/jt12 @efa4068, GPL-3.0; `hdl/jt12.v`, plus the files `jt12.qip` lists).
  - Its README lists YM2612/YM3438 compatibility.
  - jt12 always applies YM2612-style output limiting ("YM2612 had a limiter... YM3438 did not... JT12 always has a limiter enabled", `hdl/jt12_acc.v`). That's acceptable; note it in the README.
  - Drive `cen` at the chip's input clock (8 MHz enable). Verify against jt12's docs and MAME `-wavwrite` output.
- **SDC:** if the Z80 core is slow at 96 MHz, add a multicycle constraint for its internal paths, as for fx68k (enable every 16 clocks).

### 4.6 Simulation and tools

| File | Change |
|---|---|
| `scripts/romtool.py` | Per-set tables: CRCs from §2.3. Output `prog.bin` (1 MB interleaved), `z80.bin`, `blitter.bin` (3.5 MB, FF-filled), `oki.bin` (512 KB), plus a `stream.bin` in the §3.1 layout for `top_tb` |
| `sim/tb_main.cpp` | `--game N`; ROM buffer sizes (`rom` 0x80000 → 0x100000, `gfx` 0x200000 → 0x380000, `okirom` 0x40000 → 0x80000); serve CPU graphics-ROM reads; serve the OKI through the bank logic once that moves into the board, or keep serving `oki_rom_addr` as today |
| `sim/top_tb.cpp` | Read the stream file (or the MRA order) instead of the hard-coded shangha3j layout; the SDRAM content check uses the §3.1 offsets |
| `sim/refmodel/refmodel.c`, `blitter.c` | Musashi reference: per-game memory map, ROM sizes, DSW port, vblank on INPUTS bits 7/15, latch writes ignored (sound not modelled), graphics-ROM reads, tile-code wrap. Its blit dumps feed `blit_test.sh` |
| `scripts/blit_test.sh`, `sim/blit_tb.cpp` | Graphics buffer size, 19-bit row address |
| `scripts/oki_test.sh`, `sim/oki_bench.sv`, `sim/oki_tb.cpp` | Banking: play phrases from both heberpop halves and all four blocken banks, switching banks between phrases; two phrase tables |
| `scripts/make_test_rom.py`, `check_test_trace.py` | The hand-made test ROM uses shangha3j addresses; add a heberpop/blocken variant if needed |
| `tools/mame/frame_log.lua` | Already game-agnostic: set `S3_GO=100008` for blocken |
| `tools/mame/sound_log.lua` | New: logs 68000 latch writes and every Z80 I/O access. The 68000 tap is tested; the Z80 taps aren't yet |
| `scripts/mame_latency.py` | Unchanged |

---

## 5. Sound section sketch (`ga9201_sound.sv`, new)

```
ports: clk (96 MHz), reset, pause, game_id
       latch_wr, latch_din[7:0]           from the 68000 (…0F, low byte)
       oki_bank[1:0]                      from coinctrl (heberpop bit 3 -> {0,b3}; blocken bits 5:4)
       z80 ROM read port (BRAM or SDRAM), OKI ROM port (to shangha3_mem)
       snd[15:0] signed

z80  : cen = every 16 clocks (6 MHz), frozen by pause
       mem: 0000-F7FF ROM, F800-FFFF RAM (2 KB BRAM)
       io (A7..A0): 00-03 jt12, 80 jt6295, C0 latch read (clears pending), 40/41 ignore
       INT_n = !latch_pending; during INTA (M1 & IORQ) drive data bus = 8'hFF (RST 38h)
       NMI_n = jt12 irq_n
jt12 : cen = every 12 clocks (8 MHz)
oki  : jt6295, cen = existing 1.056 MHz enable; rom_addr -> bank logic -> shangha3_mem OKI port
mix  : snd = sat16( k_fm*(fm_l+fm_r)/2 + k_oki*oki ); start from MAME's 0.40 / 1.0 and
       match a MAME -wavwrite capture of the same scene, then Aaron's ears/PCB
```

Verification:

1. **Unit:** feed the latch sequence captured by `tools/mame/sound_log.lua` into the sound section alone. Compare its Z80 I/O writes with MAME's log (same order and values; timing within a few µs).
2. **Audio:** compare against MAME `-wavwrite` by ear and by spectrogram. Sample-exact FM isn't expected.
3. **OKI:** the banked `oki_test` must be sample-exact, as today.

---

## 6. Block RAM budget (M10K, 553 on the DE10-Nano)

The v0.1.3 build fits, but the exact M10K count wasn't recorded. **First action of the new work:** have Aaron read Compilation Report → Fitter → Resource Section → Resource Usage Summary → "M10K blocks" for v0.1.3, and note it in `docs/HANDOFF.md`.

Estimate for the core alone today: about 270 (draw buffer about 130, work RAM 64, command snapshot 36, tilemap snapshot 16, palette 4, cache 5, CRT Adjust, line buffer, OKI table and others about 15). The MiSTer framework adds roughly 100–150.

| New item | M10K |
|---|---|
| Z80 RAM 2 KB | 2 |
| Z80 ROM 64 KB in BRAM | 64 (or 0 if served from SDRAM) |
| Second OKI phrase table | 1 |
| jt12 | a few |
| Wider cache tag | 0 |

If the total gets tight:

1. Z80 ROM from SDRAM via `ch3`.
2. `MISTER_DISABLE_ADAPTIVE` in the qsf.
3. Shrink `cmdbuf` to 1024 entries.

Never let both frame buffers back into BRAM.

---

## 7. Milestones and acceptance tests

| # | Milestone | Done when | Est. sessions |
|---|---|---|---|
| 0 | Setup | `setup_sandbox.sh` and `build_mame.sh` done; heberpop/blocken ROM CRCs checked; MAME frames + `sound_log` captured for heberpop (and blocken) | 0.5 |
| 1 | `game_id`, uniform layout | shangha3j still passes `sim.sh test`, `blit_test.sh`, `sim_top.sh` (boot frames identical) with the new MRA layout | 0.5–1 |
| 2 | heberpop 68000 side | Boots in `sim.sh game` with the sound latch stubbed; reference model and HDL write traces match from reset (as done for shangha3j) | 1 |
| 3 | heberpop graphics | Frames match MAME at a fixed offset (`mame_latency.py`); `blit_test` passes on heberpop blit dumps; CPU graphics-ROM reads correct | 1 |
| 4 | Quartus checkpoint | Builds with Z80 + RAM + ROM in place (sound may be silent); M10K count and timing recorded; runs on the MiSTer | 0.5 (+ Aaron's build) |
| 5 | heberpop sound | Z80 I/O log matches MAME's `sound_log`; banked `oki_test` sample-exact; audio matches MAME by ear | 1–2 |
| 6 | blocken | Boots, attract mode matches MAME (allowing for MAME's own zoom inaccuracy), 3 buttons, OKI 4 banks | 1 |
| 7 | Release | MRAs for all three games, README, `CHANGELOG`, dated `.rbf`; Aaron's play test | 0.5 |
| 8 | Blocken zoom/rotation (research) | Needs PCB footage; scope separately | open |

Run the regression gate from `CLAUDE.md` after every milestone. Shanghai III must stay pixel-identical to v0.1.3 in `sim.sh game` unless a change is intended.

---

## 8. Risks and unknowns

- **Z80 IM 0 with vector FF:** the interrupt acknowledge cycle must present FF. A wrong vector crashes the sound CPU silently (no sound, game runs). Check in the Z80 I/O log.
- **jt12 timing assumptions** (busy flag, timer IRQ) against the game's real access pattern: compare with `sound_log` timing. This is the same class of bug as jt6295's dropped commands.
- **OKI command spacing** on the Z80 side is unknown; the phrase table stays in BRAM regardless.
- **CPU graphics-ROM reads:** rate and pattern unknown. If heavy, a separate small cache keeps the program cache from thrashing.
- **heberpop debug switches** (driver notes: work RAM `$30878e` bit 0, active low; `$aff14`): if the game ever shows text-stub screens or endless 2-player CPU matches, suspect power-on RAM contents that differ from MAME's. The core's BRAM starts at 0 after FPGA configuration but keeps old contents across a core reset.
- **Blocken graphics:** MAME is imperfect, so frame comparisons will show differences that aren't core bugs. Separate MAME's known zoom issues from real mismatches before chasing them.
- **Pause:** must also freeze the Z80, YM3438 and OKI, or the music keeps playing in the menu.

---

## 9. Decisions for Aaron (ask early, with a recommendation)

1. **Repo/core name** for the platform. Recommended: keep the repo for now and rename the core (`.rbf` and OSD name) at the first multi-game release. The board has no official platform name; MAME calls the chip "GA9201 KA01-0249".
2. **Which PCBs** does he own (heberpop? blocken?) for hardware comparisons, especially blocken zoom/rotation.
3. **Release order:** ship Shanghai III v1.0.0 first (sound balance and CRT Adjust check pending), or wait for the platform release.
