# Credits

AetherNX is built on other people's work. This page lists where each part comes from and under which license it is used.

## The engine (`dm/`, `scripts/`, `docs/`)

HorizonNative is a fork of **[nxnative](https://github.com/seedds/nxnative)** by **seedds** and its contributors, under the MIT License ([LICENSE](LICENSE)). It began as **[d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile)** (MIT). Third-party code inside the engine (Ryujinx's shader translator, the Vulkan headers, libvpx, dav1d, stb_vorbis, deko3d's texture layout, NVIDIA FLIP and others) keeps its own license: see [dm/third_party/README.md](dm/third_party/README.md).

## AetherNX (`studio/`, `aethernx`, `scripts/aethernx_cli.py`)

The Studio app, the command-line tool and the release packaging are by Alessio Cosi ([iCosiSenpai](https://github.com/iCosiSenpai)), under the MIT License.

Two parts follow **[NX2Apple](https://github.com/LNPANDY/NX2Apple)** by LNPANDY and its contributors (MIT), a launcher for the same engine, rewritten here for AetherNX's one app per game: the install on a device (`scripts/device_install.py`: signing with the player's own team through `xcodebuild -allowProvisioningUpdates`, `devicectl device install app`, the retry under the team's own bundle ID and the retry without a capability the team's profile cannot carry, from its `ShellInstall.swift`), and a library-wide cloud saves folder that a game's own choice overrides (`studio/Sources/CloudSaves.swift`, from its save setup). The page on the Increased Memory Limit ([playing.md](docs/playing.md#the-increased-memory-limit)) summarizes its `ENTITLEMENTS.md`.

## Submodules (`vendor/`)

Related projects are included as Git submodules, not copied: each stays a separate repository with its own history, authors and license, pinned to a fork under [iCosiSenpai](https://github.com/iCosiSenpai) so the pinned commit stays available. The engine and the Studio app do not need them; `./aethernx lift` uses `nxrt`, and the C++ project of `./aethernx decomp-init` uses `nnheaders` and `sead`.

| Folder | Original project | License | What it is |
|---|---|---|---|
| `vendor/nxrt` | [fedebuonco/nxrt](https://github.com/fedebuonco/nxrt) | Unlicense | Runtime and AArch64-to-C static recompiler for Switch games |
| `vendor/SwitchRecomp` | [bgyss/SwitchRecomp](https://github.com/bgyss/SwitchRecomp) | none stated | Static recompilation pipeline and validation skills |
| `vendor/mush8` | [c22dev/mush8](https://github.com/c22dev/mush8) | GPL-3.0 | Rust static recompiler and runtime |
| `vendor/LASRecomp` | [peiikai/LASRecomp](https://github.com/peiikai/LASRecomp) | MIT | Static recompilation of The Legend of Zelda: Link's Awakening |
| `vendor/EoWRecomp` | [Nycolazs/EoWRecomp](https://github.com/Nycolazs/EoWRecomp) | MIT | Static recompilation of The Legend of Zelda: Echoes of Wisdom |
| `vendor/AC-Recomp` | [swaymun/AC-Recomp](https://github.com/swaymun/AC-Recomp) | MIT | Static recompilation of Astral Chain |
| `vendor/smo-recomp` | [Coz-0/smo-recomp](https://github.com/Coz-0/smo-recomp) | GPL-3.0 | Static recompilation of Super Mario Odyssey |
| `vendor/nnheaders` | [open-ead/nnheaders](https://github.com/open-ead/nnheaders) | none stated | Nintendo SDK headers reconstructed by the decompilation community |
| `vendor/sead` | [open-ead/sead](https://github.com/open-ead/sead) | none stated | Nintendo EAD's standard library, reconstructed |
| `vendor/dread-decomp` | [var-flotsam/dread-decomp](https://github.com/var-flotsam/dread-decomp) | MIT | Metroid Dread decompilation and its tools |
| `vendor/NX2Apple` | [LNPANDY/NX2Apple](https://github.com/LNPANDY/NX2Apple) | MIT | Another Mac front end for the engine |
| `vendor/LumaNX` | [Xc1Ym/LumaNX](https://github.com/Xc1Ym/LumaNX) | MIT | Mac and iOS game library front end |
| `vendor/NxLibrary` | [Bium23/NxLibrary](https://github.com/Bium23/NxLibrary) | MIT | Mac library front end |
| `vendor/nx-os` | [tripathishubham1/nx-os](https://github.com/tripathishubham1/nx-os) | MIT | Console-style launcher for the Mac |
| `vendor/game-decompilation-skill` | [lemiur/Game-Decompilation-Skill-For-Claude](https://github.com/lemiur/Game-Decompilation-Skill-For-Claude) | none stated | Matching-decompilation guides: matcher, orchestrator, permuter, code rules |
| `vendor/decomp-skills` | [Ketbome/decomp-skills](https://github.com/Ketbome/decomp-skills) | MIT | Matching-decompilation workflow guide |
| `vendor/decompile-skill` | [coyang/decompile-skill](https://github.com/coyang/decompile-skill) | MIT | Evidence-linked C/C++ reconstruction from binaries |
| `vendor/gba-matching-decomp-skill` | [FacundoMainere/gba-matching-decomp-skill](https://github.com/FacundoMainere/gba-matching-decomp-skill) | MIT | Game Boy Advance matching decompilation pipeline |
| `vendor/ns-game-apple-arm-port` | [realskyrin/ns-game-apple-arm-port](https://github.com/realskyrin/ns-game-apple-arm-port) | MIT | Switch to Apple silicon porting guide |
| `vendor/re-skill` | [vgrichina/re-skill](https://github.com/vgrichina/re-skill) | MIT | Reverse-engineering session guide with Ghidra |
| `vendor/switch-port-to-apple` | [yokeyhh/switch-port-to-apple](https://github.com/yokeyhh/switch-port-to-apple) | MIT | Switch to Apple silicon porting guide |

"None stated" means the original repository has no license file. Such code is not relicensed here: it is only referenced as a submodule, and its use is up to its authors.

The guides under `vendor/` are linked from `.claude/skills/` so coding tools that read that folder find them.

## Other related work

Forks kept under iCosiSenpai for reference, not included here: [OdysseyDecomp](https://github.com/MonsterDruide1/OdysseyDecomp), [botw](https://github.com/zeldaret/botw), [SwitchStaticRecompiler](https://github.com/kahoot-ut/SwitchStaticRecompiler), [switch2mac](https://github.com/azmasm/switch2mac), [nx-native-wrapper](https://github.com/varyform/nx-native-wrapper), [nxnative-gui](https://github.com/jamescastells/nxnative-gui), [MacNativeGames](https://github.com/ly05010419/MacNativeGames), [kartnative](https://github.com/pahorema/kartnative), [nxnative-tv-builder](https://github.com/ltomo2/nxnative-tv-builder).
