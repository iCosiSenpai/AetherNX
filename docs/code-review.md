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

A second round audited the host, graphics, Python tooling and front end in parallel read-only passes. The front-end pass completed its report. The host, graphics and Python passes stopped before writing theirs; the leads they had already confirmed in their logs were each verified independently against the code before any fix. Severity follows the first round's scale.

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

On 2026-10-30 the review ran again. It first checked this working tree's fixes, then completed the host, graphics and Python passes. Each finding below was checked against the code before it was fixed.

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

### Fourth audit round

On 2026-10-30, after the first run on an iPhone, a review audited identity and attribution, first-use pipelines (from that run's log), the host and graphics, and the front ends, and surveyed open-source Switch emulators for features (in-game menus, on-screen control editing, Metal picture options, shader caches); the survey's ideas are in [settings.md](settings.md#the-in-game-menu) and [rendering.md](reference/rendering.md#picture-options-of-the-present). Each finding below was checked against the code before it was fixed.

| Area | Finding | Fix | Evidence |
|---|---|---|---|
| Pipelines (P1) | The launcher offers Metal 4 pipelines for every NVN game, but the IPA left out the `_bp` pulling libraries and the offline archive unless the profile set `pso_mtl4 on`: draws waited for every pipeline (Fire Emblem's first battle froze with sound). | Every NVN IPA packs the pulling libraries and the `g18p` archive; `IOS_PULL=0` / `DM_PSO_GPUS=none` leave them out. | `test_profile_pack`, `test_pso_offline` |
| Pipelines (P1) | Bases the device's prebuild wrote served only from the next start. | A file the prebuild writes joins the archive lookups at once (`arch_write`, `arch_lists` under `g_arch_lk`). | `t_pso_bundle` same-run check |
| Pipelines (P1) | A prebuild that skipped every pair for a missing library still wrote its stamp, so a fixed package would not build them. | The device's stamp counts the pulling libraries the app carries. | `t_pso_bundle`, `t_pso_archive`, `t_pso_stall` |
| Pipelines (P1) | Pipeline prebuild was offered (on) with Metal 4 off, where it does nothing. | `needs=DM_PSO_MTL4=1`. | `test_launcher_settings` |
| Pipelines (P1) | Fire Emblem: Three Houses shipped an empty prewarm manifest. | The 511 rows the iPhone recorded through boot, the opening and the first battle. | game note |
| Pipelines (P2, open) | A profile without `pso_pairs.tsv` whose shader split makes a supplemental table: the iOS package and the offline archive leave it out. | Not changed this round: Fire Emblem has no such table; the Mac paths already forward it. | not reproduced here |
| Present (P1) | The background suspend could finish while a display-link present was still encoding. | `g_pq_encoding`; the suspend waits for it as for committed presents. | `t_gfx_suspend`, `t_present_rescue` |
| RO (P1) | `RegisterModuleInfo` scanned an NRR's hash table wherever its header pointed. | The table must lie inside the NRR's own size, all of it readable. | `t_nro` |
| Audio (P1) | AudioOut admitted a buffer while played-but-unreclaimed ones filled the released queue; a stop then aborted the host. | Admission counts pending and released buffers. | `t_audio` admission check |
| Keyboard (P2) | A UTF-16 String of one byte made the copy length wrap. | Capacities under one unit copy nothing. | `t_swkbd` case 0 |
| Vulkan / GL (P2) | Destroyed swapchains kept their images resident and filled the window list. | `mtl_ext_tex_release`. | `t_vk_desc`, GL checks |
| Launcher (P2) | Hold frames when late was offered where no frame step runs. | `fixups:FPS_STATE_OFF`. | `test_launcher_settings` |
| Launcher (P2) | The touch layout selector had no VoiceOver element. | The menu button that replaces it is an accessibility element (`DmMenuAX`); the layout is in the in-game menu. | review |
| Cross-review (P1) | An alert queued over the in-game menu (a failed save, the game's text input) was what Resume dismissed: the game resumed under a menu that no longer closed. | Alerts wait while the menu is up (`present_when_free`); the menu closes only with nothing presented over it. | review |
| Cross-review (P2) | A control group moved near an edge at a small size left the screen at a larger one, the menu button included. | Every layout pulls each group back inside the screen (`keepOnScreen`). | review |
| Cross-review (P2) | Play pressed before the iCloud container had resolved started the whole session without cloud saves. | The resolution is published under a lock from its own thread, and Play waits up to 3 s for one under way. | review |
| Cross-review (P2) | Released external textures waited for an NVN fence a Vulkan or GL game never signals. | `mtl_ext_tex_release` drops the map's reference itself after the presents. | `t_vk_desc` |
| Cross-review (P2) | − and + held still never opened the menu: the controller sends no change to time the hold by. | A deadline of its own checks both are still down after 0.5 s. | review |
| Cross-review (P2) | A shake while paused played after Resume. | The shake detector is reset while the menu or the editor is up. | review |
| Cross-review (P2) | The controller's step on Sharpness stuck at 5 %; a fixed Touch feedback could still be changed from the menu. | Step arithmetic fixed; the row is disabled and guarded when fixed. | review |
| Identity (P2/P3) | The license credited only the original author; player docs pointed to another project's PR and launcher; two lines named another chain or front end. | The maintainer's copyright beside the original (MIT keeps it); the docs point to HorizonNative. Imported findings keep their `upstream PR #` provenance. | `test_docs` |

### Security audit round

On 2026-10-31 a review audited the whole repository for security in four read-only passes (host and game-file tools; graphics and packaging; front ends and apps; tooling and repository), against this threat model: game packages, downloaded files, a shared iCloud folder, a player's `env.txt` and the Files-visible Documents folder are untrusted; the maintainer's keys and signing identity must not leak. It reported 15 distinct findings; each was checked against the code. Twelve are fixed, one is a hardening of the loader, one is by design and documented, and one concerns only the imported base's own history.

| Area | Finding | Fix | Evidence |
|---|---|---|---|
| Mac launcher (P1) | A player's `env.txt` could set any variable, `DYLD_INSERT_LIBRARIES` included, which the launcher passed to the host it starts: a shared `env.txt` and a library beside it ran code in the host. | `dm/host/env_file.h`: the player's file sets only `DM_` and `MTL_` switches. The bundle's `env.txt` (part of the signed build) and the launch environment are not filtered. | `test_player_env` |
| Watchdog (P1) | `DM_WATCH_SAMPLE` went into a shell command line in single quotes: a quote in it ran a command when the stall watchdog fired (Mac). | `/usr/bin/sample` is started with `posix_spawn`, the path one argument. | compiled; the path no longer reaches a shell |
| Apps (P1) | A player's `env.txt` could name any file as a diagnostic output (`DM_FSLOG` truncates it), and move the app's folders: `DM_TEMP=save` made the game's clean of its temporary storage empty the saves. | The same header refuses the folder switches (`DM_ROMFS`, `DM_SAVE`, `DM_TEMP`, `DM_AOC_DIR` …) and any value with `/` or `.`/`..`, except the cloud saves folder `DM_SAVE_SYNC`. A plain file name still lands in the app's own folder. | `test_player_env` |
| Saves (P1) | A `save.work` or `save.new` left beside a save as a link made the next mount or commit delete the contents of the folder it pointed at; a writable mount whose root is a link (`Documents/temp` → `../Library`) was emptied by `CleanDirectoryRecursively`. | Recursive deletes open each folder with `O_NOFOLLOW` from its parent (`rm_fd_contents`); a root that is a link loses only the link; a clean refuses a linked root. | `t_fs` 6f |
| Cloud saves (P1) | The Mac's upload wrote `save.dmsync.<pid>.nosync` with `O_TRUNC` in the shared folder: a link left at that name had its target overwritten. | A random name made with `mkstemps` (exclusive). | `t_save_sync` upload check |
| RomFS packing (P1) | `romfs_image.py` followed links in the RomFS folder, copying any file on the Mac into the image. | Links and special files are refused; files are opened with `O_NOFOLLOW`. | `test_romfs_image` |
| Extraction (P1) | `nx_extract` wrote with `File.Create`, which follows a link already in the destination folder and truncates its target. | Linked folders inside the destination are refused; a file is removed and created new (`CreateNew`). | builds; no synthetic NSP fixture exercises it |
| Shader map (P1) | An archive member name with a tab or line break could add a row to a provisional shader map, whose key then named a file outside the work folder. | `shader_split.py` writes each field as one cell; the packing script stops on a provisional profile's split map whose key is not a plain file name stem (no folder, dot or space; the split writes 16 hexadecimal digits) or whose package name is not a plain name (`check_shader_map`; checked there, not in `dmsh_build.py`, whose bytes are part of the shader chain version). All 112 profile maps conform. | `test_untrusted_inputs` |
| Scripts (P1) | `push_romfs.sh` and `stage_resources.sh` ran `resources.env` with `source`. | `dm/ios/tools/read_resources.py` reads it as data: only the resource settings `gen_resources.py` writes (`DM_RESOURCE_ROMFS` and the rest), one value each. | `test_romfs_image` |
| Xcode project (P1) | `ln -sfn` into a real `tools` folder left that folder's scripts in place, which the build ran. | A real folder where the link goes stops the preparation; the link is checked. | review |
| IPA packing (P1) | `<ipa>.idx.partial` was opened with truncation after the whole pack: a link made there meanwhile had its target overwritten. | The index and the new archive are created exclusively, with `O_NOFOLLOW`. | `test_pack_ipa` |
| NRO collection (P2) | An NRR's hash count was not bounded by the file: 848 bytes asked for four billion iterations. | The table must lie inside the file, as `hle_ro.c` requires at run time. | `test_untrusted_inputs` |
| Loader (P1, hardening) | Relocation tables and the slots they write were not checked against the module: an `r_offset` of `0xfffffffffffffff8` wrote before its base. A game module is code that runs natively in the host anyway, so this is no security boundary; a damaged module now stops with its name. | `reloc_slot`, bounded `DT_RELA`, `DT_JMPREL` and `DT_RELR` (aligned). | `t_symbols` relocation tables |
| Build folder (P1, by design) | A `<title ID>_build/profile/*/patches.py` is executed by the rewriter. | Not changed: the build folder holds the rewritten code the app runs and stage stamps the next build reuses, so it is trusted like any build tree. [development.md](development.md#the-packing-script-in-detail) says to build only from one you made. | documented |
| History (P3) | Two commits contain workstation paths of the imported base's author (a user name, a cloud-drive folder, a keys location; no key material). | Nothing to change here: those commits are only in the imported base's own history (the `upstream` remote); HorizonNative's history starts at its import commit and does not contain them. | `git branch -r --contains` |

### Fifth audit round

On 2026-11-10, after the nightly fuzz run failed, a review audited the Studio app, the `aethernx` tool, the host and the CI runs. Each finding below was checked against the code before it was fixed; the Studio's own logic got automated tests in the same change (`studio/tests/test_studio.py`, run by the `studio` CI job).

| Area | Finding | Fix | Evidence |
|---|---|---|---|
| Fuzz (P2) | The nightly run failed: a cut or damaged NARC raised `cra.Error` out of `shader_split.py`. | A red line naming its layout, adapted from upstream PR #1278 (Vincent Keyan); seven corpus files. | `test_cra`, `test_split_narc`, `test_fuzz_corpus` |
| Studio (P1) | The Danger Zone removed every app, archive and IPA in a game's folder, also when that folder was a library folder holding other games' files; `isSafeToRemove` compared URLs that never match, so it protected no folder. | Apps go only when their `DMTitleID` is the game's; a game whose folder is a library folder loses only its packages and its apps; the confirmation lists the paths; nothing goes while the game runs; folders are compared as paths. | `test_studio` |
| Scan (P2) | A package at the top of a library folder made the scan take the whole library for one game. | The game folders inside are scanned as before. | `test_aethernx_cli` |
| GPU tests (P2) | `t_render_enable_queue` and `t_render_counter_overlap` failed under a profile with `render_cond`. | The test fixes of upstream `d902bc66` and `2a6f9b32`. | `make -C dm/gfx/tests run` |
| RomFS packing (P2) | Random staging names left dump and NUP builds without progress and left an image-sized file per stopped build. | [The fixed `<image>.part`, created new](reference/packing.md#packing-a-romfs-image-shows-no-progress-and-each-stopped-pack-leaves-an-image-sized-file). | `test_romfs_image` |
| `aethernx` (P2) | `unpack` gave `.tar.*` archives to a tool that cannot read them, waited at a password prompt, deleted the archives when no game came out, and `--delete-archives` removed only the first volume; `ios-slim` built without the extracted files the copy to the phone needs; `doctor` did not check the Metal compiler of the tested shader chain; `setup` installed unpinned packages. | bsdtar for tar archives; no standard input, and a hint for an encrypted archive; archives kept and exit 1 when no game came out; every volume removed; `--keep-extracted` for `ios-slim`; a required Metal check (`own_compilers.py --check-metal`); the versions CI tests. | `test_aethernx_cli` |
| Studio (P2) | The extra build options were split at spaces, so a quoted value broke; `ios-slim` lacked `--keep-extracted` here too; a failed setup check showed an alert behind its own sheet. | Words split as a shell would, an unclosed quote stops with a message; the error is shown in place. | `test_studio` |
| Studio (P2) | Artwork lookups (the title ID or the name to nlib.cc and Wikipedia) began before the Setup Assistant had shown the setting; Download Again raced with a fetch under way; turning the setting off did not stop the queue. | No lookup before the assistant is done or skipped; fetches from before a clear are dropped; the queue checks the setting before each game. | review |
| Studio (P2) | Each failed start of a command left two threads and four descriptors; `capture` read stderr with a data race; a stalled `git fetch` held the update check for good. | The readers start after the process; stderr is handed over once its reader ends; timeouts and git's low-speed limit. | `test_studio`; Swift 6 type check clean |
| Studio updater (P1) | The release archive was unpacked before its signature was checked, and nothing checked its entries: ditto names each entry from its local header and also unpacks one the central directory leaves out. Run from its disk image or a translocated copy, the update ended in a file-system error. | `isSafeAppArchive` reads the archive as ditto does (local headers in order, each with its record's name and sizes, each deflate stream ending where recorded) and takes only files and folders under `AetherNX.app/` and `__MACOSX/`; a read-only location opens the release page. | `test_studio`: 16 hostile archives refused, 3 accepted, each check mutation-tested |
| Host restart (P1) | `ExecuteProgram` with a parameter over 64 KB returned to a game that waits to be ended; a thread still running after 10 s stayed while the reset remapped memory under it; a thread created as the restart began was never marked and waited for good. | The first two stop the process with a FATAL line; a thread linked during a restart is marked (`g_killing`). | `t_restart` |
| Host fs (P1) | A restart kept what the old program wrote to its saves and did not commit (the end of a process drops it on Horizon). | RELEASE clones each save's work directory from its committed version; a clone that fails leaves it tainted. | `t_fs` ⑩ |
| Save sync (P1) | A stop between a pull's moves left a mixed save and no `<save>.sync-stuck`. | [The marker is on disk before the first move](reference/services.md#a-cloud-save-pull-stopped-between-its-moves-left-no-marker). | `t_save_sync_faults` (17) |
| CI (P3) | The pinned actions had no update path. | `.github/dependabot.yml`. | review |
| Studio (P3) | Three Italian strings showed another meaning: the Settings tab "Building" read "In compilazione" (its key was given twice), the tools' Update buttons read "Aggiornamento" (the noun), and a setup row's spoken status "Pronte". The build log showed the `game` progress event as raw JSON. | Distinct keys (`Building…`, `Game update`, `Made`); events the app does not show stay out of the log. | `test_studio`: every key has its Italian, none is given twice, none is unused |

The host tests ran plain, under ASan and UBSan, and under TSan; the tool tests (174 files), clang-tidy and the Python lint ran locally as in CI, with the three CI hosts and the iOS compile check. The GPU tests, which CI does not run, passed on an M5 with the two GPU test fixes; the later changes do not reach them. One real game was checked (`regress.py check --quick` on Fire Emblem Fortune's Weave: 16,888 shaders unchanged); no game was played for these fixes, and no iPhone, cloud service, full disk or app update was used.

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
