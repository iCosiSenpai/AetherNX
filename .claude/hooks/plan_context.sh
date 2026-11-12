#!/bin/sh
# SessionStart hook: print the local plan-context notes (gitignored, see
# plan-context/README.md) so an agent keeps the user's open requests after a new
# session, a resume or a context compaction. Prints nothing when the folder is absent.
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}/plan-context"
[ -d "$dir" ] || exit 0
echo "== plan-context (local agent notes; read plan-context/README.md for the rules) =="
if [ -f "$dir/status.md" ]; then
  cat "$dir/status.md"
fi
newest=$(ls -1 "$dir"/requests-*.md 2>/dev/null | sort | tail -n 1)
if [ -n "$newest" ]; then
  echo
  echo "== open requests: ${newest#"$dir"/} (checklist only; the file also has the user's verbatim text) =="
  awk '/^## Checklist/{on=1} /^## Original message/{on=0} on' "$newest"
fi
exit 0
