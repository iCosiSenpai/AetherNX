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
