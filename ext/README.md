# Reused open-source cores

Copied in as plain files (not git submodules) so the Quartus project builds
straight from a GitHub zip download. Each folder keeps its own LICENSE.

| Folder | Upstream | Commit | License |
|---|---|---|---|
| `fx68k/` | https://github.com/ijor/fx68k | 0602ee4627b10f301298f2673d826cdd6baa9327 | GPL-3.0 |
| `jt49/` (hdl only) | https://github.com/jotego/jt49 | 6f1247fe0282a70c86ea2b4d8aa901f5332c94db | GPL-3.0 |
| `jt6295/` (hdl only) | https://github.com/jotego/jt6295 | 7d76b0be8cd8f85f3ae741178c9830b20e2071a1 | GPL-3.0 |
| `jt12/` (hdl only, `jt12.vhd` left out) | https://github.com/jotego/jt12 | efa4068a12c9771643fb98bcaaea58c860f5b000 | GPL-3.0 |
| `tv80/` (`rtl/core`: `tv80_core`, `_alu`, `_mcode`, `_reg`, `tv80s`) | https://github.com/hutch31/tv80 | 66a131c38d05ef58b3d8c4f1507a72e6e4aa5d65 | MIT-style (see `tv80/LICENSE`) |

`rtl/tv80_cen.v` is `tv80s.v` with its clock enable brought out to a port (the
Z80 runs at 6 MHz from the 96 MHz clock); `tv80s.v` itself is kept unmodified
for reference and isn't in the build.

Timing assumptions checked against the games:
- **jt12** processes a register write on any clock where `cs_n` and `wr_n` are
  low, so `ga9201_sound.sv` gives it a one-clock strobe per Z80 `OUT`. It always
  applies YM2612-style output limiting (a real YM3438 doesn't). Its outputs are
  16-bit signed.
- **tv80** samples `wait_n` and the data bus on clock-enable edges; the Z80 ROM
  comes from an SDRAM cache, so `ga9201_sound.sv` holds `wait_n` low until the
  byte is there. IM 0 interrupt acknowledges read FF (RST 38h), as on MAME.
  `scripts/snd_z80_test.sh` exercises both.

Not stored here:
- `Musashi/` (reference model only) is cloned by `scripts/build_refmodel.sh`.
- The MiSTer framework (`sys/`, from MiSTer-devel/Template_MiSTer @5dda373) lives at the project root.
