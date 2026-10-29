# Functional code review: 2026-10-29

Reviewed revision: `491fe8506d3d387ef0bf950545d1e094a085a38f`. This is a functional review of the current foundation, separate from the earlier identity cleanup. Four defects below were reproduced with synthetic inputs and controlled failure injection. They remain open; this review does not modify engine behavior.

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

## Reproduce

The [save harness](review-repros/save_sync.c), [fetch hook](review-repros/save_sync_fetch_hook.c) and [loader harness](review-repros/loader_symbols.c) compile against the current production sources. They use synthetic folders and data; they do not read games, keys or player saves. A successful exit means the reported defect was observed, not that the implementation passed an acceptance test.

On macOS, from the repository root:

```sh
mkdir -p /private/tmp/horizonnative-code-review
clang -O1 -g -fsanitize=address,undefined -Wno-deprecated-declarations \
  docs/review-repros/save_sync.c docs/review-repros/save_sync_fetch_hook.c \
  -o /private/tmp/horizonnative-code-review/save_sync_review
/private/tmp/horizonnative-code-review/save_sync_review scan
/private/tmp/horizonnative-code-review/save_sync_review pull
/private/tmp/horizonnative-code-review/save_sync_review race

make -C dm/host GAME=010015100B514000 game_profile
clang -O1 -g -Wno-unused-function -Wno-deprecated-declarations \
  -I dm/host -I dm/host/gen/010015100B514000 -I dm/games/010015100B514000 \
  docs/review-repros/loader_symbols.c \
  -o /private/tmp/horizonnative-code-review/loader_symbols_review
/private/tmp/horizonnative-code-review/loader_symbols_review
```

## Coverage and limits

- All 92 Python test files under `dm/tools/tests`, `dm/ios/tests` and `dm/gfx/tests` passed in isolated processes: 788 reported cases, including 12 skipped cases. The real shipped translator was configured for compiler tests.
- The host's ASan/UBSan target passed. The dedicated save reproductions above also ran with ASan/UBSan.
- The host's `tsan-threads` target passed. The CPU texture ASan/UBSan target passed all 5,334 checks. Logical races involving reused file paths are not excluded by a clean memory-race detector result.
- Manual review concentrated on build orchestration and packaging, RomFS index validation, save transactions and synchronization, app storage/environment handling and module loading. Existing tests exercise additional host and graphics paths; passing them does not establish that the entire engine is defect-free.
- No real-game routes, long gameplay sessions or iOS device runs were performed for this review. Game-specific compatibility and performance remain outside these results.
- The reported save failures were injected deterministically; real disk exhaustion, provider outages and permission failures were not induced on the owner's data.

The import backup bundle, local archive branch and temporary comparison copies have been deleted at the owner's request. Local source-monitor configuration is retained for the separately requested update reviews.
