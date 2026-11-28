# Where this skill comes from

A copy of the `unslop-anything` agent skill by Erkam Yaman, MIT license (`LICENSE` beside this file), taken on 2026-11-28 from
https://github.com/erkamyaman/unslop-anything at commit `0ebab79cf0076bdf34841b8dab3abd284c147233`, folder `skills/unslop-anything`.
Its `agents/openai.yaml` (for another agent host) is left out; nothing else is changed.

It is here so that every Claude Code session opened on this repository, on a Mac or in the cloud, can run it on Studio, the
companion, the game launchers and the website (`/unslop-anything review|treat|scan|chart|follow-up`). Its detector,
`scripts/detect.js`, only reads files (`fs.readFileSync`, `fs.readdirSync`, `fs.statSync`); it was read before the copy was made.

To update it, take the folder again from a newer commit, read what changed in `scripts/detect.js`, and change the commit above.
This project's standing context for it is `.unslop-anything/chart.md`.
