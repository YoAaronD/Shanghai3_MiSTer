# Next cores: Hebereke no Popoon and Blocken (same GA9201 platform)

This plan covers adding the other two games that MAME runs with the same driver as Shanghai III (`src/mame/sunelectronics/shangha3.cpp`, copy in `docs/mame/shangha3.cpp`):

| Set | Year | Maker | PCB | MAME status |
|---|---|---|---|---|
| `shangha3j` (done) | 1993 | Sunsoft | SUN04C | working |
| `heberpop` | 1994 | Sunsoft / Atlus | SUN-06 | working |
| `blocken` | 1994 | Visco / KID | KID-07 | **imperfect graphics**: zoom incomplete, rotation missing |

All facts below come from the MAME driver; the names in parentheses are the functions or sections of `docs/mame/shangha3.cpp` to read. If the driver has changed since, re-read it first: `git -C /opt/src/mame log -1 -- src/mame/sunelectronics/shangha3.cpp`. Before starting, also check that nobody has released a MiSTer core for either game in the meantime (search GitHub and the MiSTer forum).

---

## 1. What carries over unchanged

All three boards share the same core hardware:

- 68000 at 16 MHz (48 MHz / 3)
- GA9201 blitter
- 64 KB work/graphics RAM at 0x300000
- RGBx_555 palette (2048 entries)
- the same raster: 8 MHz pixel clock, 512 × 263, visible 384 × 224
- IRQ4 at vblank, acknowledged by a write to `…0a`
- flip at 0x340001, gfxlist at 0x360000
- OKI M6295 at 1.056 MHz

So these files are reused as they are:

- `rtl/shangha3_blitter.sv`
  - the two-phase snapshot design and CPU write arbitration
  - `shadow_en` is already a port: tie it to 0 for these two games (blitter notes: "heberpop definitely doesn't use them, pen 14 is supposed to be solid black")
- `rtl/shangha3_video.sv`, `rtl/shangha3_video_timing.sv`: frame buffers, DDR3 display buffer, palette
- `rtl/sdram.sv` and most of `rtl/shangha3_mem.sv` (download writer, CPU cache, tile-row port, OKI port)
- CRT Adjust, the `Shanghai3.sv` wrapper pattern, DIP handling, MRA pattern
- all verification tooling:
  - `scripts/`
  - `sim/` (board bench, top bench with SDRAM + DDR3 models, blitter replay bench)
  - `sim/refmodel/` (the blitter golden model)
  - MAME itself as reference (`scripts/build_mame.sh`, `tools/mame/frame_log.lua`)

## 2. Differences, item by item

### 2.1 Memory map (`*_state::program_map`)

| Address | shangha3 | heberpop | blocken |
|---|---|---|---|
| Program ROM | 000000–07FFFF (512 KB) | 000000–0FFFFF (1 MB) | 000000–0FFFFF; only 256 KB populated (2 × 128 KB), rest reads FF |
| Palette | 100000–100FFF | 100000–100FFF | **200000–200FFF** |
| INPUTS / SYSTEM | 200000 / 200002 | 200000 / 200002 | **100000 / 100002** |
| DSW (16-bit) | — (via YM2149 ports) | 200004 | 100004 |
| Blitter go | 200008 | 200008 | 100008 |
| IRQ ack | 20000A | 20000A | 10000A (reads ignored) |
| Coin control | 20000C (byte) | **20000D** (byte; bit 3 = OKI bank) | **10000D** (bits 5:4 = OKI bank) |
| Sound latch | — | 20000F (byte) | 10000F (byte) |
| YM2149, protection 20004E, OKI | yes | **no** (on the Z80 side) | **no** |
| Work/gfx RAM | 300000–30FFFF | same | same |
| Graphics ROM readable by the CPU | no | **800000–B7FFFF** | **800000–B7FFFF** |

Plan: one parameter or register (`game_id`) selects the decode.

### 2.2 Inputs (`INPUT_PORTS_START( heberpop )`, `( blocken )`)

- vblank appears on **INPUTS bits 7 and 15** for heberpop and blocken; on shangha3 it was SYSTEM bit 7. MAME comment: "vblank?? has to toggle".
- Blocken has a third button per player (bits 6 / 14).
- SYSTEM bit 5: Service (heberpop: service-mode switch; blocken: "keeping this pressed on boot generates BAD DIPSW").
- DSW is a 16-bit port read directly by the 68000. Defaults and labels are in the driver's DIP definitions, which this plan doesn't list. Take every default from the driver; this was a bug once already (DSW2 on shangha3).

### 2.3 ROM sizes and the SDRAM layout (`ROM_START( heberpop )`, `( blocken )`)

- **heberpop:**
  - program 2 × 512 KB (ic31 even, ic32 odd)
  - audio 64 KB (ic34)
  - graphics 7 × 512 KB = 3.5 MB (ic98–ic104)
  - OKI 512 KB (ic53)
- **blocken:**
  - program 2 × 128 KB (ic31j, ic32j)
  - audio 64 KB (ic34)
  - graphics: ic98j at 0, ic99j at 0x080000, ic100j at **0x200000**
    - 100000–1FFFFF and 280000–37FFFF are empty (filled with FF)
    - the MRA must pad the holes with FF; simplest is an MRA `<part repeat="0x100000">FF</part>`, or a pad in the download writer
  - OKI 512 KB (ic53)
- Graphics ROM = 3.5 MB, so the tile-row address grows from 18 to 19 bits (`gfx_addr` in the blitter, board and mem). The SDRAM layout must grow (total about 5.1 MB, still far inside the 32 MB module).
- CPU cache: the tag gets 1 bit wider (1 MB program space).

### 2.4 CPU reads of the graphics ROM (800000–B7FFFF)

This is new. The 68000 reads graphics ROM directly, probably for decompression or checks. Plan:

- route these reads through the existing CPU cache path, with a second tag space or a separate small cache, into the graphics region of SDRAM
- byte order: the graphics region is `ROM_REGION16_BE`, so CPU word reads see big-endian pairs, while the blitter reads rows little-endian, as in `shangha3_mem.sv`
- check the byte order with the reference model before trusting it

Blocken's attract mode also reads 080000–0FFFFF and expects nonzero data. MAME returns FF there, and returning 0 freezes the demo for some frames (driver TODO at the top of the file, MAME bug MT00985). Return FF for unpopulated program space.

### 2.5 Sound section (`sound_program_map`, `sound_io_map`, machine configs `heberpop()` / `blocken()`)

Both games have:

- **Z80 at 6 MHz** (48/8, "???" in MAME): use T80 (as many MiSTer cores do), with a clock enable every 16 clocks at 96 MHz
  - program ROM 0000–F7FF (from the 64 KB ic34), RAM F800–FFFF (2 KB)
  - I/O (mask FF): 00–03 YM3438, 80 OKI, C0 sound latch read
  - interrupts:
    - latch data pending → Z80 INT, in IM 0 with vector FF, i.e. RST 38h (`init_heberpop`)
    - YM3438 IRQ → Z80 NMI
- **YM3438 at 8 MHz** (48/6, "8 MHz?"): the YM3438 is the CMOS YM2612. Use jt12 (jotego, GPL-3.0), and check whether it has a YM3438 option (the chips differ slightly in output, the "ladder effect"). MAME mixes 0.40 per FM channel vs OKI 1.0.
- **Sound latch:** an 8-bit generic latch; the 68000 writes it at …0F.
- **heberpop:** unknown Z80 writes to ports 40/41 (MAME TODO); ignore them, log in simulation.
- No YM2149 and no protection: remove both for these games.
- Z80 ROM in BRAM costs about 52 M10K. That fits the current budget (core about 270 of 553 M10K). Otherwise use SDRAM with a small cache. Check the Quartus fit early.

### 2.6 OKI banking (`heberpop_state::coinctrl_w`, `blocken_state::coinctrl_w`, `oki_map`, `init_blocken`)

- **heberpop:** `coinctrl` bit 3 selects which 256 KB half of the 512 KB ROM the OKI sees (`set_rom_bank`).
- **blocken:** OKI 00000–1FFFF is fixed (the ROM's first 128 KB); 20000–3FFFF is a window onto one of four 128 KB banks, selected by `coinctrl` bits 5:4 (`configure_entries(0, 4, base, 0x20000)`).
- **Phrase-table copy:** the 1 KB copy in BRAM (`shangha3_mem.sv`) holds the first 1 KB the OKI sees. It exists because jt6295 drops commands during slow table lookups.
  - heberpop: the table moves with the bank, so keep two 1 KB tables (one per half) and select by bank.
  - blocken: the table lies in the fixed region, so one table suffices.
- Re-run `scripts/oki_test.sh` adapted to banking.

### 2.7 Blitter differences

- `shadow_en = 0` for both.
- Command word 5 bit 7 is "unknown (used by blocken)" (command table in the blitter notes).
- **Blocken zoom and rotation:** MAME's zoom is "definitely wrong for Blocken" (blitter code comment) and rotation (words 0xB, 0xC) isn't implemented. MAME is therefore **not a valid reference** for those commands.
  - Phase 1: match MAME (no rotation) and mark the core as imperfect, like MAME does.
  - Phase 2 needs ground truth from a real Blocken PCB: photos or video of screens that use zoom/rotation. MAME's note: Game Mode B, start a play.
  - This is the one open-ended research item; scope it separately.
- Graphics ROM row addresses: 19 bits (see 2.3).

### 2.8 Clocks and timing

Same 48 MHz crystal and same raster. MAME notes "refresh rate is unknown" for all three, and a Blocken PCB note says the game is clearly too slow at 8 MHz (it's 16 MHz). Keep the 96 MHz single-clock scheme; add the Z80 enable (÷16) and the YM3438 enable (÷12 for 8 MHz, then jt12's internal prescaler; check the jt12 docs).

## 3. Recommended structure: one platform core

MiSTer convention for shared hardware is one core per platform, with the game picked by the MRA. Examples: Kyle's Namco NA-1 core, Jotego's CPS cores. Suggested approach:

- the MRA sends a game ID byte (`<rom index="1">` with a `<part>` byte, or the `mod` attribute; read via `ioctl_index == 1`)
- the core sets `game_id` from it, which selects:
  - memory map
  - sound section (YM2149 vs Z80 + YM3438)
  - shadows
  - OKI banking
  - ROM layout
- unused sections are kept, but idle when not selected (block RAM permitting)

**Decision for Aaron:**

- whether to grow `Shanghai3_MiSTer` into a platform repo (renaming it later, e.g. `SunsoftGA9201_MiSTer`; GitHub keeps redirects), or
- whether to start a separate repo per game.

The platform approach shares every fix (the DDR3 frame buffer, blitter, SDRAM) and is what the MiSTer community expects. The board has no official platform name; MAME calls the chip "GA9201 KA01-0249".

## 4. Order of work

1. **Research check** (30 min): re-read the driver, confirm the ROM CRCs against Aaron's dumps (`scripts/romtool.py`), and check for existing cores.
2. **heberpop first:** it works in MAME, so every step has a golden reference. Blocken's open graphics questions come after.
3. Game ID plumbing and the memory-map variants. Boot the 68000 side with the sound CPU stubbed: latch writes go nowhere, and the game shouldn't care at first.
4. 19-bit graphics addressing and the SDRAM layout; CPU reads of graphics ROM. Verify with the MAME frame dumps (`tools/mame/frame_log.lua`) and the blitter replay bench.
5. **Early Quartus build with the Z80 ROM and RAM in place** (block-RAM check). Don't repeat the late-fit lesson.
6. Sound section: T80 + jt12 + latch + interrupts, then OKI banking.
   - Reference: MAME `-wavwrite`, and a Z80 trace from MAME's debugger (`-debug` with `trace`, or a Lua tap on the Z80 I/O space)
   - compare command sequences and audio
7. Blocken: memory map, 3 buttons, OKI 4-bank, FF-padded holes, FF for 080000–0FFFFF reads, then the zoom/rotation research item.
8. MRA per game with the DIP definitions from the driver.

## 5. Known traps (from Shanghai III; read docs/HANDOFF.md §8 and §11)

- Take every default (DIPs, vblank bit position, bank state at reset) from the driver on day one.
- Check reused cores' timing assumptions against the game's real access pattern. jt6295 dropped commands; T80 and jt12 have their own (e.g. jt12 busy flag timing; Z80 IM 0 with vector FF).
- Budget block RAM in M10K blocks (553 total, about 100–150 for the MiSTer framework). Two full-screen BRAM frame buffers didn't fit; the display buffer is in DDR3 now.
- Long simulations: give each run its own output directory; use `pkill -x`, never `pkill -f`.
- The workspace can restart; keep runs under about 20 minutes or make them resumable.
