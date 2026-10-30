# Functional code review: 2026-10-29

Reviewed revision: `491fe8506d3d387ef0bf950545d1e094a085a38f`. This is a functional review of the current foundation, separate from the earlier identity cleanup. Four defects below were reproduced with synthetic inputs and controlled failure injection. All four are fixed, with permanent regression tests ([Resolution](#resolution)). A second and a third audit round found the further defects listed there.

## Findings

### P1: Failed cloud-save backup can discard the local save

In [save_sync.c](../dm/host/save_sync.c#L398), `pull()` first exchanges the incoming and active save directories with `RENAME_SWAP`, then moves the old local directory to the backup. If this second operation fails, `pull()` returns failure without reversing the exchange. [mount_once()](../dm/host/save_sync.c#L486) reports that the current local save is being kept, then removes the staging directory, which still contains that old local save.

Reproduction: inject `ENOSPC` only into the backup `rename()` after a successful exchange. `pull()` returns `-1`, the active progress file contains the remote value instead of the local value, and after the caller's cleanup the backup is empty. The original progress file is no longer available at either location.

Required correction: preserve transaction state across both operations, roll back or explicitly retain the original directory on failure, and prevent caller cleanup from deleting an unrecovered save. Test failures in both save-folder iterations as well as failed backup moves.

### P1: An unreadable save is reported as an empty save

[has_entries()](../dm/host/save_sync.c#L77) returns false for every `names_of()` error, including `EACCES` and I/O failures. [pack_save()](../dm/host/save_sync.c#L163) therefore skips that directory and returns success. `ss_scan()` reports an empty save, allowing mounting code to choose a remote save as though no local progress exists. During sends, an unreadable folder can likewise disappear from an otherwise valid exported snapshot.

Reproduction: inject `EACCES` when enumerating an existing save directory containing a progress file. `ss_scan()` returns success, zero files and an empty hash rather than reporting failure. This bypasses the mount's existing error guard.

Required correction: distinguish a missing or empty directory from an unreadable one, and propagate enumeration errors through scanning, cloning, packing and import decisions. Preserve the active save and remote snapshot whenever the state is unknown.

### P2: A timed-out download can remove a later download

[fetch_thread()](../dm/host/save_sync.c#L358) deletes `j->local` when an abandoned fetch eventually finishes. Fetch destinations are reused by later [send_save()](../dm/host/save_sync.c#L411) attempts. The worker is detached and continues after the timeout, so its final unlink can delete a different attempt's file at the same path. The iOS coordinator can also complete its copy after the timeout.

Reproduction: hold the first fetch until its deadline expires, create the next download at the reused destination, then let the abandoned fetch finish. Its cleanup removes the new download. No real cloud provider is required to reproduce this scheduling error.

Required correction: give each fetch its own destination and ownership lifetime; publish the completed result only while that job is still accepted. Cleanup for a timed-out job must never touch another job's path.

### P2: Symbol-table sizing can request 8 GiB for two symbols

[parse_dynamic()](../dm/host/loader.c#L60) derives the symbol count from the distance between string and symbol table pointers instead of the dynamic hash table. With strings located before symbols, conversion through `sizeof` produces an enormous unsigned count, and [build_symhash()](../dm/host/loader.c#L75) allocates accordingly and can walk past the module. This also assumes the tables are adjacent. The Python reader already handles the dynamic hash table's symbol count in [nso_syms.py](../dm/tools/nso_syms.py#L21).

Reproduction: construct a bounded image with two symbols, a dynamic hash table declaring two entries, and the string table before the symbol table. The loader requests 8,589,934,592 bytes for its index. The reproduction intercepts that allocation so it does not actually consume that memory.

Required correction: derive and validate counts from the dynamic metadata, bound all table ranges against the mapped image, and check index-allocation failure. Reject an unsupported or damaged layout with a diagnostic rather than using a pointer difference as a count.

## Resolution

Fixed on 2026-10-29. Each regression test below fails against the reviewed revision and passes now.

| Finding | Fix | Regression test |
|---|---|---|
| P1 failed backup discards the local save | `pull()` checks both folders before moving anything, moves this device's folders straight into the backup and the cloud's into place, and puts back every move when one fails. This device's save never passes through `<save>.sync-tmp`. When putting back fails too, sync stops for that session and the log names the backup holding the save. Old backups are pruned only after a pull succeeds. | `t_save_sync_faults` (2)–(7): each of the four moves failing in turn, a failed rollback, an empty folder in the way, a mount whose pull fails |
| P1 unreadable save reported as empty | `names_of()` reports `readdir` errors. `has_entries()` returns −1 for an unreadable folder, and only a missing folder counts as empty. Scan, pack, pull and send propagate the error, so the mount turns sync off and a send sends nothing. A guest-name attribute that cannot be read fails the pack. | `t_save_sync_faults` (1), (6), (8), (11) |
| P2 timed-out download removes a later one | Each fetch downloads to its own `<local>.<pid>-<n>.part`. Only the caller still waiting renames it into place; an abandoned fetch removes only its own file. | `t_save_sync_faults` (9), (10) |
| P2 symbol table sized from pointer distance | `parse_dynamic()` takes the count from `DT_HASH`, else `DT_GNU_HASH`. The adjacent-table fallback applies only when the strings follow the symbols. Every table, name and the dynamic table's end are bounded by the module, and the index allocation is checked. A relocation naming a symbol past the table stops with a diagnostic. | `t_symbols` (dynamic tables) |

### Second audit round

A second round, with Codex, audited the host, graphics, Python tooling and front end in parallel read-only passes. The front-end pass completed its report. The host, graphics and Python passes stopped at the Codex account's usage limit before writing theirs; the leads they had already confirmed in their logs were each verified independently against the code before any fix. Severity follows the first round's scale.

| Area | Finding | Fix | Evidence |
|---|---|---|---|
| Save sync (P1) | A send replaced a newer cloud save when both had changed. The Mac launcher's send after a host that stopped before its first save mount could push an older save. | The send applies the mount's three-way decision: a newer cloud save is not replaced, and the next start brings it in. | `t_save_sync_faults` (12) |
| Save sync (P1) | A cloud backup that failed part way was left in place, and old backups had already been pruned. | The part of a backup is removed, and pruning happens only after the backup is complete. | `t_save_sync_faults` (13) |
| Save sync (P2) | After the player chose another cloud folder, an unchanged save was never sent there. | `<save>.sync` records the cloud file it was in step with. A state file without that record still counts for any folder. | `t_save_sync_faults` (14) |
| Mac launcher (P2) | After the host exited, SIGTERM was forwarded to the reaped (possibly reused) process ID, and the launcher ignored it during the cloud send. | The launcher waits for the host without reaping it (`WNOWAIT`), retires its PID with the signals held, then restores their default action. | `test_nsp_mac_app` `test_sigterm_during_the_cloud_send` |
| iOS front end (P1) | Text input requested while another alert was on screen was never shown, and the game thread waited forever. | Alerts are presented once nothing else is presenting or showing an alert, with a retry when UIKit refuses. | Not covered by an automated test (UIKit) |
| iOS front end (P2) | Each newly chosen cloud folder leaked a security-scoped access. | Scopes are balanced: the previous folder's scope is released when another is chosen or cloud saves are turned off. | Not covered by an automated test (device API) |
| Launcher (P2) | A non-finite value from an env file (`DM_RENDER_SCALE=nan`) trapped while the settings screen was drawn. | The row names the value with a warning, and no label converts a non-finite number. | `launcher_storage_check.swift` |
| Host IPC (P2) | `SendSyncRequest` read the domain header before checking that it fits the message. | The bounds check is done first. | Reviewed in code |
| Host fs (P1) | A failed `CreateFile` (space, I/O) left the save transaction committable, so a deleted-then-recreated file could commit as deleted. | Such a failure poisons the transaction, as a failed write does. | Host `t_fs` suites pass |
| Host fs (P2) | A rename checked only that its source was writable, so it could move a save file into a read-only RomFS. | The destination's mount is checked too. | Reviewed in code |
| Host audio (P1) | An AudioOut with more than 8 channels overran the silent sink's stack buffer. | Channel counts above the host's buffers are refused with a diagnostic. | Reviewed in code |
| Host movie (P1) | A Vorbis header of 65,025 bytes or more overran its single Ogg page. | Packets continue across pages as the Ogg format specifies. | `t_movie_vpx` (Ogg pages, ASan) |
| Host threads (P1) | `SetThreadActivity` could use a thread object freed while it waited for the pause. | The object is pinned for the wait, and the signal is sent while the thread is known to be alive. | Reviewed in code; TSan thread suites pass |
| Graphics (P2) | Listing a shader in `dual_want.tsv` did not change its cache key, so a rebuild could restore the build without the dual-source entry point. | Listed pixel shaders add the request to their key; other keys are unchanged. | `test_dmsh_pairs` |
| Graphics (P1) | 65 deferred uniform updates of 64 KiB filled the page filter, and its probe loop never ended. | The filter is kept to three quarters of its slots and skipped beyond that. | An extracted harness hangs on the old code and returns on the new |
| Packaging (P2) | Extractions were reused after an NSP was replaced, `nx_extract` changed or `--allow-damaged` was turned off. | Each extraction keeps a key of its inputs. An extraction made before keys existed is adopted once. | `test_nsp_incremental` `ExtractReuse` |
| Packaging (P1) | `--profile-out` naming the registered profile deleted its tables before copying them. | A derived folder on, inside or holding the registered profile is refused. | `test_nsp_incremental` |

The leads the interrupted passes had named without confirming them were all confirmed in the third round, and fixed there.

### Third audit round

On 2026-10-30 Codex ran again once its usage limit had reset. It first reviewed this working tree's fixes, then completed the host, graphics and Python passes. Each finding below was checked against the code before it was fixed.

| Area | Finding | Fix | Evidence |
|---|---|---|---|
| Save sync (P1, fix incomplete) | After a pull that could not be put back, the Mac launcher's send after the host could upload the mixed save. | `<save>.sync-stuck` records the backup holding this device's save. Nothing is synced (mount, sender, launcher) until the player deletes it. | `t_save_sync_faults` (15) |
| Save sync (P1, fix incomplete) | Cloud backups were pruned before the upload, so repeated failed uploads could replace distinct backups with copies of the same save. | Pruning happens only after a successful upload, and a failed attempt removes its own backup. | `t_save_sync_faults` (16) |
| Host fs (P1, fix incomplete) | A `CreateFile` failing while its path was resolved (folder or guest-name read error) did not refuse the commit. | Resolution failures other than the answers a game expects poison the transaction too. | `t_fs` 6e |
| Packaging (P2, fix incomplete) | A replacement extraction that failed deleted the old key, and the next run adopted the stale extraction as one made before keys existed. | The old key stays until the new extraction is swapped in. | `test_nsp_incremental` |
| Packaging (P1, fix incomplete) | `--provisional --profile-out` on the registered profile bypassed the derived-profile guard. | The provisional folder gets the same check. | `test_nsp_incremental` |
| Packaging (P2, fix incomplete) | A re-extraction of the same names and sizes did not invalidate the shader split, Vulkan or GL stages. | Those stage keys include the extraction's own key. | `test_nsp_incremental` |
| Packaging (P1) | `nro_collect.py` inflated a whole zstd frame before comparing its hash, so a small frame could exhaust memory. | Output is bounded by the NRO header's size. | `test_untrusted_inputs` |
| Packaging (P1) | RomFS images and their stamps were staged at a predictable `.part` path opened with truncation, which followed a link left there; `nx_extract` did the same. | Staging files are created exclusively (Python `mkstemp`, C# `CreateNew` after removing any link). | `test_untrusted_inputs`; `nx_extract` builds |
| Packaging (P2) | `regress.py` reused rewritten modules after the extracted modules, NROs or profile changed. | The cache's `.done` holds a digest of those inputs. | `test_regress` |
| Graphics tools (P1) | `cpk.py --extract` wrote archive members named `../…` or absolute paths outside its output folder. | Members are confined to the output folder, links included. | `test_untrusted_inputs` |
| Host movie (P1) | NV12 conversion of an odd-width picture stored 32 bytes into a shorter last chroma row. | The SIMD stores are bounded by the row. | `t_movie_vpx` (ASan) |
| Host threads (P1) | `GetThreadCoreMask`, `SetThreadCoreMask` and `GetThreadId` used a thread object without the lock that `CloseHandle` frees it under. | G is held from the lookup to the last use. | Reviewed in code; TSan suites pass |
| Host fs (P1) | A save file left open across a refused commit wrote into the deleted old tree, and the next commit succeeded without that data. | Writes and resizes through such a handle are refused and refuse the commit until it is reopened. | `t_fs` 6d |
| Host fs (P1) | A link inside a writable mount was followed, so a recursive clean could empty the folder it pointed to. | Links in writable mounts are not followed. | `t_fs` 6e |
| Host ro (P1) | `ro::LoadModule` hashed the length the NRO header claimed before checking that it was mapped. | The whole range is checked as readable first. | `t_nro` |
| Host audio (P2) | The audio renderer released a catch-up queue slot before copying it, so the producer could overwrite it. | The copy happens first. | Reviewed in code |
| Graphics (P1) | `WriteTexels` fell back to the whole-level path for a region outside the level and wrote past its buffer. | Regions are validated against the level, layers and slices before either path. | `t_cpu_tex` |
| Graphics (P1) | Pending-write collection could append past its fixed array before deduplication. | Every append is checked against the capacity. | Reviewed in code |
| Graphics (P1) | A re-registered sampler was released while recorded draws and the GPU still used it. | The old sampler is retired after the submissions recorded so far. | Reviewed in code; graphics suite passes |
| Graphics (P1) | The fault handler could read a dirty-tracking slot while it was reused for another pool. | Lock-free readers take a seqlock-validated copy. | `t_dirty_slots`, `t_dirty_race` |
| Graphics (P2) | A descriptor pool re-created larger at the same address overlapped the next pool's range. | It gets a fresh range. | Reviewed in code |
| Graphics (P2) | Each new fill pattern buffer stayed in the residency set for good. | The previous one is retired. | Reviewed in code |
| Graphics (P2) | Vulkan timestamp queries read a 1,024-entry ring by ticket, so an unreset query read a later submit's time. | Each query keeps its own completion time. | Reviewed in code; graphics suite passes |

The `dmsh_build.py` change moves the shader chain to `5ba3d294ee74`: game shader libraries and the host must be rebuilt together on the next build.

## Regression tests

The synthetic reproductions that came with the first round compiled against the production sources and asserted that each defect occurred. They now fail by design and have been replaced by the permanent tests above. On macOS, from the repository root:

```sh
make -C dm/host/tests GAME=010015100B514000 save-sync symbols
make -C dm/host/tests GAME=010015100B514000 asan tsan-threads
python3 -m unittest dm/tools/tests/test_nsp_incremental.py dm/tools/tests/test_nsp_mac_app.py dm/gfx/tests/test_dmsh_pairs.py dm/ios/tests/test_launcher_storage.py
```

## Coverage and limits

- All 92 Python test files under `dm/tools/tests`, `dm/ios/tests` and `dm/gfx/tests` passed in isolated processes: 788 reported cases, including 12 skipped cases. The real shipped translator was configured for compiler tests.
- The host's ASan/UBSan target passed. The dedicated save reproductions above also ran with ASan/UBSan.
- The host's `tsan-threads` target passed. The CPU texture ASan/UBSan target passed all 5,334 checks. Logical races involving reused file paths are not excluded by a clean memory-race detector result.
- Manual review concentrated on build orchestration and packaging, RomFS index validation, save transactions and synchronization, app storage/environment handling and module loading. Existing tests exercise additional host and graphics paths; passing them does not establish that the entire engine is defect-free.
- No real-game routes, long gameplay sessions or iOS device runs were performed for this review or its fixes. Game-specific compatibility and performance remain outside these results.
- The reported save failures were injected deterministically; real disk exhaustion, provider outages and permission failures were not induced on the owner's data.

The import backup bundle, local archive branch and temporary comparison copies have been deleted at the owner's request. Local source-monitor configuration is retained for the separately requested update reviews.
