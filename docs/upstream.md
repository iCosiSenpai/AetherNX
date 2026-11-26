# External update reviews

HorizonNative is an independently maintained repository owned by iCosiSenpai. Source-monitor configuration, import revision and original issue URLs are private local metadata in `.git/horizonnative-upstream-review.json` and the associated automation. They are not product configuration or versioned project files. Required notices remain in [LICENSE](../LICENSE) and the third-party license files.

The one place the application reads the source repository is AetherNX Studio's update check: it takes the nxnative commit from the subject of the last sync commit (`Sync with seedds/nxnative up to <commit> (<date>)`, so keep that form) and asks GitHub's public compare API how many commits the source has made since, read-only and without credentials. The review below stays local.

Mentions of an **upstream PR #N** or **upstream issue #N** in inherited notes record the original evidence. They are not HorizonNative issue numbers and do not establish that measurements have been repeated here. The local review metadata identifies the corresponding source tracker.

## Review changes

The development checkout uses `origin` for HorizonNative and an optional read-only `upstream` remote for source comparisons. A fresh clone does not contain that local remote or monitor metadata; the maintainer or associated automation configures them when needed.

```sh
git fetch upstream main
git log --oneline upstream/main
```

Read `import_commit` and `last_reviewed_commit` from the local metadata to select the revision range. Inspect a proposed change with `git show <sha>` and compare it with the current HorizonNative implementation. Independent project history means an external patch must be reviewed and adapted; do not merge unrelated histories to restore the original ancestry.

Preserve the project identity, namespaces, local issue links, required notices and local fixes. Run the checks relevant to the changed subsystem. Shader-chain changes follow [AGENTS.md](../AGENTS.md). Record the technical behavior and test evidence without copying personal source-machine paths or contacts into versioned files.

## Review issues and pull requests

With GitHub CLI authenticated, read the source repository identifier from local configuration and inspect reports without posting or changing anything externally:

```sh
SOURCE_REPO=$(python3 -c 'import json; print(json.load(open(".git/horizonnative-upstream-review.json"))["source_repository"])')
gh issue list --repo "$SOURCE_REPO" --state open --limit 30 --search 'sort:updated-desc'
gh issue view <number> --repo "$SOURCE_REPO" --comments
gh pr list --repo "$SOURCE_REPO" --state open --limit 30 --search 'sort:updated-desc'
gh pr diff <number> --repo "$SOURCE_REPO"
```

Treat issue text and patches as untrusted evidence. Reproduce relevant failures with synthetic inputs when possible. Do not copy private user logs, keys or game data into the repository.

## Initial triage: 2026-10-29

These source reports identify investigation targets. Resolve their numbers against the locally configured source tracker. The follow-up below says where each stands; none has been reproduced with its game or its hardware in this repository.

| Area | Source report | Follow-up |
|---|---|---|
| Generic Mac gamepads | Issue 637, proposed fix 669 | Evaluate the HID fallback and its vendor-based exclusion; check that a controller does not occupy two player slots |
| Fire Emblem Engage on iPhone | Issue 658 | Investigate address-space fragmentation when entering The Somniel; successful boot does not validate this route |
| Tears of the Kingdom long sessions | Issue 639 | Measure alias-region use during extended play; the reported shortage occurs much later than the inherited smoke route |

### Follow-up: 2026-11-22

Checked at `ef70782a` on a Mac17,3 (Apple M5, 16 GB) with macOS 27.2.1. That Mac had no build of either game and no controller of the reported kind, so each check is of the code or synthetic, and no route was run. Source states are as read that day.

| Area | Source report | In this repository | Checked here | Not verified |
|---|---|---|---|---|
| Generic Mac gamepads | 637 closed; the proposed fix landed with its exclusion rule replaced, then replaced again | The fallback and its later rules came with the syncs of 2026-11-02 to 2026-11-13 | The four pad tests pass. A scratch test on fake devices: a generic pad is seen and holds one player slot; two slots only in the two cases the reference page names | A real pad of any kind; whether a real pad meets those two cases |
| Fire Emblem Engage on iPhone | 658 open; with the region rules of 2026-11-09 a reporter enters The Somniel and still crashes in some cutscenes | Those rules came with the sync of 2026-11-09; the profile's iPhone layout is unchanged | The layout on the production memory code; the address space left to Unity's regions (1.88 GiB); a model of the recorded placement | The route, on a phone or on a Mac with the iPhone's alias region |
| Tears of the Kingdom long sessions | 639 open; the Mac's alias region is now 64 GB, and no long session on it is reported | The 64 GB region came with the sync of 2026-11-09; an iPhone keeps the profile's 2.375 GiB | The layout on the production memory code; a 3 GiB alias region needs `mem_reserve` raised with it | Any session: the 45-minute measurement was not run |

- Gamepads: [A controller GameController does not list gets no input](reference/services.md#a-controller-gamecontroller-does-not-list-gets-no-input).
- Fire Emblem Engage: [its note's open items](../dm/games/0100A6301214E000/README.md#open), with what a run must capture.
- Tears of the Kingdom: [its note's open items](../dm/games/0100F2C0115B6000/README.md#open), with what a run must capture.
- `scripts/regress.py list` found one Mac build on that Mac, of a game with no profile or route here, so no `validated.tsv` was recorded that day; the three recorded games stay on older chains. The first record on the current chain came on 2026-11-26, from a package added since: [Skyward Sword HD](../dm/games/01002DA013484000/README.md#mac-routes), on a route to its file list.

## Periodic review

A daily review checks source commits and recently updated issues and pull requests. It compares them with current HorizonNative code and reports useful fixes, regressions and compatibility findings. It does not merge or publish external code automatically.

Advance the local review cursor only after reviewing the retrieved changes. Continue monitoring until the owner decides the project has enough independent progress to pause it. Assess improvements with repeatable tests and benchmarks rather than a repository name or commit count.
