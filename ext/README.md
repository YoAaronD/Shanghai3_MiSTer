# Reused open-source cores

Copied in as plain files (not git submodules) so the Quartus project builds
straight from a GitHub zip download. Each folder keeps its own LICENSE.

| Folder | Upstream | Commit | License |
|---|---|---|---|
| `fx68k/` | https://github.com/ijor/fx68k | 0602ee4627b10f301298f2673d826cdd6baa9327 | GPL-3.0 |
| `jt49/` (hdl only) | https://github.com/jotego/jt49 | 6f1247fe0282a70c86ea2b4d8aa901f5332c94db | GPL-3.0 |
| `jt6295/` (hdl only) | https://github.com/jotego/jt6295 | 7d76b0be8cd8f85f3ae741178c9830b20e2071a1 | GPL-3.0 |

Not stored here:
- `Musashi/` (reference model only) is cloned by `scripts/build_refmodel.sh`.
- The MiSTer framework (`sys/`, from MiSTer-devel/Template_MiSTer @5dda373) lives at the project root.
