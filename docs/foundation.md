# HorizonNative: reusable foundation

HorizonNative is maintained by iCosiSenpai. The source import includes the complete engine and its tooling, rather than only an application wrapper. Imported game notes and benchmarks are historical evidence, not new HorizonNative validation.

## Components

| Component | Source | Reuse |
|---|---|---|
| End-to-end build pipeline | [NSP builder](../scripts/build_ipa_from_nsp.py) | Scan a game folder, extract inputs, rewrite modules, build shaders and package an app; JSON progress for a future UI |
| Native code rewriter | [patch_nso.py](../dm/tools/patch_nso.py) | Adapt AArch64 modules to Apple's process and memory constraints |
| Horizon host | [dm/host](../dm/host) | Service, memory, threading, audio, input and filesystem implementations |
| Graphics backends | [dm/gfx](../dm/gfx) | NVN, Vulkan and OpenGL integration with Metal; shader tooling and caches |
| Game profiles | [profile index](../dm/games/README.md) | Per-title configuration, build-specific patches, shader tables and documented findings |
| iOS application shell | [dm/ios](../dm/ios) | Unsigned app packaging, player controls, settings and storage |
| macOS application shell | [dm/mac](../dm/mac) | Standalone app packaging, launcher, settings, saves and logs |
| Front-end contract | [frontends.md](frontends.md), [settings.md](settings.md) | JSON progress, launcher metadata and shared settings for a future library UI |
| Diagnostics | [bug reports](../scripts/bug_report.py), [benchmarks](../scripts/bench.py), [regressions](../scripts/regress.py) | Redacted reports, repeatable routes and comparisons between revisions |
| Tests and reference material | [development guide](development.md), [agent guides](agents/README.md), [reference](reference/README.md) | Synthetic tests, build checks, bring-up recipes and known failure analysis |

## Identity and compatibility

New app bundles default to `io.github.icosisenpai.horizonnative.<title ID>`. Mac apps use the `HorizonNative` launcher, `~/Library/Application Support/HorizonNative/<title ID>/` and `~/Library/Logs/HorizonNative/`. Cloud saves use `HorizonNative Saves`. Prepared Xcode projects use `HorizonNative.xcworkspace`. Existing explicitly configured bundle IDs are still honored.

Old installations' saves and preferences are not migrated automatically. Back them up and copy them deliberately if moving an existing game to this new namespace. Regression and impact reports use `horizonnative-regress/1` and `horizonnative-impact/1`. Consumers of reports from the imported base must accept these HorizonNative identifiers. Internal `dm` names, environment switches, shader fingerprints and third-party source identities are preserved.

For rebuilding and checking the shipped translator, see [release tools](release-tools.md).

## Development priorities

1. Establish a repeatable Mac build and an unsigned iOS build from this repository.
2. Record HorizonNative's own tested games, devices and routes alongside the inherited notes.
3. Build an application UI around the existing progress and settings contracts.
4. Review upstream fixes and issue reports through the [update process](upstream.md), porting useful changes with focused tests.
5. Compare compatibility, correctness and frame times on the same games and devices before claiming an improvement over the imported base.

The MIT notice in [LICENSE](../LICENSE) and all [third-party notices](../dm/third_party/README.md) remain part of the reusable foundation.

GitHub Actions workflows are retained in `.github/workflows/`; Actions starts disabled in this private repository. Local validation is recorded in [validation.md](validation.md). Enable Actions in the repository settings when ready to run the inherited Mac/iOS build matrix and nightly fuzzing.
