# Validation record

Validated locally on 2026-10-29 with Xcode 27.1 and Python 3.15.2. This checks the independent project identity, application packaging and storage behavior; it does not establish new game compatibility or performance results.

## Initial project rename

The results in this section describe the initial rename, before the additional identity cleanup below.

## Results

- 187 Python tests passed across documentation, bug reporting, Mac app packaging and launcher execution, RomFS commands, incremental builds, shader-chain consistency, regression tooling and launcher settings.
- 37 Python tests passed across Xcode preparation, Swift launcher storage, unsigned IPA handling, IPA packaging and CI toolchain consistency.
- 54 C save-sync checks passed, including the renamed default cloud-save folder.
- The pinned ruff/pyright ratchet passed: 392 pre-existing findings matched the inherited baseline; no new findings and no stale baseline entries. This is not a claim that the imported code has zero lint findings.
- Shell syntax and `git diff --check` passed.
- At this initial stage, the original MIT license and all vendored third-party files were unchanged. All game profiles were retained.

## Commands

Run Python checks in an environment with `.github/requirements/lint.txt` installed:

```sh
python -m unittest -q dm/tools/tests/test_docs.py dm/tools/tests/test_bug_report.py dm/tools/tests/test_nsp_mac_app.py dm/tools/tests/test_nsp_romfs.py dm/tools/tests/test_nsp_incremental.py dm/tools/tests/test_nsp_chain.py dm/tools/tests/test_regress.py dm/tools/tests/test_launcher_settings.py
python -m unittest -q dm/ios/tests/test_xcode_workflow.py dm/ios/tests/test_launcher_storage.py dm/ios/tests/test_ipa_unsigned.py dm/ios/tests/test_pack_ipa.py dm/tools/tests/test_ci_toolchain.py
python dm/tools/lint_python.py
make -C dm/host/tests GAME=010015100B514000 save-sync
bash -n dm/ios/tools/build_ipa.sh
git diff --check
```

At this initial stage, the shader translator, chain fingerprints, host semantics and game profiles did not change. No game was launched, no game shader rebuild or gameplay regression run was performed, and no app was installed on a device for this rename. Packaging tests use synthetic inputs. Imported game notes retain their original validation limits. GitHub Actions workflows are available but start disabled in the private repository; the results above are local checks.

## Additional identity cleanup

The follow-up audit scans the complete tracked file tree, including binary content, for the retired maintainer and project identifiers in UTF-8, UTF-16LE and UTF-16BE. The only remaining identity match is the required copyright notice in `LICENSE`. Personal build paths were present in the old translator DLL and its PDB; the release translator has been rebuilt without debug symbols and the obsolete PDB removed. Required notices remain unchanged. In the vendored C# sources, only annotation comments changed; stripping comments before comparison yields identical source statements.

`AGENTS.md` now describes HorizonNative's ownership, interfaces, validation rules and data handling without inherited personal workstation assumptions. External source addresses and tracker URLs live in local monitor metadata and the associated automation. Report schemas use the HorizonNative identifiers documented in [foundation.md](foundation.md).

The rebuilt translator produces byte-identical SPIR-V for 96 synthetic inputs compared with the prior translator, covering buffer, 2D, array and 3D images with boundary coordinates, returning/discarded results and debug translation variants. The tool-lock check passes. Documentation, chain, regression and cache-fingerprint suites pass 73 tests, and the pinned Python lint/type ratchet still reports no new findings.

The image-atomic suite's 13 tests pass with real translator execution, SPIR-V validation, macOS and iOS Metal compilation and native Mac GPU result/sentinel checks. The geometry suite passes all 18 tests with its native fixtures configured, including 40 GPU PrimitiveID cases. These checks use synthetic shaders, not game data.

The initial native geometry invocation was missing the required test-executable variables. After building `t_geometry` and `t_geometry_primitive_id` and setting both variables, the geometry suite passed without a source-code fix. The native fixture build retains pre-existing compiler warnings; this record does not claim a warning-free engine build.

The pinned release assemblies and source digest changed, so the chain header is now `e25fce867fcc`. This deliberately invalidates old shader libraries: game shaders and the host must be rebuilt together on the next game build. The cleanup has not run real-game regression routes and does not establish improved game compatibility.

The published branch starts with a new HorizonNative import commit rather than retaining the source project's commit authors. The local recovery bundle, archive branch and temporary comparison copies were removed at the owner's request after the identity cleanup. The read-only external source remote and review metadata remain available for the requested monitoring. Required licenses remain in the new tree.

## Audit and launcher redesign: 2026-10-29

[Functional code review](code-review.md) records the defects fixed here and their regression tests. Only the fixes are validated by these checks; no compatibility or performance claim is made.

- All 93 Python test files under `dm/tools/tests`, `dm/ios/tests` and `dm/gfx/tests` passed in isolated processes with `DM_GAME=010015100B514000`: 801 cases, 22 skipped (after the third audit round). Several graphics test files need `DM_GAME` set and fail without it, independently of these changes.
- The pinned ruff/pyright ratchet reported 392 findings, all in the baseline, and no new ones.
- The host built for `010015100B514000`. Its `run`, `asan` (ASan/UBSan) and `tsan-threads` test targets passed after the third round, including `t_save_sync_faults` (49 checks; 20 of its first 33 fail on the reviewed revision), the dynamic-table cases of `t_symbols`, the Ogg paging and odd-size NV12 cases of `t_movie_vpx`, `t_fs` (101 checks, with stale handles and links) and `t_nro` (an NRO header larger than its mapping).
- The 23 graphics unit tests the CI runs in `dm/gfx/tests` passed, `t_cpu_tex` with its new region checks also under `--metal`. `nx_extract` builds with `dotnet build`.
- The deferred-uniform page filter was checked with a harness extracted from `nvn_mtl.m`: the reviewed revision hangs, the fixed one returns.
- The iOS launcher sources type-check against the iOS 26 SDK and the Mac sources against the macOS SDK. `test_launcher_storage` (model, saved choices, invalid env values, controller steps, tint contrast and the Mac window's measured layout) and `test_nsp_mac_app` (including SIGTERM during the cloud send, which fails on the reviewed launcher) passed.
- Screens were captured from the Mac window and, through Mac Catalyst running the iOS sources, for an iPhone in landscape and an iPad. No iOS simulator runtime is installed on this Mac, so text at accessibility sizes and controller focus were checked from the source and the model tests, not on screen. Neither has been checked on a device.
- `dmsh_build.py` is a shader chain input, so the chain is now `5ba3d294ee74`. Game shader libraries and the host must be rebuilt together on the next build.

No game was launched, no gameplay regression route was run, and no app was installed on a device.

## In-game menu, picture options, pipelines and fourth audit round: 2026-10-30

[Functional code review](code-review.md#fourth-audit-round) records the fixes; [settings.md](settings.md#the-in-game-menu) the features. The first iPhone run (Fire Emblem: Three Houses, iPhone 17 Pro Max, iOS 27.2) and its log are in the [game note](../dm/games/010055D009F78000/README.md#on-the-iphone).

- The graphics tests the CI runs (23) and `t_present_crop` (107 checks: stretch, sharp pixels, sharpening against real GPU output, the MetalFX switch, the anisotropy rule), `t_pso_bundle` (54, with the same-run prebuild check), `t_pso_archive` (74) and `t_pso_stall` (41) passed.
- The host's `run`, `asan` and `tsan` targets passed for `010055D009F78000`, including the new checks of `t_fs` (DLC from two folders, 106 checks), `t_nro` (NRR hash tables outside the NRR or its mapping), `t_swkbd` (UTF-16 Strings under one unit) and `t_audio` (AudioOut admission with unreclaimed buffers).
- Python: all 94 test files passed in isolated processes with `DM_GAME=010015100B514000` (804 cases, 22 skipped), among them the launcher storage test with the brand marks and the SVG path reader, the packaging, pipeline-archive default and environment-switch tests; the pinned ruff/pyright ratchet reported no new finding.
- A cross-review of this round's changes found eight defects in them (an alert over the in-game menu, controls pushed off screen, the iCloud resolution race, external textures waiting for an NVN fence, the − + hold, a shake while paused, the sharpness step, a fixed Touch feedback); all are fixed ([code review](code-review.md#fourth-audit-round)).
- On the iPhone 17 Pro Max, the final build booted with no red line: the 511-row prewarm list prepared before the first frame, the bundled `g18p` archive held every pair's base, no pipeline was compiled on the submit thread, 60 fps (p99 16.67 ms). A player session on the same build opened the in-game menu, used the layout editor and changed Screen live, with no red line.
- The iOS sources (the launcher, `InGameMenu.swift`, `SupportLinks.swift`) type-check against the iOS 26 SDK with no warning, `DmGamepad.m`, `front_ios.m`, `CloudSaves.m` and `main.m` compile for iOS (only the existing `mainScreen` deprecation warnings), and the Mac launcher with the support section type-checks against the macOS SDK.
- Xcode on this Mac is 27.2 now, whose Metal compiler (32023.922) is not the one `dmsh_chain.lock` names (32023.921): the device build below was made with `--allow-other-metal`. The libraries built with the tested compiler are kept beside it (`shader/ios/b-5ba3d294ee74.metal921`).
- Automatic iCloud saves need the iCloud container on the App ID, which an App Store Connect API key cannot create: until the account holder signs in to Xcode with the Apple ID once, device builds are signed without it and the launcher offers the folder picker as before.

Not verified: the first battle on the new package (the run did not reach it), controller shortcuts (Home, − and + held) on a physical controller, VoiceOver and accessibility text sizes on the device, and automatic iCloud (it needs the container on the App ID).

## Security audit, README and license: 2026-10-31

[Functional code review](code-review.md#security-audit-round) records the security round: 15 findings from four passes, each checked against the code; twelve fixed, the loader hardened, the build folder documented as trusted, one concerning only the imported base's own history.

- The host's `run`, `asan` and `tsan` targets passed for `010015100B514000`, with the new checks: `t_fs` 6f (a linked `save.new` or `save.work` loses only the link, a linked writable root is not cleaned; 115 checks), `t_save_sync` (the upload ignores a link at the old staging name; 57 checks, 49 fault checks) and `t_symbols` (relocation tables and slots outside a synthetic module refused, inside ones applied).
- Python: all 94 test files passed in isolated processes with `DM_GAME=010015100B514000` (812 cases, 22 skipped), among them the player `env.txt` filter (`test_player_env`), RomFS links and FIFOs refused and `resources.env` read as data (`test_romfs_image`), NRR tables and provisional shader-map rows (`test_untrusted_inputs`), and links planted during an IPA pack (`test_pack_ipa`). The pinned ruff/pyright ratchet reported no new finding; `env_switches.py --check` and `git diff --check` passed. The graphics tests passed.
- The shader chain version is unchanged (`5ba3d294ee74`): the shader-map check lives in the packing script, not in `dmsh_build.py`, so no game's shader libraries need building again.
- `nx_extract` builds with the link checks (.NET 10); no synthetic NSP fixture runs it. The Mac launcher and `crash.c` compile with the new code; `main.m` compiles for iOS.
- The README's banner renders in GitHub's Markdown (checked through GitHub's Markdown API); `test_docs` passed.

Not verified: a device run with the filtered `env.txt`, the watchdog's sampler on a real stall, and the Mac app rebuilt with the new launcher.
