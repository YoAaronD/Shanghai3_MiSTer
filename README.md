# SunsoftGA9201 for MiSTer: Shanghai III, Hebereke no Popoon, Blocken

![Shanghai III running on the core: title screen and a game in progress](docs/images/hdl_video_output_2x.png)

A MiSTer FPGA core for Sunsoft's GA9201 arcade board family, named after the boards' custom graphics chip. Until v1.0.0 it was the Shanghai3 core. It re-creates the original boards in hardware logic and runs three games:

- **Shanghai III** (Sunsoft, 1993), the arcade mahjong-solitaire game: 68000, GA9201 graphics blitter, YM2149 music chip, OKI M6295 sample chip.
- **Hebereke no Popoon** (Sunsoft, 1994), a falling-block puzzle game: the same 68000 and blitter, plus a Z80 sound CPU with a YM3438 FM chip and a bank-switched OKI M6295.
- **Blocken** (KID / Visco, 1994), a puzzle game on the same hardware as Hebereke no Popoon.

Shanghai III was checked against MAME and against an original Shanghai III PCB: boot, picture, gameplay and sound balance. Hebereke no Popoon and Blocken were checked against MAME (no PCB yet). The core was created with the assistance of AI tooling.

**Status:** Shanghai III is released (v1.0.0), tested on a DE10-Nano with a CRT (15 kHz analog) and with HDMI. Hebereke no Popoon and Blocken are in development: Hebereke no Popoon runs in simulation and matches MAME; neither has run on hardware yet.

## Supported sets

| Game | MAME set | MRA | ROM zips |
| --- | --- | --- | --- |
| Shanghai III (Japan) | `shangha3j` | `Shanghai III (Japan).mra` | `shangha3j.zip`, plus its parent `shangha3.zip` if your set is split |
| Hebereke no Popoon (Japan) | `heberpop` | `Hebereke no Popoon (Japan).mra` | `heberpop.zip` |
| Blocken (Japan) | `blocken` | `Blocken (Japan).mra` | `blocken.zip` |

ROMs are not included. Use MAME 0.289 sets (`mame -verifyroms shangha3j heberpop blocken`). For Shanghai III, split, non-merged and merged sets all work: the MRA looks in `shangha3j.zip` first, then `shangha3.zip`.

The other Shanghai III sets (`shangha3`, `shangha3u`, `shangha3up`) use different program ROMs and haven't been tested.

All three games run on one core file. Each MRA tells the core which game it is, so always start the games from their MRAs.

## Installation

1. Copy `releases/SunsoftGA9201_YYYYMMDD.rbf` to `/media/fat/_Arcade/cores/`. If you're updating, remove any older `SunsoftGA9201_*.rbf` from there, and any `Shanghai3_*.rbf` (the core's name before v1.1.0).
2. Copy the `.mra` files from `releases/` to `/media/fat/_Arcade/`.
3. Copy the ROM zip(s) to `/media/fat/games/mame/`.
4. Start the game from the **Arcade** menu.

The release zip on the GitHub Releases page is laid out like the SD card. You can copy its `_Arcade` folder onto the root of the SD card instead of steps 1 and 2.

Requires an SDRAM module: the games' ROMs are kept in SDRAM. Any size works.

**Updating from v1.0.0 (the Shanghai3 core):** replace the Shanghai III MRA with the new one too: the core now loads every game in one common layout, and the v1.0.0 MRA doesn't match it. The core's new name also means MiSTer starts with fresh settings for it: set your OSD options and button mapping again (the button list gained Button 3).

## What to expect

### Shanghai III

- **The game tests itself for about 12 seconds after loading**, as the arcade board does: a black screen, then "ROM 1 CHECK OK", "ROM 2 CHECK OK", "VIEW WORK CHECK OK", "COLOR RAM CHECK" and "ADPCM CHECK OK".
- The **green stripes during COLOR RAM CHECK** are correct. The real board shows them too, because it changes colors mid-frame. (MAME shows solid flashes there.)
- The attract mode is silent; the music starts in the demo game. The core turns Demo Sounds On by default; a stock arcade board, with all its DIP switches off, plays the demo silently. Set Demo Sounds to Off in the DIP switches for that.
- **The title screen, mode select and layout wheel run at 30 updates per second, as on the arcade board** (gameplay runs at 60). The real board's graphics chip is slow enough that those busy screens miss every other frame, and the core reproduces that, so menu timeouts and the title's scrolling text match the original.

### Hebereke no Popoon

- **The game tests itself for about 25 seconds after loading**: ROM 1 and 2, VIEW WORK, COLOR RAM and CG ROM 1–4 checks. The coloured bands during COLOR RAM CHECK come from the same mid-frame colour changes as on Shanghai III.
- The game runs at MAME's speed. The Shanghai III board's graphics chip slows its busiest screens down to 30 updates per second; this core reproduces that for Shanghai III, where it was measured on a PCB, but not for Hebereke no Popoon until it can be checked on that game's board.

### Blocken

- MAME marks Blocken's graphics as imperfect: some zoomed graphics are drawn wrongly, and the graphics chip's rotation isn't emulated. MAME is the only reference available, so the core draws Blocken as MAME does, including those faults.

## Controls

| Game | MiSTer default (pad) |
| --- | --- |
| Joystick | D-pad / stick |
| Button 1 | A |
| Button 2 | B |
| Button 3 (Blocken only) | X |
| Start | Start |
| Coin | Select |
| Service (adds a credit) | R |

Two players are supported (second controller).

## OSD options

- **Aspect ratio:** Original (4:3), Full Screen, or the custom ratios set in MiSTer.ini.
- **Scandoubler Fx:** None, HQ2x, CRT 25 / 50 / 75 %.
- **OKI (drums/FX):** the balance between the board's two sound chips; see [Sound](#sound) below.
  - **PCB** (default) is the balance measured against a real Shanghai III board. For Hebereke no Popoon and Blocken it is MAME's balance (no PCB recording yet).
  - **OKI+ / OKI++** bring the drums and effects forward by 3 / 6 dB; **OKI− / OKI−−** make them 3 / 6 dB less pronounced.
  - The setting cycles PCB → OKI+ → OKI++ → OKI−− → OKI− → PCB.
- **Orientation:** Horizontal, Vertical CW, Vertical CCW. The vertical settings rotate the HDMI picture through the MiSTer scaler, for vertical (TATE) monitors. The analog/CRT output is never rotated.
- **CRT Adjust** (page): picture geometry for analog CRTs, by rmonic79.
  - Turn it **On**, then set:
    - **H-Size** in 1 % steps, from −12 to +10 %
    - **H-Position** in 6-pixel steps
    - **V-Shift** in 1-line steps
  - Sync is never moved, so the CRT stays locked while you adjust.
  - It needs Scandoubler Fx = None. While it's On, HDMI follows the adjustment too; with it Off, the video passes through untouched.
- **DIP Switches:** see below. Press Reset after changing them: the game reads some of them (Flip Screen, for one) only during its self-test.
- **Service Mode:** the board's test switch, for the game's service menu.
- **Pause when OSD is open:** On by default. Opening the menu freezes the game and silences it; closing the menu resumes exactly where it stopped.
- **Reset**, **Reset and close OSD**.

## Sound

Each arcade board makes its sound with two chips, mixed together on the board. The core re-creates them.

**Hebereke no Popoon and Blocken** use a Yamaha **YM3438** FM synthesis chip for the music, driven by its own Z80 processor, and the same OKI M6295 for drums, voices and effects, with more samples than the chip can address at once (the main processor switches banks). The core's FM chip is jotego's jt12, a YM2612/YM3438 re-creation. Their balance and level match MAME's output (measured: within 0.3 dB in loudness).

The rest of this section is about Shanghai III.

**YM2149: the music.** A Yamaha sound chip (a close relative of General Instrument's AY-3-8910) that generates simple tones: three square-wave voices plus noise. In Shanghai III it plays the melody, the harmony and the bass line.

**OKI M6295: drums and sound effects.** "OKI" is Oki Electric, the Japanese company that made the MSM6295. Instead of generating tones, it plays back short recorded sounds stored in a ROM on the board (ADPCM, a compressed digital audio format), up to four at a time. It was common in early-'90s arcade games for voices, drums and effects. In Shanghai III it plays:

- the music's drums, including the deep kick-drum thump that gives the music most of its low end;
- the sound effects: picking a tile, the special sound when a pair of season or flower tiles is removed, the jingles.

**The balance option.** The relative volume of the two chips was measured from a recording of a real board, and that's the **PCB** setting. If you'd like the drums and effects more prominent (OKI+, OKI++) or more in the background (OKI−, OKI−−), each step moves them 3 dB against the music. The music moves the opposite way by half as much, so the overall loudness stays about the same. For overall volume, use MiSTer's own volume control.

## DIP switches

The MRA sets each game's switches; the defaults below are MAME's. Hebereke no Popoon and Blocken's switches are in the OSD under DIP Switches, with MAME's names (Hebereke no Popoon has several "Unknown" switches; leave them Off).

### Shanghai III

| Switch | Settings (default in bold) |
| --- | --- |
| Coin A, Coin B | **1C/1C**, 2C/1C, 3C/1C, 4C/1C, 5C/1C, 1C/2C, 1C/3C, 1C/4C |
| Difficulty | Easy, **Normal**, Hard, Hardest |
| Base Time | 70, **80**, 90, 100 sec |
| Additional Time | 4, **5**, 6, 7 sec |
| Demo Sounds | Off, **On** |
| Flip Screen | **Off**, On |

### Hebereke no Popoon

| Switch | Settings (default in bold) |
| --- | --- |
| Difficulty | Very Easy, Easy, **Normal**, Hard |
| Allow Diagonal Moves | No, **Yes** |
| Demo Sounds | Off, **On** |
| Coin A, Coin B | **1C/1C**, 2C/1C, 3C/1C, 4C/1C, 5C/1C, 1C/2C, 1C/3C, 1C/4C |
| Unknown (SW1:3, 4, 7, 8; SW2:7, 8) | **Off**, On |

### Blocken

| Switch | Settings (default in bold) |
| --- | --- |
| Service Mode | **Off**, On |
| Difficulty | Easy, **Normal**, Hard, Very Hard |
| Game Type | **A**, B |
| Players (MAME's name; probably lives) | **1**, 2, 3, 4 |
| Demo Sounds | Off, **On** |
| Flip Screen | **Off**, On |
| Coin A, Coin B | **1C/1C** and 15 other settings, including Free Play (Coin A) |

## Building from source

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): Quartus build, simulations, the MAME comparison tools, and how the core was verified. What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

## Credits

- **YoAaronD:** the core.
- **Kyle Lester** (kyledlester): hardware testing; the CRT Adjust glue and the rotation approach come from his Nostradamus core.
- **Umberto Parisi** (rmonic79): CRT Adjust.
- **Jorge Cwik**: fx68k, the 68000 CPU core.
- **Jose Tejada** (jotego): jt49 (YM2149), jt6295 (OKI M6295) and jt12 (YM3438).
- **Guy Hutchison**: tv80, the Z80 CPU core (based on Daniel Wallner's T80).
- **Sorgelig** and the MiSTer contributors: the MiSTer framework and the SDRAM controller.
- **The MAME team:** the `shangha3.cpp` driver by Nicola Salmoria (Shanghai III, Hebereke no Popoon, Blocken), used as a behavioral reference. No MAME code is in the core.
- **Raki** (ika-musume): the pause-when-OSD-is-open idea, from the CV1000 core.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE). Third-party parts keep their own licenses, listed in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#licenses).
