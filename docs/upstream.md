# External update reviews

HorizonNative is an independently maintained repository owned by iCosiSenpai. Source-monitor configuration, import revision and original issue URLs are private local metadata in `.git/horizonnative-upstream-review.json` and the associated automation. They are not product configuration, network endpoints used by the application or versioned project files. Required notices remain in [LICENSE](../LICENSE) and the third-party license files.

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

These source reports identify investigation targets. None has been reproduced or fixed by HorizonNative yet. Resolve their numbers against the locally configured source tracker.

| Area | Source report | Follow-up |
|---|---|---|
| Generic Mac gamepads | Issue 637, proposed fix 669 | Evaluate the HID fallback and its vendor-based exclusion; check that a controller does not occupy two player slots |
| Fire Emblem Engage on iPhone | Issue 658 | Investigate address-space fragmentation when entering The Somniel; successful boot does not validate this route |
| Tears of the Kingdom long sessions | Issue 639 | Measure alias-region use during extended play; the reported shortage occurs much later than the inherited smoke route |

## Periodic review

A daily review checks source commits and recently updated issues and pull requests. It compares them with current HorizonNative code and reports useful fixes, regressions and compatibility findings. It does not merge or publish external code automatically.

Advance the local review cursor only after reviewing the retrieved changes. Continue monitoring until the owner decides the project has enough independent progress to pause it. Assess improvements with repeatable tests and benchmarks rather than a repository name or commit count.
