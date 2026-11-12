@AGENTS.md

## Claude Code: keeping the user's requests across sessions

The rules above are for every agent. These are Claude Code's own, for work that spans
more than one chat, session or context compaction.

- `plan-context/` is local and gitignored. A SessionStart hook
  (`.claude/settings.json` → `.claude/hooks/plan_context.sh`) prints its `status.md` and
  the checklist of the newest `requests-<date>.md` at every start, resume, clear and
  compaction. Rules for the folder are in `plan-context/README.md`.
- When the user gives a request with several parts, write it to
  `plan-context/requests-<YYYY-MM-DD>.md` first: their verbatim words, then a checklist
  in English. Do it before starting the work, not at the end.
- Keep `plan-context/status.md` current after each step that matters (a commit, a test
  run, a decision, a question for the user): branch, what is done, what is next, what is
  unverified. Keep it under about 80 lines, since it is injected into every session.
- Record choices in `plan-context/decisions.md`, above all what was left out and why, so
  a later session does not redo or silently drop it. Never delete a user request: mark it
  done or dropped with the reason.
- Notes about other projects studied for AetherNX (NX2Apple, NxLibrary, nxnative) go in
  `plan-context/research/`, so they are not read again from scratch.
- Durable facts that outlive one request (how the engine tracks upstream, what was
  adopted from whom) belong in Claude's memory or the repository docs, not only here.
