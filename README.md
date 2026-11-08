<div align="center">

<img src="./assets/aethernx-logo.png" width="175" alt="AetherNX Studio Logo" />

# ⚡ AETHERNX (`switch-comp`)

### **The Universal Nintendo Switch Decompilation (`DECOMP`), Static Recompilation (`RECOMP`) & Native Apple Silicon Porting (`COMP`) Suite**

*Turn Nintendo Switch packages (**Base Game + Title Updates + Multiple DLCs**) into native **macOS `.app`** bundles, **iOS / iPadOS `.ipa`** packages, statically recompiled **C11 / C++20 / Rust** translation units, and byte-matching **C++20 clean-room decompilation** workspaces.*

[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20iPadOS%20%7C%20tvOS-000000?style=for-the-badge&logo=apple&logoColor=white)](#-tri-pipeline-architecture)
[![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20(ARM64)-0A84FF?style=for-the-badge&logo=arm&logoColor=white)](#-tri-pipeline-architecture)
[![Graphics](https://img.shields.io/badge/GPU-Metal%20%2F%20NVN%20%2F%20SPIR--V-30D158?style=for-the-badge)](#-tri-pipeline-architecture)
[![Pipelines](https://img.shields.io/badge/Pipelines-COMP%20%E2%80%A2%20RECOMP%20%E2%80%A2%20DECOMP-5E5CE6?style=for-the-badge)](#-tri-pipeline-architecture)
[![Unified Repos](https://img.shields.io/badge/Unified%20Repos-31%20Forked%20Projects-FF9F0A?style=for-the-badge)](#complete-31-repository-copyright--attribution-registry)
[![AI Skills](https://img.shields.io/badge/AI%20Skills-15%20Agent%20Skills-BF5AF2?style=for-the-badge)](#-integrated-ai-agent-skills-15-skills)
[![License](https://img.shields.io/badge/License-MIT%20%2B%20Third--Party-32D74B?style=for-the-badge)](./LICENSE)

[**Overview**](#-overview) •
[**Prerequisites: Keys, Firmware & Game Versions**](#-prerequisites--best-practices-prodkeys-firmware--latest-gameupdatedlc) •
[**Tri-Pipeline Architecture**](#-tri-pipeline-architecture) •
[**Quick Start & CLI**](#-quick-start--cli-reference) •
[**AetherNX Studio App**](#-aethernx-studio-native-swiftui-app) •
[**Showcase: Luigi's Mansion 3**](#-flagship-showcase-luigis-mansion-3-0100dca0064a6000) •
[**15 AI Skills**](#-integrated-ai-agent-skills-15-skills) •
[**Legal & Copyrights**](#-legal-notice-copyrights--third-party-licenses)

</div>

---

## 🌌 Overview

Because the Nintendo Switch (**ARM Cortex-A57**, AArch64 ISA) and modern Apple devices (**M1–M4 Macs, iPhone, iPad, Apple TV**, AArch64 ISA) share the same 64-bit ARM instruction set architecture, Switch titles do **not** require slow CPU interpretation or JIT dynamic binary translation on Apple Silicon.

**AetherNX** (`switch-comp`) brings together **31 open-source repositories** (forked and preserved under [`@iCosiSenpai`](https://github.com/iCosiSenpai)) and **15 specialized AI Agent Skills** into one unified studio that attacks Switch preservation and native execution from three synergistic angles:

| Pipeline | Engine & Subsystem | How It Works | Output Artifacts |
| :--- | :--- | :--- | :--- |
| **1. `COMP`**<br>*(Native Binary Porting)* | **HorizonNative (`dm/`)**<br>+ `rewrite_nso.py` + `dmsh_xlate` | Decompresses & merges **Base + Update + DLCs** (`nx_extract`), rewrites ARM64 Switch `NSO` binaries directly into native Apple **Mach-O `.dylib`** modules (patching `SVC #0x26` syscalls and `MRS Xn, TPIDRRO_EL0` TLS accesses), translates Maxwell GPU shaders into **Metal `.metallib`**, and links with the native HOS kernel (`dmhost`). | Native **macOS `.app`**, unsigned **iOS / iPadOS `.ipa`**, or ready-to-sign **Xcode Workspace**. |
| **2. `RECOMP`**<br>*(Static Recompilation)* | **`nxrt` (`recomp/nxrt/`)**<br>+ `SwitchRecomp` + `mush8` | Statically lifts every AArch64 function from `ExeFS/main` & `ExeFS/rtld` into portable **C11 / C++20 / Rust** source chunks (`main_000.c` .. `main_NNN.c` + dispatch tables), emitting integer/control-flow in C and NEON/SIMD/FP in bit-exact inline AArch64 assembly around a `Cpu` context. | **`lifted_c/*.c`** chunks, **`main_table.c`**, **`nxrt_game_desc.c`**, native `.o` / Mach-O binaries. |
| **3. `DECOMP`**<br>*(Clean-Room Decompilation)* | **`aethernx_decomp.py`**<br>+ `open-ead/nnheaders` + `sead` + `dread-tools` | Harvests every function boundary from `.eh_frame_hdr`, recovers and demangles `.dynsym` C++ symbols, classifies SDK subsystems (`nn::*`, `sead`, `nvn`, `libc`), and scaffolds a **C++20 CMake** project pre-wired to `nnheaders` & `sead` plus 15 AI matching-decomp skills. | **`DECOMP_REPORT.md`**, **`manifest.json`**, **`functions/*.tsv`**, **`symbols/*.tsv`**, **`CMakeLists.txt`**, **`src/main_reconstruct.cpp`**. |

---

## 🔑 Prerequisites & Best Practices: `prod.keys`, Firmware & Latest Game/Update/DLC

> [!IMPORTANT]
> **Self-Sourcing Notice (Da reperire autonomamente per conto proprio)**:
> AetherNX does **not** ship with any cryptographic keys, Nintendo Switch firmware, or game files. **All required inputs — `prod.keys`, `title.keys`, Switch System Firmware, Base Game, Title Updates, and DLCs — must be extracted or obtained independently by the user on their own from their own hardware.**

To achieve **100% compatibility, accurate shader translation, clean ExeFS/Mach-O binary rewriting, and full DLC mounting**, always follow these three golden rules (configurable directly in the **"Chiavi, Firmware & File"** tab of [`AetherNX.app`](./AetherNX.app)):

| Requirement | Recommended Version & Format | Why It Is Essential |
| :--- | :--- | :--- |
| **1. Cryptographic Keys (`prod.keys` & `title.keys`)** | Latest generation **`prod.keys`** (e.g. `v22.5.0+` containing `header_key`, `key_area_key_application_*`, `titlekek_*`, and `master_key_*`) | Required by `nx_extract` to decrypt the NCA headers, `ExeFS` NSO modules, `RomFS` containers, and `BKTR` Title Update patches. |
| **2. Switch System Firmware (`Firmware.zip` or NCA folder)** | **Latest Switch System Firmware** (e.g. `Firmware 22.5.0+`) | Provides shared system archives (`FontStandard`, `TimeZoneBinary`, Mii resources, system applets) and ensures compatibility with games and updates compiled against the newest Nintendo SDK (`nnSdk`). |
| **3. Game Packages: Base Game + Latest Update + All DLCs (`.nsp` / `.xci` / `.nsz` / `.zip` / `.rar` / `.7z`)** | **Base Game (`v0`) + Latest Title Update (`vXXXXX`) + All Updated DLCs** placed inside the same game folder (or subfolders) | **It is always strongly recommended to use the latest available Title Update and all updated DLCs.** AetherNX's per-title game profiles, shader maps (`shader_map.tsv`), `BuildID`-keyed runtime hooks, and static recompilation descriptors are calibrated against the **latest official update** of each title. |
| **4. Apple Toolchain ([Xcode](https://developer.apple.com/xcode/) 27.2)** | **[Xcode](https://developer.apple.com/xcode/) 27.2** + Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`), `.NET 10 SDK`, Python 3 (`capstone`, `lz4`, `nsz`, `fonttools`), `7zz` / `unar` | Compiles the native ARM64 Mach-O host, translates Maxwell shaders to Metal (`Xcode 27.2` Metal compiler lock), and signs macOS `.app` and iOS/iPadOS `.ipa` bundles (Zero-JIT required on iOS/iPadOS!). |

## How to Play

1. Place your **Base Game**, **latest Title Update**, and **all DLCs** (`.nsp`, `.xci`, `.nsz`, `.xcz`, or compressed `.zip`/`.rar`/`.7z` archives) inside a folder under `Games/<Game Name>/`.
2. Open **[`AetherNX.app`](./AetherNX.app)** (or use `./aethernx`), configure your `prod.keys` and `Firmware.zip` in the **"Chiavi, Firmware & File"** tab, and click **Build Nativo macOS `.app`** or **Build iOS / iPadOS `.ipa`** (supports both Apple Developer Accounts and **Free Apple ID Sideloading via SideStore / AltStore / Sideloadly with Zero JIT required**).

<details>
<summary><b>📸 Verified Game Profiles Gallery (75+ Native Switch Ports)</b></summary>

<!-- gallery: written by dm/tools/docs_gallery.py from docs/images/gallery.tsv; change the table, then run it -->
<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-bananza.jpg" width="256" alt="Donkey Kong Bananza"><br><small><b><a href="dm/games/040074A01BF12000/README.md">Donkey Kong Bananza</a></b><br>Switch 2, Mac only, from a dump</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/splatoon-raiders.jpg" width="256" alt="Splatoon Raiders"><br><small><b><a href="dm/games/0400380020056000/README.md">Splatoon Raiders</a></b><br>Switch 2, Mac only, from a dump</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-kart-8-deluxe.jpg" width="256" alt="Mario Kart 8 Deluxe"><br><small><b><a href="dm/games/0100152000022000/README.md">Mario Kart 8 Deluxe</a></b><br>no Mii heads</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-vs-donkey-kong.jpg" width="256" alt="Mario vs. Donkey Kong"><br><small><b><a href="dm/games/0100B99019412000/README.md">Mario vs. Donkey Kong</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/paper-mario-the-thousand-year-door.jpg" width="256" alt="Paper Mario: The Thousand-Year Door"><br><small><b><a href="dm/games/0100ECD018EBE000/README.md">Paper Mario: The Thousand-Year Door</a></b><br>60 fps with 1.0.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-3d-world.jpg" width="256" alt="Super Mario 3D World + Bowser's Fury"><br><small><b><a href="dm/games/010028600EBDA000/README.md">Super Mario 3D World + Bowser's Fury</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-bros-wonder.jpg" width="256" alt="Super Mario Bros. Wonder"><br><small><b><a href="dm/games/010015100B514000/README.md">Super Mario Bros. Wonder</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-galaxy.jpg" width="256" alt="Super Mario Galaxy"><br><small><b><a href="dm/games/010099C022B96000/README.md">Super Mario Galaxy</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-galaxy-2.jpg" width="256" alt="Super Mario Galaxy 2"><br><small><b><a href="dm/games/0100FD8022DAA000/README.md">Super Mario Galaxy 2</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-odyssey.jpg" width="256" alt="Super Mario Odyssey"><br><small><b><a href="dm/games/0100000000010000/README.md">Super Mario Odyssey</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-breath-of-the-wild.jpg" width="256" alt="The Legend of Zelda: Breath of the Wild"><br><small><b><a href="dm/games/01007EF00011E000/README.md">The Legend of Zelda: Breath of the Wild</a></b><br>60 fps with 1.9.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-links-awakening.jpg" width="256" alt="The Legend of Zelda: Link's Awakening"><br><small><b><a href="dm/games/01006BB00C6F0000/README.md">The Legend of Zelda: Link's Awakening</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-tears-of-the-kingdom.jpg" width="256" alt="The Legend of Zelda: Tears of the Kingdom"><br><small><b><a href="dm/games/0100F2C0115B6000/README.md">The Legend of Zelda: Tears of the Kingdom</a></b><br>60 fps with 1.4.3</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/13-sentinels.jpg" width="256" alt="13 Sentinels: Aegis Rim"><br><small><b><a href="dm/games/01003FC01670C000/README.md">13 Sentinels: Aegis Rim</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/absolum.jpg" width="256" alt="Absolum"><br><small><b><a href="dm/games/0100A83022A22000/README.md">Absolum</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/ace-attorney-investigations.jpg" width="256" alt="Ace Attorney Investigations Collection"><br><small><b><a href="dm/games/010005501E68C000/README.md">Ace Attorney Investigations Collection</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/advance-wars-1-2-re-boot-camp.jpg" width="256" alt="Advance Wars 1+2: Re-Boot Camp"><br><small><b><a href="dm/games/0100300012F2A000/README.md">Advance Wars 1+2: Re-Boot Camp</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ai-the-somnium-files.jpg" width="256" alt="AI: THE SOMNIUM FILES"><br><small><b><a href="dm/games/010089B00D09C000/README.md">AI: THE SOMNIUM FILES</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/ai-the-somnium-files-nirvana-initiative.jpg" width="256" alt="AI: THE SOMNIUM FILES - nirvanA Initiative"><br><small><b><a href="dm/games/0100713016CCC000/README.md">AI: THE SOMNIUM FILES - nirvanA Initiative</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/animal-crossing-new-horizons.jpg" width="256" alt="Animal Crossing: New Horizons"><br><small><b><a href="dm/games/01006F8002326000/README.md">Animal Crossing: New Horizons</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/animal-well.png" width="256" alt="ANIMAL WELL"><br><small><b><a href="dm/games/010020D01AD24000/README.md">ANIMAL WELL</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/astral-chain.png" width="256" alt="ASTRAL CHAIN"><br><small><b><a href="dm/games/01007300020FA000/README.md">ASTRAL CHAIN</a></b><br>60 fps target with 1.0.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/balatro.jpg" width="256" alt="Balatro"><br><small><b><a href="dm/games/0100CD801CE5E000/README.md">Balatro</a></b><br>played by touch</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ball-x-pit.jpg" width="256" alt="BALL x PIT"><br><small><b><a href="dm/games/010086A022444000/README.md">BALL x PIT</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta.jpg" width="256" alt="Bayonetta"><br><small><b><a href="dm/games/010076F0049A2000/README.md">Bayonetta</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta-2.jpg" width="256" alt="Bayonetta 2"><br><small><b><a href="dm/games/01007960049A0000/README.md">Bayonetta 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta-3.jpg" width="256" alt="Bayonetta 3"><br><small><b><a href="dm/games/01004A4010FEA000/README.md">Bayonetta 3</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/big-brain-academy-brain-vs-brain.jpg" width="256" alt="Big Brain Academy: Brain vs. Brain"><br><small><b><a href="dm/games/0100620012D6E000/README.md">Big Brain Academy: Brain vs. Brain</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/brain-memory-training-academy.jpg" width="256" alt="Brain Memory Training Academy"><br><small><b><a href="dm/games/0100F5D01DA3A000/README.md">Brain Memory Training Academy</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/captain-toad-treasure-tracker.jpg" width="256" alt="Captain Toad: Treasure Tracker"><br><small><b><a href="dm/games/01009BF0072D4000/README.md">Captain Toad: Treasure Tracker</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/catherine-full-body.jpg" width="256" alt="Catherine: Full Body"><br><small><b><a href="dm/games/0100BF00112C0000/README.md">Catherine: Full Body</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/celeste.jpg" width="256" alt="Celeste"><br><small><b><a href="dm/games/01002B30028F6000/README.md">Celeste</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/cuphead.jpg" width="256" alt="Cuphead"><br><small><b><a href="dm/games/0100A5C00D162000/README.md">Cuphead</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dark-souls-remastered-creation.jpg" width="256" alt="DARK SOULS: REMASTERED"><br><small><b><a href="dm/games/01004AB00A260000/README.md">DARK SOULS: REMASTERED</a></b><br>60 fps with 1.0.3</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/digimon-story-cyber-sleuth.jpg" width="256" alt="Digimon Story Cyber Sleuth: Complete Edition"><br><small><b><a href="dm/games/010014E00DB56000/README.md">Digimon Story Cyber Sleuth: Complete Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-country-tropical-freeze.jpg" width="256" alt="Donkey Kong Country: Tropical Freeze"><br><small><b><a href="dm/games/0100C1F0051B6000/README.md">Donkey Kong Country: Tropical Freeze</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-vii-reimagined.jpg" width="256" alt="DRAGON QUEST VII Reimagined"><br><small><b><a href="dm/games/0100A9D01C446000/README.md">DRAGON QUEST VII Reimagined</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-xi-s.jpg" width="256" alt="DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition"><br><small><b><a href="dm/games/01006C300E9F0000/README.md">DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition</a></b><br>60 fps with 1.0.4</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-resonance.jpg" width="256" alt="FINAL FANTASY RESONANCE"><br><small><b><a href="dm/games/0100606026F12000/README.md">FINAL FANTASY RESONANCE</a></b><br>60 fps with 1.0.1</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-tactics.jpg" width="256" alt="FINAL FANTASY TACTICS - The Ivalice Chronicles"><br><small><b><a href="dm/games/010038B015560000/README.md">FINAL FANTASY TACTICS - The Ivalice Chronicles</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/fire-emblem-engage.jpg" width="256" alt="Fire Emblem Engage"><br><small><b><a href="dm/games/0100A6301214E000/README.md">Fire Emblem Engage</a></b><br>60 fps with 2.0.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/fire-emblem-three-houses.jpg" width="256" alt="Fire Emblem: Three Houses"><br><small><b><a href="dm/games/010055D009F78000/README.md">Fire Emblem: Three Houses</a></b><br>60 fps with 1.2.0</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/ghost-trick-phantom-detective.jpg" width="256" alt="Ghost Trick: Phantom Detective"><br><small><b><a href="dm/games/010029B018432000/README.md">Ghost Trick: Phantom Detective</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/the-great-ace-attorney-chronicles.jpg" width="256" alt="The Great Ace Attorney Chronicles"><br><small><b><a href="dm/games/010036E00FB20000/README.md">The Great Ace Attorney Chronicles</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hades.jpg" width="256" alt="Hades"><br><small><b><a href="dm/games/0100535012974000/README.md">Hades</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/hades-ii.jpg" width="256" alt="Hades II"><br><small><b><a href="dm/games/0100A00019DE0000/README.md">Hades II</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hollow-knight-silksong.jpg" width="256" alt="Hollow Knight: Silksong"><br><small><b><a href="dm/games/010013C00E930000/README.md">Hollow Knight: Silksong</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hyrule-warriors-age-of-calamity.jpg" width="256" alt="Hyrule Warriors: Age of Calamity"><br><small><b><a href="dm/games/01002B00111A2000/README.md">Hyrule Warriors: Age of Calamity</a></b><br>60 fps with 1.3.0</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/kirby-and-the-forgotten-land.jpg" width="256" alt="Kirby and the Forgotten Land"><br><small><b><a href="dm/games/01004D300C5AE000/README.md">Kirby and the Forgotten Land</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/luigis-mansion-3.jpg" width="256" alt="Luigi's Mansion 3"><br><small><b><a href="dm/games/0100DCA0064A6000/README.md">Luigi's Mansion 3</a></b><br>60 fps with 1.4.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/metroid-dread.jpg" width="256" alt="Metroid Dread"><br><small><b><a href="dm/games/010093801237C000/README.md">Metroid Dread</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/monster-hunter-rise.jpg" width="256" alt="Monster Hunter Rise"><br><small><b><a href="dm/games/0100B04011742000/README.md">Monster Hunter Rise</a></b><br>60 fps with 16.0.2</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/monster-train-2.jpg" width="256" alt="Monster Train 2"><br><small><b><a href="dm/games/010051701FB46000/README.md">Monster Train 2</a></b><br>60 fps with 1.1.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler.jpg" width="256" alt="OCTOPATH TRAVELER"><br><small><b><a href="dm/games/010057D006492000/README.md">OCTOPATH TRAVELER</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler-0.jpg" width="256" alt="Octopath Traveler 0"><br><small><b><a href="dm/games/01005270232F2000/README.md">Octopath Traveler 0</a></b><br>60 fps with 1.0.5</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler-ii.jpg" width="256" alt="Octopath Traveler II"><br><small><b><a href="dm/games/0100A3501946E000/README.md">Octopath Traveler II</a></b><br>60 fps with 1.1.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/patricks-parabox.jpg" width="256" alt="Patrick's Parabox"><br><small><b><a href="dm/games/0100E44016C22000/README.md">Patrick's Parabox</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/persona-5-royal.jpg" width="256" alt="Persona 5 Royal"><br><small><b><a href="dm/games/01005CA01580E000/README.md">Persona 5 Royal</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pikmin-4.jpg" width="256" alt="Pikmin 4"><br><small><b><a href="dm/games/0100B7C00933A000/README.md">Pikmin 4</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-brilliant-diamond.jpg" width="256" alt="Pokémon Brilliant Diamond"><br><small><b><a href="dm/games/0100000011D90000/README.md">Pokémon Brilliant Diamond</a></b><br>60 fps with 1.3.0</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-legends-z-a.jpg" width="256" alt="Pokémon Legends: Z-A"><br><small><b><a href="dm/games/0100F43008C44000/README.md">Pokémon Legends: Z-A</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-scarlet.png" width="256" alt="Pokémon Scarlet"><br><small><b><a href="dm/games/0100A3D008C5C000/README.md">Pokémon Scarlet</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-violet.jpg" width="256" alt="Pokémon Violet"><br><small><b><a href="dm/games/01008F6008C5E000/README.md">Pokémon Violet</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-sword.jpg" width="256" alt="Pokémon Sword"><br><small><b><a href="dm/games/0100ABF008968000/README.md">Pokémon Sword</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-shield.jpg" width="256" alt="Pokémon Shield"><br><small><b><a href="dm/games/01008DB008C2C000/README.md">Pokémon Shield</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/portal.jpg" width="256" alt="Portal"><br><small><b><a href="dm/games/01007BB017812000/README.md">Portal</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/raging-loop.jpg" width="256" alt="Raging Loop"><br><small><b><a href="dm/games/010020400E1C2000/README.md">Raging Loop</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/rhythm-heaven-groove.jpg" width="256" alt="Rhythm Heaven Groove"><br><small><b><a href="dm/games/0100D9F01D474000/README.md">Rhythm Heaven Groove</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/romance-of-the-three-kingdoms-8-remake.jpg" width="256" alt="ROMANCE OF THE THREE KINGDOMS 8 REMAKE"><br><small><b><a href="dm/games/0100C2A01A730000/README.md">ROMANCE OF THE THREE KINGDOMS 8 REMAKE</a></b><br>controller only</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/sea-of-stars.jpg" width="256" alt="Sea of Stars"><br><small><b><a href="dm/games/01008C0016544000/README.md">Sea of Stars</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/shin-megami-tensei-v-vengeance.jpg" width="256" alt="SHIN MEGAMI TENSEI V: Vengeance"><br><small><b><a href="dm/games/010069C01AB82000/README.md">SHIN MEGAMI TENSEI V: Vengeance</a></b><br>60 fps with 1.0.3</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/stardew-valley.jpg" width="256" alt="Stardew Valley"><br><small><b><a href="dm/games/0100E65002BB8000/README.md">Stardew Valley</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/steins-gate-reboot.jpg" width="256" alt="STEINS;GATE RE:BOOT"><br><small><b><a href="dm/games/01008BC024FDE000/README.md">STEINS;GATE RE:BOOT</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-smash-bros-ultimate.jpg" width="256" alt="Super Smash Bros. Ultimate"><br><small><b><a href="dm/games/01006A800016E000/README.md">Super Smash Bros. Ultimate</a></b><br>offline</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/taiko-risshiden-v-dx.jpg" width="256" alt="Taiko Risshiden V DX"><br><small><b><a href="dm/games/0100346017304000/README.md">Taiko Risshiden V DX</a></b><br>Japanese · played by touch</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/unicorn-overlord.jpg" width="256" alt="Unicorn Overlord"><br><small><b><a href="dm/games/010069401ADB8000/README.md">Unicorn Overlord</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/yoshis-crafted-world.jpg" width="256" alt="Yoshi's Crafted World"><br><small><b><a href="dm/games/01006000040C2000/README.md">Yoshi's Crafted World</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/nier-automata.png" width="256" alt="NieR:Automata The End of YoRHa Edition"><br><small><b><a href="dm/games/010056B015FE8000/README.md">NieR:Automata The End of YoRHa Edition</a></b><br>60 fps with 1.0.3</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-echoes-of-wisdom.jpg" width="256" alt="The Legend of Zelda: Echoes of Wisdom"><br><small><b><a href="dm/games/01008CF01BAAC000/README.md">The Legend of Zelda: Echoes of Wisdom</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-country-returns-hd.png" width="256" alt="Donkey Kong Country Returns HD"><br><small><b><a href="dm/games/01009D901BC56000/README.md">Donkey Kong Country Returns HD</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-rabbids-sparks-of-hope.jpg" width="256" alt="Mario + Rabbids Sparks of Hope"><br><small><b><a href="dm/games/0100317013770000/README.md">Mario + Rabbids Sparks of Hope</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-2.jpg" width="256" alt="Xenoblade Chronicles 2"><br><small><b><a href="dm/games/0100E95004038000/README.md">Xenoblade Chronicles 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-3.jpg" width="256" alt="Xenoblade Chronicles 3"><br><small><b><a href="dm/games/010074F013262000/README.md">Xenoblade Chronicles 3</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-crystal-chronicles.jpg" width="256" alt="FINAL FANTASY CRYSTAL CHRONICLES Remastered Edition"><br><small><b><a href="dm/games/0100CE4010AAC000/README.md">FINAL FANTASY CRYSTAL CHRONICLES Remastered Edition</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/return-of-the-obra-dinn.png" width="256" alt="Return of the Obra Dinn"><br><small><b><a href="dm/games/010032E00E6E2000/README.md">Return of the Obra Dinn</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/blasphemous-2.png" width="256" alt="Blasphemous 2"><br><small><b><a href="dm/games/010040801A4C8000/README.md">Blasphemous 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/silver-pines.jpg" width="256" alt="Silver Pines"><br><small><b><a href="dm/games/0100D5B026844000/README.md">Silver Pines</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/blasphemous.jpg" width="256" alt="Blasphemous"><br><small><b><a href="dm/games/0100698009C6E000/README.md">Blasphemous</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-x-x2-hd-remaster.jpg" width="256" alt="FINAL FANTASY X/X-2 HD Remaster"><br><small><b><a href="dm/games/0100BC300CB48000/README.md">FINAL FANTASY X/X-2 HD Remaster</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-rabbids-kingdom-battle.jpg" width="256" alt="Mario + Rabbids Kingdom Battle"><br><small><b><a href="dm/games/010067300059A000/README.md">Mario + Rabbids Kingdom Battle</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/persona-4-golden.jpg" width="256" alt="Persona 4 Golden"><br><small><b><a href="dm/games/010062B01525C000/README.md">Persona 4 Golden</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-definitive-edition.jpg" width="256" alt="Xenoblade Chronicles: Definitive Edition"><br><small><b><a href="dm/games/0100FF500E34A000/README.md">Xenoblade Chronicles: Definitive Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-legends-arceus.jpg" width="256" alt="Pokémon Legends: Arceus"><br><small><b><a href="dm/games/01001F5010DFA000/README.md">Pokémon Legends: Arceus</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-party-jamboree.jpg" width="256" alt="Super Mario Party Jamboree"><br><small><b><a href="dm/games/0100965017338000/README.md">Super Mario Party Jamboree</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/cult-of-the-lamb.jpg" width="256" alt="Cult of the Lamb"><br><small><b><a href="dm/games/01002E7016C46000/README.md">Cult of the Lamb</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/paper-mario-the-origami-king.jpg" width="256" alt="Paper Mario: The Origami King"><br><small><b><a href="dm/games/0100A3900C3E2000/README.md">Paper Mario: The Origami King</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/batman-arkham-knight.jpg" width="256" alt="Batman: Arkham Knight"><br><small><b><a href="dm/games/0100ACD0163D0000/README.md">Batman: Arkham Knight</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/bastion.jpg" width="256" alt="Bastion"><br><small><b><a href="dm/games/010038600B27E000/README.md">Bastion</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/baba-is-you.jpg" width="256" alt="Baba Is You"><br><small><b><a href="dm/games/01002CD00A51C000/README.md">Baba Is You</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-heist-ii.jpg" width="256" alt="SteamWorld Heist II"><br><small><b><a href="dm/games/010089C01E9CA000/README.md">SteamWorld Heist II</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-heist.jpg" width="256" alt="SteamWorld Heist: Ultimate Edition"><br><small><b><a href="dm/games/010016100A186000/README.md">SteamWorld Heist: Ultimate Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/subnautica-below-zero.jpg" width="256" alt="Subnautica: Below Zero"><br><small><b><a href="dm/games/010014C011146000/README.md">Subnautica: Below Zero</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-dig-2.jpg" width="256" alt="SteamWorld Dig 2"><br><small><b><a href="dm/games/0100CA9002322000/README.md">SteamWorld Dig 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/streets-of-rage-4.jpg" width="256" alt="Streets of Rage 4"><br><small><b><a href="dm/games/0100EC9010258000/README.md">Streets of Rage 4</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-party-superstars.jpg" width="256" alt="Mario Party Superstars"><br><small><b><a href="dm/games/01006FE013472000/README.md">Mario Party Superstars</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/subnautica.jpg" width="256" alt="Subnautica"><br><small><b><a href="dm/games/0100429011144000/README.md">Subnautica</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-dig.jpg" width="256" alt="SteamWorld Dig"><br><small><b><a href="dm/games/01009320084A4000/README.md">SteamWorld Dig</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/team-sonic-racing.jpg" width="256" alt="Team Sonic Racing"><br><small><b><a href="dm/games/010092B0091D0000/README.md">Team Sonic Racing</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/well-dweller.jpg" width="256" alt="Well Dweller"><br><small><b><a href="dm/games/0100217023F6C000/README.md">Well Dweller</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/need-for-speed-hot-pursuit-remastered.jpg" width="256" alt="Need for Speed: Hot Pursuit Remastered"><br><small><b><a href="dm/games/010029B0118E8000/README.md">Need for Speed: Hot Pursuit Remastered</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ea-sports-fc-27.jpg" width="256" alt="EA SPORTS FC 27"><br><small><b><a href="dm/games/0100C49025D3E000/README.md">EA SPORTS FC 27</a></b><br>60 fps with 1.8d.310c</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/portal-2.jpg" width="256" alt="Portal 2"><br><small><b><a href="dm/games/0100ABD01785C000/README.md">Portal 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-monkey-ball-banana-rumble.jpg" width="256" alt="Super Monkey Ball Banana Rumble"><br><small><b><a href="dm/games/010031F019294000/README.md">Super Monkey Ball Banana Rumble</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/atelier-ryza-dx.jpg" width="256" alt="Atelier Ryza: Ever Darkness &amp; the Secret Hideout DX"><br><small><b><a href="dm/games/0100199023B2E000/README.md">Atelier Ryza: Ever Darkness &amp; the Secret Hideout DX</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-iii-hd-2d-remake.jpg" width="256" alt="DRAGON QUEST III HD-2D Remake"><br><small><b><a href="dm/games/01003E601E324000/README.md">DRAGON QUEST III HD-2D Remake</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hyrule-warriors-definitive-edition.jpg" width="256" alt="Hyrule Warriors: Definitive Edition"><br><small><b><a href="dm/games/0100AE00096EA000/README.md">Hyrule Warriors: Definitive Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/metroid-prime-remastered.jpg" width="256" alt="Metroid Prime Remastered"><br><small><b><a href="dm/games/010012101468C000/README.md">Metroid Prime Remastered</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-i-ii-hd-2d-remake.jpg" width="256" alt="DRAGON QUEST I &amp; II HD-2D Remake"><br><small><b><a href="dm/games/0100D7C01F254000/README.md">DRAGON QUEST I &amp; II HD-2D Remake</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dead-cells.jpg" width="256" alt="Dead Cells"><br><small><b><a href="dm/games/0100646009FBE000/README.md">Dead Cells</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hollow-knight.jpg" width="256" alt="Hollow Knight"><br><small><b><a href="dm/games/0100633007D48000/README.md">Hollow Knight</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/triangle-strategy.jpg" width="256" alt="TRIANGLE STRATEGY"><br><small><b><a href="dm/games/0100CC80140F8000/README.md">TRIANGLE STRATEGY</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/castlevania-belmonts-curse.jpg" width="256" alt="Castlevania: Belmont's Curse"><br><small><b><a href="dm/games/0100BA4026E94000/README.md">Castlevania: Belmont's Curse</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-robot-wars-y.jpg" width="256" alt="SUPER ROBOT WARS Y"><br><small><b><a href="dm/games/010063301BD50000/README.md">SUPER ROBOT WARS Y</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-rpg.jpg" width="256" alt="Super Mario RPG"><br><small><b><a href="dm/games/0100BC0018138000/README.md">Super Mario RPG</a></b></small></td>
<td></td>
<td></td>
</tr>
</table>
<!-- end of gallery -->

</details>

---

## 🏛️ Tri-Pipeline Architecture

```text
                     ┌───────────────────────────────────────────────────────────┐
                     │          Input Package Folder (.nsp / .xci / .nsz)        │
                     │     Base Game (v0) + Highest Update + Recursive DLCs      │
                     └─────────────────────────────┬─────────────────────────────┘
                                                   │
                              [nx_extract + BKTR/LCA Patch + AOC DLC Mount]
                                                   │
             ┌─────────────────────────────────────┼─────────────────────────────────────┐
             ▼                                     ▼                                     ▼
┌─────────────────────────┐           ┌─────────────────────────┐           ┌─────────────────────────┐
│     1. NATIVE COMP      │           │    2. STATIC RECOMP     │           │  3. CLEAN-ROOM DECOMP   │
│  (HorizonNative Engine) │           │ (nxrt / SwitchRecomp /  │           │  (nnheaders / sead /    │
│                         │           │       mush8 crates)     │           │  Capstone / 15 Skills)  │
├─────────────────────────┤           ├─────────────────────────┤           ├─────────────────────────┤
│ • NSO -> Mach-O .dylib  │           │ • AArch64 -> C11 Chunks │           │ • .eh_frame_hdr Bounds  │
│ • TLS TPIDRRO_EL0 Patch │           │ • NEON/FP Inline ASM    │           │ • ELF .dynsym Demangler │
│ • SVC #0x26 Trampolines │           │ • Static Dispatch Table │           │ • C++20 CMake Scaffold  │
│ • Maxwell -> Metal .air │           │ • HLE Symbol Intercepts │           │ • Byte-Matching Loop    │
│ • macOS .app & iOS .ipa │           │ • LAS / EoW / AC / SMO  │           │ • Ghidra/IDA Automation │
└─────────────────────────┘           └─────────────────────────┘           └─────────────────────────┘
```

### Multi-Package Hierarchy Support (Base Game + Title Updates + Recursive DLCs)

Modern Switch games rarely ship as a single file. AetherNX's enhanced package scanner (`_iter_package_files` in [`scripts/build_ipa_from_nsp.py`](./scripts/build_ipa_from_nsp.py)) automatically traverses your game folder and any nested DLC/Update subdirectories to classify every `.nsp`, `.xci`, `.nsz`, and `.xcz` container by its 64-bit Title ID:

- **Base Application (`TitleID & 0x1FFF == 0x000`)**: Provides the base `RomFS` and `ExeFS`.
- **Title Updates (`TitleID & 0x1FFF == 0x800`)**: Automatically selects the highest version (`v327680`, etc.) and applies `BKTR` / `LCA` patches on top of the Base Game in a single pass via `nx_extract --base <base.nsp> <update.nsp>`.
- **Downloadable Content / Add-On Content (`TitleID = Base + 0x1000 + Index`)**: Automatically discovers all DLC packs (even inside subfolders), deduplicates by DLC index choosing the newest version, and extracts each DLC into `aoc/<index>.img` for runtime mounting via `nn::aoc`.

---

## 🚀 Quick Start & CLI Reference

### 1. Environment & Repository Health Audit (`doctor`)

Verify that all Python packages (`capstone`, `lz4`, `zstandard`), Apple toolchains (`clang`, `clang++`, `xcrun`, `xcodebuild`, `glslangValidator`, `dotnet`), `prod.keys`, 15 AI skills, 702 Python files, and symlinks are healthy:

```bash
./aethernx doctor
```

### 2. Scan Your Switch Game Library (`scan`)

```bash
# Human-readable summary table
./aethernx scan "~/Games"

# Machine-readable JSON (used by AetherNX Studio)
./aethernx scan "~/Games" --json
```

### 3. Build a Native macOS `.app` or iOS / iPadOS `.ipa` (`COMP`)

```bash
# Build native Apple Silicon macOS .app (merges Base + Update + all DLCs)
./aethernx build-mac "~/Games/Luigi Mansion 3" --gpu none

# Build unsigned iOS / iPadOS .ipa
./aethernx build-ios "~/Games/Luigi Mansion 3" --gpu none

# Generate Xcode project & workspace only (for signing/profiling in Xcode)
./aethernx prepare-xcode "~/Games/Luigi Mansion 3"
```

### 4. Generate Clean-Room Decomp & Static Recomp Workspace (`DECOMP` + `RECOMP`)

```bash
# 1. Extract all function boundaries, demangled C++ symbols, CMakeLists.txt & DECOMP_REPORT.md
./aethernx decomp-init "~/Games/Luigi Mansion 3"

# 2. Lift ExeFS/main (or rtld) into static C11 translation units via nxrt
./aethernx lift "~/Games/Luigi Mansion 3" --module main
```

---

## 🖥️ AetherNX Studio (Native SwiftUI App)

Launch the native Apple Silicon SwiftUI desktop application ([`AetherNX.app`](./AetherNX.app), source in [`studio/Sources/AetherNXApp.swift`](./studio/Sources/AetherNXApp.swift)):

```bash
./aethernx studio
```

**Studio Capabilities:**
- **Library & Porting View**: Visualizes every discovered Switch game with live badges for **Base NSP**, **Merged Update Version**, **Mounted DLC Count**, **Maxwell-to-Metal Shader Count**, **Decomp Status**, and **Lifted C11 Chunks**, plus one-click buttons to **Launch Native Mac App**, **Build macOS `.app`**, **Build iOS/iPadOS `.ipa`**, **Generate Xcode Project**, and **Run Static Lifter (`nxrt`)**.
- **Decomp & Recomp Explorer**: Displays per-module `.text` code sizes, harvested function counts, dynamic symbol counts, and one-click Finder links to `functions/<module>_functions.tsv` and `recomp/lifted_c/`.
- **AI Skills Catalog (15 Skills)**: Browse and open any of the 15 integrated `SKILL.md` specifications.
- **Ecosystem & Credits Browser (31 Repos)**: Inspect all 31 unified open-source repositories, upstream URLs, `@iCosiSenpai` forks, and licenses, plus a live streaming **Pipeline Console Drawer** and **Audit / Doctor** runner.

---

## 👻 Flagship Showcase: Luigi's Mansion 3 (`0100DCA0064A6000`)

AetherNX has been validated end-to-end on **Luigi's Mansion 3** with its complete multi-package hierarchy:

### Package Hierarchy Merged
| Package Type | Container Filename | Title ID | Version | Size | Pipeline Action |
| :--- | :--- | :--- | :--- | ---: | :--- |
| **Base Game** | `Luigi’s Mansion 3[0100DCA0064A6000][US][v0].nsp` | `0100DCA0064A6000` | `v0` (`1.0.0`) | `6.35 GiB` | Base `RomFS` (`dict.dat`, `data.dat`, `init.dat`) |
| **Title Update** | `Luigi’s Mansion 3[0100DCA0064A6800][US][v327680][CR-13].nsp` | `0100DCA0064A6800` | `v327680` (`1.4.0`) | `1.01 GiB` | Merged via `nx_extract` (`245 files`, `7.1 GiB`) |
| **DLC Pack 1** | `Luigi’s Mansion 3 [Multiplayer Pack 1][0100DCA0064A7001][US][v131072].nsp` | `0100DCA0064A7001` | `v131072` | `1.12 MiB` | Mounted at `aoc/1.img` |
| **DLC Pack 2** | `Luigi’s Mansion 3 [Multiplayer Pack 2][0100DCA0064A7002][US][v65536].nsp` | `0100DCA0064A7002` | `v65536` | `1.12 MiB` | Mounted at `aoc/2.img` |

### Executable Modules (`ExeFS` v327680) — Native Mach-O, Static Recomp & Decomp Metrics
| Module | Build ID | `.text` (MiB) | `.rodata` (MiB) | `.data` (MiB) | `.bss` (MiB) | Functions Harvested | Dynamic Symbols | `SVC` Sites | `TLS/MRS` Sites | Native Mach-O Output |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **`main`** | `64b0f3571a7be3b38c6e0a7e6760d8fb` | `13.22 MiB` | `2.65 MiB` | `0.56 MiB` | `14.11 MiB` | **`49,491`** (`50,842` CFG) | `4` | `0` | `66` | `Luigi.dylib` + **`261` C11 Chunks** (`355 MB`) |
| **`subsdk0`** | `df892dc2ed6fa5be5772e90d35fd0c4f` | `5.69 MiB` | `0.85 MiB` | `0.15 MiB` | `0.18 MiB` | **`19,165`** | `12,175` | `1` | `2,817` | `subsdk0.dylib` |
| **`subsdk1`** | `dd3eb7a8d1ac1bf3db8850410b95f979` | `10.51 MiB` | `7.11 MiB` | `0.36 MiB` | `0.62 MiB` | **`8,544`** | `40,145` | `0` | `460` | `subsdk1.dylib` |
| **`sdk`** | `35f39fa2bd35f36735bd428efea70f89` | `11.68 MiB` | `3.59 MiB` | `0.37 MiB` | `0.90 MiB` | **`36,283`** | `10,007` | `120` | `2,140` | `sdk.dylib` |
| **`rtld`** | `692f1e18245d3f6768df861d09f2a3e5` | `0.01 MiB` | `0.00 MiB` | `0.00 MiB` | `0.00 MiB` | **`20`** (`40` CFG) | `3` | `2` | `2` | `rtld_000.c` (`120 KB`) |
| **Total** | — | **`41.10 MiB`** | **`14.20 MiB`** | **`1.44 MiB`** | **`15.81 MiB`** | **`113,503`** | **`62,334`** | **`123`** | **`5,485`** | **`Luigi's Mansion 3.app` (`7.7 GB`)** |

---

## 🧠 Integrated AI Agent Skills (15 Skills)

All 15 skills are installed in [`skills/`](./skills) and symlinked inside [`.claude/skills/`](./.claude/skills) for seamless activation in **Antigravity**, **Claude Code**, and **Codex**:

| # | Skill Slug | Skill Path | Upstream Origin | Core Capability |
| :-: | :--- | :--- | :--- | :--- |
| 1 | **`aethernx-universal`** | [`skills/aethernx-universal/SKILL.md`](./skills/aethernx-universal/SKILL.md) | **AetherNX Core** | Master orchestrator across `COMP`, `RECOMP`, and `DECOMP` pipelines. |
| 2 | **`matching-decomp`** | [`skills/matching-decomp/SKILL.md`](./skills/matching-decomp/SKILL.md) | `lemiur/Game-Decompilation-Skill-For-Claude` | Byte-accurate C/C++ function matching, compiler flag recovery & object diffing. |
| 3 | **`native-platform-porting`** | [`skills/native-platform-porting/SKILL.md`](./skills/native-platform-porting/SKILL.md) | `lemiur/Game-Decompilation-Skill-For-Claude` | Replacing proprietary SDK/graphics/audio layers with native Metal/CoreAudio/HID. |
| 4 | **`orchestrator`** | [`skills/orchestrator/SKILL.md`](./skills/orchestrator/SKILL.md) | `Ketbome/decomp-skills` | Coordinates multi-agent translation-unit queues and matching progress. |
| 5 | **`matcher`** | [`skills/matcher/SKILL.md`](./skills/matcher/SKILL.md) | `Ketbome/decomp-skills` | Iterative assembly diffing and register allocation alignment for Clang/LLVM. |
| 6 | **`permute`** | [`skills/permute/SKILL.md`](./skills/permute/SKILL.md) | `Ketbome/decomp-skills` | Automated AST permutation to resolve instruction scheduling differences. |
| 7 | **`decomp-code-rules`** | [`skills/decomp-code-rules/SKILL.md`](./skills/decomp-code-rules/SKILL.md) | `Ketbome/decomp-skills` | Enforces clean-room C++17/20 idioms, `sead`/`nn` naming, and fixed-size types. |
| 8 | **`helper-recovery`** | [`skills/helper-recovery/SKILL.md`](./skills/helper-recovery/SKILL.md) | `Ketbome/decomp-skills` | Identifies compiler intrinsics, soft-float helpers, and C++ ABI thunks. |
| 9 | **`wall-identifier`** | [`skills/wall-identifier/SKILL.md`](./skills/wall-identifier/SKILL.md) | `Ketbome/decomp-skills` | Diagnoses inline header mismatches, struct layout shifts, and ABI walls. |
| 10 | **`ns-game-apple-arm-port`** | [`skills/ns-game-apple-arm-port/SKILL.md`](./skills/ns-game-apple-arm-port/SKILL.md) | `realskyrin/ns-game-apple-arm-port` | Automates Switch NSP extraction, Mach-O rewriting, and Metal shader builds. |
| 11 | **`switch-port-to-apple`** | [`skills/switch-port-to-apple/SKILL.md`](./skills/switch-port-to-apple/SKILL.md) | `yokeyhh/switch-port-to-apple` | Diagnoses crash logs, missing HOS service stubs, and shader edge cases. |
| 12 | **`switch-static-recomp`** | [`skills/switch-static-recomp/SKILL.md`](./skills/switch-static-recomp/SKILL.md) | **AetherNX** + `SwitchRecomp` + `nxrt` | Static AArch64-to-C11/C++20 lifting workflow + 7 verification sub-skills. |
| 13 | **`evidence-decompile`** | [`skills/evidence-decompile/SKILL.md`](./skills/evidence-decompile/SKILL.md) | `coyang/decompile-skill` | Evidence-driven C/C++ reconstruction from Ghidra/IDA exports and call graphs. |
| 14 | **`re-skill`** | [`skills/re-skill/SKILL.md`](./skills/re-skill/SKILL.md) | `vgrichina/re-skill` | Headless Ghidra CLI automation for symbol, vtable, and pseudocode export. |
| 15 | **`gba-matching-decomp-skill`** | [`skills/gba-matching-decomp-skill/SKILL.md`](./skills/gba-matching-decomp-skill/SKILL.md) | `FacundoMainere/gba-matching-decomp-skill` | Structured `asm-differ` and multi-version alignment patterns. |

---

## 📂 Repository Layout

```text
switch-comp/
├── aethernx                      # Unified CLI (studio, scan, build-mac, build-ios, prepare-xcode, decomp-init, lift, skills, doctor)
├── AetherNX.app                  # Native Apple Silicon SwiftUI Studio Application
├── studio/                       # SwiftUI Studio source code (Sources/AetherNXApp.swift) & build_studio.sh
├── dm/                           # Native HOS Kernel (dmhost), nx_extract, NVN->Metal, Vulkan->Metal & per-game profiles
│   ├── games/                    # Per-title profiles, shader maps, and game patches (incl. 0100DCA0064A6000)
│   ├── gfx/                      # NVN-on-Metal, Vulkan-on-Metal, and Maxwell shader translator (dmsh_xlate)
│   ├── host/                     # Native ARM64 HOS kernel, services, audio, HID, and filesystem runtime
│   ├── ios/                      # iOS / iPadOS Xcode project generator and touch overlay
│   ├── mac/                      # macOS .app packager and launcher
│   ├── third_party/              # Embedded libraries (Ryujinx Shader, libvpx, stb_vorbis, Vulkan-Headers, FLIP)
│   └── tools/                    # NSO parser, symbol analyzer, and binary utilities
├── scripts/
│   ├── build_ipa_from_nsp.py     # Enhanced NSP/XCI/NSZ -> macOS .app / iOS .ipa builder (recursive DLC & Update support)
│   ├── aethernx_decomp.py        # Multi-module NSO Function Harvester, Decomp Generator, nxrt Lifter & Doctor Audit
│   └── rewrite_nso.py            # ARM64 NSO -> Mach-O binary rewriter (TLS/SVC/PageZero)
├── recomp/
│   ├── nxrt/                     # Universal C11 Static Recompilation Lifter & Runtime (fedebuonco/nxrt)
│   ├── switchrecomp/             # Rust/C++20 Static Recompiler & Maxwell Shader Translator (bgyss/SwitchRecomp)
│   ├── mush8-crates/             # Rust Static Recompiler & WGPU Runtime Crates (Catchingalls/mush8)
│   └── profiles/                 # Title-specific Recomp Tools (LASRecomp, EoWRecomp, AC-Recomp, smo-recomp)
├── decomp/
│   ├── nnheaders/                # Nintendo Switch SDK (nn::*) C++ Headers (open-ead/nnheaders)
│   ├── sead/                     # Nintendo EAD Standard Library Headers (open-ead/sead)
│   └── dread-tools/              # Matching Decompilation Diff & Setup Scripts (var-flotsam/dread-decomp)
├── frontends/
│   ├── lumanx/                   # LumaNX macOS & iOS Library Manager (Xc1Ym/LumaNX)
│   ├── nx-library/               # NxLibrary SwiftUI + Ryujinx Fallback (Bium23/NxLibrary)
│   ├── nx-os/                    # Switch OS Console-Style Launcher (tripathishubham1/nx-os)
│   └── nx-play/                  # NX2Apple / NX Play SwiftUI Launcher (LNPANDY/NX2Apple)
├── skills/                       # 15 AI Agent Skills (also linked in .claude/skills/)
├── LICENSE                       # Root MIT License + Third-Party Summary
├── NOTICE                        # Attribution & Redistribution Notice
├── COPYRIGHT.md                  # Full Copyright & License Registry for all 31 Repositories + Third-Party Libraries
└── PROVENANCE.md                 # Exact Directory-to-Upstream Provenance Mapping
```

---

## ⚖️ Legal Notice, Copyrights & Third-Party Licenses

### Clean-Room Interoperability & Non-Affiliation Disclaimer

1. **Zero Proprietary Code or Assets**: **AetherNX** (`switch-comp`) contains **no** Nintendo Switch system firmware, **no** cryptographic keys (`prod.keys`, `title.keys`), **no** proprietary Nintendo SDK libraries, and **no** copyrighted game ROMs/containers (`.nsp`, `.xci`, `.nsz`, `.xcz`). The repository `.gitignore` strictly blocks all key files, game containers, and extracted per-title build workspaces.
2. **User-Supplied Dumps Only**: To use AetherNX, you must supply your own legally dumped game packages and cryptographic keys extracted from your own personally owned Nintendo Switch hardware in accordance with applicable local laws regarding software interoperability and personal backup.
3. **Trademarks**: *Nintendo*, *Nintendo Switch*, *Horizon OS*, *Luigi's Mansion*, *Super Mario Odyssey*, *The Legend of Zelda*, *Metroid Dread*, *Astral Chain*, and *Mario Kart* are trademarks or registered trademarks of **Nintendo Co., Ltd.** *Apple*, *macOS*, *iOS*, *iPadOS*, *tvOS*, *Apple Silicon*, *Metal*, *Swift*, and *Xcode* are trademarks of **Apple Inc.** AetherNX is an independent open-source engineering project and is not affiliated with, endorsed by, or sponsored by Nintendo Co., Ltd. or Apple Inc.

---

### Complete 31-Repository Copyright & Attribution Registry

Every upstream project unified or referenced in AetherNX has been forked to [`https://github.com/iCosiSenpai`](https://github.com/iCosiSenpai) and retains its original copyright notices and license terms. See [`COPYRIGHT.md`](./COPYRIGHT.md), [`PROVENANCE.md`](./PROVENANCE.md), [`LICENSE`](./LICENSE), and [`NOTICE`](./NOTICE) for full details.

#### A. Native Apple Silicon Execution & Binary Rewriting (`COMP`)
| Project | Upstream Repository | `@iCosiSenpai` Fork | Copyright Holder / Author(s) | License |
| :--- | :--- | :--- | :--- | :--- |
| **HorizonNative (`nxnative`)** | [`seedds/nxnative`](https://github.com/seedds/nxnative) / [`UnknownSoldier1945/HorizonNative`](https://github.com/UnknownSoldier1945/HorizonNative) | [`iCosiSenpai/HorizonNative`](https://github.com/iCosiSenpai/HorizonNative) | Copyright (c) 2026 Alessio Cosi (`iCosiSenpai`), `seedds`, `UnknownSoldier1945` | **MIT** |
| **MacNativeGames** | [`ly05010419/MacNativeGames`](https://github.com/ly05010419/MacNativeGames) | [`iCosiSenpai/MacNativeGames`](https://github.com/iCosiSenpai/MacNativeGames) | Copyright (c) `ly05010419` | **MIT** |
| **switch2mac** | [`azmasm/switch2mac`](https://github.com/azmasm/switch2mac) | [`iCosiSenpai/switch2mac`](https://github.com/iCosiSenpai/switch2mac) | Copyright (c) `azmasm` | **GPL-3.0** |
| **nx-native-wrapper** | [`varyform/nx-native-wrapper`](https://github.com/varyform/nx-native-wrapper) | [`iCosiSenpai/nx-native-wrapper`](https://github.com/iCosiSenpai/nx-native-wrapper) | Copyright (c) `varyform` | **MIT** |
| **kartnative** | [`pahorema/kartnative`](https://github.com/pahorema/kartnative) | [`iCosiSenpai/kartnative`](https://github.com/iCosiSenpai/kartnative) | Copyright (c) `pahorema` | **GPL-3.0** |
| **nxnative-tv-builder** | [`ltomo2/nxnative-tv-builder`](https://github.com/ltomo2/nxnative-tv-builder) | [`iCosiSenpai/nxnative-tv-builder`](https://github.com/iCosiSenpai/nxnative-tv-builder) | Copyright (c) `ltomo2` | **MIT** |

#### B. Static Recompilers & Universal Runtimes (`RECOMP`)
| Project | Upstream Repository | `@iCosiSenpai` Fork | Copyright Holder / Author(s) | License |
| :--- | :--- | :--- | :--- | :--- |
| **nxrt** | [`fedebuonco/nxrt`](https://github.com/fedebuonco/nxrt) | [`iCosiSenpai/nxrt`](https://github.com/iCosiSenpai/nxrt) | Federico Buoncompagni (`fedebuonco`) | **Unlicense** |
| **SwitchRecomp** | [`bgyss/SwitchRecomp`](https://github.com/bgyss/SwitchRecomp) | [`iCosiSenpai/SwitchRecomp`](https://github.com/iCosiSenpai/SwitchRecomp) | Copyright (c) `bgyss` | **MIT** |
| **mush8** | [`Catchingalls/mush8`](https://github.com/Catchingalls/mush8) | [`iCosiSenpai/mush8`](https://github.com/iCosiSenpai/mush8) | Copyright (c) `Catchingalls` | **MIT / Apache-2.0** |
| **LASRecomp** | [`peiikai/LASRecomp`](https://github.com/peiikai/LASRecomp) | [`iCosiSenpai/LASRecomp`](https://github.com/iCosiSenpai/LASRecomp) | Copyright (c) `peiikai` | **MIT** |
| **EoWRecomp** | [`Nycolazs/EoWRecomp`](https://github.com/Nycolazs/EoWRecomp) | [`iCosiSenpai/EoWRecomp`](https://github.com/iCosiSenpai/EoWRecomp) | Copyright (c) `Nycolazs` | **MIT** |
| **AC-Recomp** | [`swaymun/AC-Recomp`](https://github.com/swaymun/AC-Recomp) | [`iCosiSenpai/AC-Recomp`](https://github.com/iCosiSenpai/AC-Recomp) | Copyright (c) `swaymun` | **MIT** |
| **smo-recomp** | [`Coz-0/smo-recomp`](https://github.com/Coz-0/smo-recomp) | [`iCosiSenpai/smo-recomp`](https://github.com/iCosiSenpai/smo-recomp) | Copyright (c) `Coz-0` | **MIT** |
| **SwitchStaticRecompiler** | [`kahoot-ut/SwitchStaticRecompiler`](https://github.com/kahoot-ut/SwitchStaticRecompiler) | [`iCosiSenpai/SwitchStaticRecompiler`](https://github.com/iCosiSenpai/SwitchStaticRecompiler) | Copyright (c) `kahoot-ut` | **Source-Available** |

#### C. Clean-Room Decompilation, SDK Headers & Game Engine Libraries (`DECOMP`)
| Project | Upstream Repository | `@iCosiSenpai` Fork | Copyright Holder / Author(s) | License |
| :--- | :--- | :--- | :--- | :--- |
| **nnheaders** | [`open-ead/nnheaders`](https://github.com/open-ead/nnheaders) | [`iCosiSenpai/nnheaders`](https://github.com/iCosiSenpai/nnheaders) | Copyright (c) `open-ead` contributors | **MIT** |
| **sead** | [`open-ead/sead`](https://github.com/open-ead/sead) | [`iCosiSenpai/sead`](https://github.com/iCosiSenpai/sead) | Copyright (c) `open-ead` contributors (`leoetlino` et al.) | **MIT** |
| **dread-decomp** | [`var-flotsam/dread-decomp`](https://github.com/var-flotsam/dread-decomp) | [`iCosiSenpai/dread-decomp`](https://github.com/iCosiSenpai/dread-decomp) | Copyright (c) `var-flotsam` & contributors | **MIT** |
| **OdysseyDecomp** | [`MonsterDruide1/OdysseyDecomp`](https://github.com/MonsterDruide1/OdysseyDecomp) | [`iCosiSenpai/OdysseyDecomp`](https://github.com/iCosiSenpai/OdysseyDecomp) | Copyright (c) `MonsterDruide1` & contributors | **MIT / Clean-Room** |
| **botw** | [`zeldaret/botw`](https://github.com/zeldaret/botw) | [`iCosiSenpai/botw`](https://github.com/iCosiSenpai/botw) | Zelda Reverse Engineering Team (`zeldaret`) | **Unlicense** |

#### D. AI Agent Decompilation, Recompilation & Apple Silicon Porting Skills (`SKILLS`)
| Project | Upstream Repository | `@iCosiSenpai` Fork | Copyright Holder / Author(s) | License |
| :--- | :--- | :--- | :--- | :--- |
| **Game-Decompilation-Skill-For-Claude** | [`lemiur/Game-Decompilation-Skill-For-Claude`](https://github.com/lemiur/Game-Decompilation-Skill-For-Claude) | [`iCosiSenpai/Game-Decompilation-Skill-For-Claude`](https://github.com/iCosiSenpai/Game-Decompilation-Skill-For-Claude) | Copyright (c) `lemiur` | **MIT** |
| **decomp-skills** | [`Ketbome/decomp-skills`](https://github.com/Ketbome/decomp-skills) | [`iCosiSenpai/decomp-skills`](https://github.com/iCosiSenpai/decomp-skills) | Copyright (c) `Ketbome` | **MIT** |
| **ns-game-apple-arm-port** | [`realskyrin/ns-game-apple-arm-port`](https://github.com/realskyrin/ns-game-apple-arm-port) | [`iCosiSenpai/ns-game-apple-arm-port`](https://github.com/iCosiSenpai/ns-game-apple-arm-port) | Copyright (c) `realskyrin` | **MIT** |
| **switch-port-to-apple** | [`yokeyhh/switch-port-to-apple`](https://github.com/yokeyhh/switch-port-to-apple) | [`iCosiSenpai/switch-port-to-apple`](https://github.com/iCosiSenpai/switch-port-to-apple) | Copyright (c) `yokeyhh` | **MIT** |
| **decompile-skill** | [`coyang/decompile-skill`](https://github.com/coyang/decompile-skill) | [`iCosiSenpai/decompile-skill`](https://github.com/iCosiSenpai/decompile-skill) | Copyright (c) `coyang` | **MIT** |
| **re-skill** | [`vgrichina/re-skill`](https://github.com/vgrichina/re-skill) | [`iCosiSenpai/re-skill`](https://github.com/iCosiSenpai/re-skill) | Copyright (c) `vgrichina` | **MIT** |
| **gba-matching-decomp-skill** | [`FacundoMainere/gba-matching-decomp-skill`](https://github.com/FacundoMainere/gba-matching-decomp-skill) | [`iCosiSenpai/gba-matching-decomp-skill`](https://github.com/iCosiSenpai/gba-matching-decomp-skill) | Copyright (c) `FacundoMainere` | **MIT** |

#### E. Native macOS / iOS / iPadOS Frontends & Launchers (`FRONTENDS`)
| Project | Upstream Repository | `@iCosiSenpai` Fork | Copyright Holder / Author(s) | License |
| :--- | :--- | :--- | :--- | :--- |
| **LumaNX** | [`Xc1Ym/LumaNX`](https://github.com/Xc1Ym/LumaNX) | [`iCosiSenpai/LumaNX`](https://github.com/iCosiSenpai/LumaNX) | Copyright (c) `Xc1Ym` | **MIT** |
| **NxLibrary** | [`Bium23/NxLibrary`](https://github.com/Bium23/NxLibrary) | [`iCosiSenpai/NxLibrary`](https://github.com/iCosiSenpai/NxLibrary) | Copyright (c) `Bium23` | **MIT** |
| **nx-os** | [`tripathishubham1/nx-os`](https://github.com/tripathishubham1/nx-os) | [`iCosiSenpai/nx-os`](https://github.com/iCosiSenpai/nx-os) | Copyright (c) `tripathishubham1` | **MIT** |
| **NX2Apple (`NX Play`)** | [`LNPANDY/NX2Apple`](https://github.com/LNPANDY/NX2Apple) | [`iCosiSenpai/NX2Apple`](https://github.com/iCosiSenpai/NX2Apple) | Copyright (c) `LNPANDY` | **GPL-3.0** |
| **nxnative-gui** | [`jamescastells/nxnative-gui`](https://github.com/jamescastells/nxnative-gui) | [`iCosiSenpai/nxnative-gui`](https://github.com/iCosiSenpai/nxnative-gui) | Copyright (c) `jamescastells` | **MIT** |

#### F. Embedded Third-Party Libraries (`dm/third_party/`)
| Library | Version | Purpose | License |
| :--- | :--- | :--- | :--- |
| **Ryujinx Shader Translator** (`Ryujinx.Graphics.Shader`, `Ryujinx.Common`, `Spv.Generator`) | `1.3.2` | Maxwell GPU bytecode to GLSL / SPIR-V translation (`dm/gfx/tools/dmsh_xlate`) | **MIT** (`dm/third_party/ryujinx/LICENSE.txt`) |
| **libvpx** | `v1.17.0` | VP9 video stream decoding (`dm/host/hle_movie.c`) | **BSD-3-Clause** (`dm/third_party/libvpx/LICENSE`) |
| **stb_vorbis** | `1.22` | Ogg Vorbis audio stream decoding (`dm/host/hle_movie.c`) | **MIT / Public Domain** (`dm/third_party/stb_vorbis/LICENSE`) |
| **Vulkan-Headers** | `1.4.363` | Vulkan C headers for Vulkan-on-Metal (`dm/gfx/vk/hle_vk.m`) | **Apache-2.0 OR MIT** (`dm/third_party/vulkan-headers/LICENSE.md`) |
| **NVIDIA FLIP** (+ `stb_image`, `tinyexr`) | — | Perceptual rendering quality metric (`dm/verify/gfxq/`) | **BSD-3-Clause** (`dm/third_party/flip/LICENSE`) |
| **deko3d** (GOB texture layout sizing) | — | Block-linear texture layout math (`dm/gfx/nvn/nvn_tex.c`) | **zlib** |

---

<div align="center">

**Created & Maintained by Alessio Cosi ([@iCosiSenpai](https://github.com/iCosiSenpai))**  
*Built with love for Apple Silicon & Game Preservation.*

</div>
