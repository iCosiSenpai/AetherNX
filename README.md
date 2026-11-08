<div align="center">

<img src="./assets/aethernx-logo.png" width="175" alt="AetherNX Studio Logo" />

# ⚡ AETHERNX (`switch-comp`)

### **The Universal Nintendo Switch Decompilation (`DECOMP`), Static Recompilation (`RECOMP`) & Native Apple Silicon Porting (`COMP`) Suite**

*Turn Nintendo Switch packages (**Base Game + Title Updates + Multiple DLCs**) into native **macOS `.app`** bundles, **iOS / iPadOS `.ipa`** packages, statically recompiled **C11 / C++20 / Rust** translation units, and byte-matching **C++20 clean-room decompilation** workspaces.*

[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20iPadOS%20%7C%20tvOS-000000?style=for-the-badge&logo=apple&logoColor=white)](#tri-pipeline-architecture)
[![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20(ARM64)-0A84FF?style=for-the-badge&logo=arm&logoColor=white)](#tri-pipeline-architecture)
[![Graphics](https://img.shields.io/badge/GPU-Metal%20%2F%20NVN%20%2F%20SPIR--V-30D158?style=for-the-badge)](#tri-pipeline-architecture)
[![Pipelines](https://img.shields.io/badge/Pipelines-COMP%20%E2%80%A2%20RECOMP%20%E2%80%A2%20DECOMP-5E5CE6?style=for-the-badge)](#tri-pipeline-architecture)
[![Unified Repos](https://img.shields.io/badge/Unified%20Repos-31%20Forked%20Projects-FF9F0A?style=for-the-badge)](#complete-31-repository-copyright--attribution-registry)
[![AI Skills](https://img.shields.io/badge/AI%20Skills-15%20Agent%20Skills-BF5AF2?style=for-the-badge)](#integrated-ai-agent-skills-15-skills)
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
| **3. Game Packages: Base Game + Latest Update + All DLCs (`.nsp` / `.xci` / `.nsz`)** | **Base Game (`v0`) + Latest Title Update (`vXXXXX`) + All Updated DLCs** placed inside the same game folder (or subfolders) | **It is always strongly recommended to use the latest available Title Update and all updated DLCs.** AetherNX's per-title game profiles, shader maps (`shader_map.tsv`), `BuildID`-keyed runtime hooks, and static recompilation descriptors are calibrated against the **latest official update** of each title. |

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
