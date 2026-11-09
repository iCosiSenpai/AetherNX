# Changelog

## 0.1.0

The first release under the AetherNX name.

**AetherNX Studio**, rebuilt from scratch:

- A library sidebar with search, and one page per game: its files (base game, update, DLC), its builds, and Build, Play and More.
- Builds show their real progress (step, progress bar, time left) from the build script's JSON events, can be stopped, and log to an Activity panel.
- Settings (⌘,) in three panes: General, Keys, Building. Choices are kept between launches.
- Keyboard shortcuts for every action, listed in the README.
- A setup check that lists what is missing and the command that installs it, and installs the Python packages for you.
- First launch finds the AetherNX tools or downloads them; it no longer depends on one machine's folders.
- English and Italian.
- Signed with a Developer ID and notarized.

**`./aethernx`**, rewritten:

- Works with macOS's own bash: builds no longer stop at once with `KEYS_ARGS[@]: unbound variable`.
- New `setup` (a Python environment with the packages the build needs) and `version`; `doctor` tells required from optional pieces and prints the fix for each.
- `build <folder> --target mac|ios|ios-slim|xcode` replaces the four build commands, which remain as aliases.
- `scan --json` reports folders it could not read instead of dropping them, and gives each game's display version and icon once built.
- `unpack` extracts archives only: `.nsz` and `.xcz` packages were always converted by the build.
- Unknown commands fail with an error.

**Fixes**

- The app passed options the build script does not have (`--re-extract`, `--re-rewrite`, `--re-translate`, `--gpu ryujinx`); the Metal HUD and language settings did not reach the game. Removed or replaced with the build's real options.
- Removed paths of the maintainer's own Mac from the code, the app and the docs.
- The firmware and `title.keys` settings were never used by a build; they are gone.
- Deleting a build folder or a shader cache asks first and moves it to the Trash.

**Repository**

- Third-party projects are Git submodules in `vendor/` instead of copies that had lost their license files. [CREDITS.md](CREDITS.md) lists each with its real license.
- The built app is no longer committed; it is attached to each release.
- CI builds the Studio app and checks the command-line tool.
