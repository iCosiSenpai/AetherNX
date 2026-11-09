# Changelog

## 0.2.0

Switch 2 games, and an app that sets itself up and keeps itself up to date.

**Engine**, synced with nxnative up to `7479adf` (2026-11-09), 358 changes:

- **Switch 2 games**: Fire Emblem Fortune's Weave, Splatoon Raiders, Mario Kart World, Ocarina of Time, Hyrule Warriors: Age of Imprisonment and more; NVN2 task and mesh shaders, DLSS on MetalFX, AV1 movies (VideoToolbox, else dav1d).
- Dump folders without `base/` (an update that holds the whole game, as Fortune's Weave's dumps do), NUP containers, and applications of several programs.
- The shader translator was rebuilt (chain `c1ab2399d5c7`): **every game's shaders are translated again** at its next build.
- AetherNX's own features carried over: the in-game menu and picture options, iCloud saves (now with the stricter rule that only the game's start decides between two changed saves), Assassin's Creed's in-place restart and the launcher.

**AetherNX Studio**

- A **Setup Assistant** on first launch: the build tools (found or downloaded), the setup check with its fixes, `prod.keys`, the library folder and a few choices. Help → Setup Assistant opens it again.
- **Game artwork from the internet**: icons and banners from nlib.cc by title ID, box art from Wikipedia by name for games nlib does not list (Switch 2 games among them), kept on the Mac; the icon in the game's files is the fallback. The game's page shows the banner and the publisher and year; Console Mode uses the banner behind the game.
- A red **Danger Zone** on each game's page: the space each part of the game takes, **Remove…** for the build folder, the apps or the saves, and **Remove Everything…** (also in the sidebar's context menu), to the Trash or deleted for good. A game folder left empty goes too, and a library folder that was only that game leaves the library.
- Before a first build, a **space check** that says what is missing; space held by local Time Machine snapshots can be freed from the dialog.
- **Play time** and last played for each game, Console Mode ordered by last played, a **Switch 2** tag, the free space in the sidebar, and a **notification** when a build ends in the background.
- A dump folder builds without `prod.keys`.
- The setup check counts `zbic` as required: every build needs it (Switch 2 and system 22 games are compressed with it), so a Python without it no longer passes the check and then stops the build.
- **Update checks** at launch, in the AetherNX menu (Check for Updates…) and in a new **menu bar item**: the app's newest release, installed in place after its checksum and Developer ID signature are checked; the tools' new commits, with Update; and nxnative's changes since AetherNX's last sync, with a link. A toolbar button appears while an update is ready.

## 0.1.0

The first release under the AetherNX name.

**AetherNX Studio**, rebuilt from scratch:

- A library sidebar with search, and one page per game: its files (base game, update, DLC), its builds, and Build, Play and More.
- Builds show their real progress (step, progress bar, time left) from the build script's JSON events, can be stopped, and log to an Activity panel.
- Settings (⌘,) in three panes: General, Keys, Building. Choices are kept between launches.
- Keyboard shortcuts for every action, listed in the README.
- **Console Mode**: the library full screen for the couch, driven by a game controller (A plays, B goes back, Y builds again) or the arrow keys, with each game's art behind it and the controller's own button glyphs. ≡ on a controller or ⌃⌘C opens it.
- A setup check that lists what is missing and the command that installs it, and installs the Python packages for you.
- First launch finds the AetherNX tools or downloads them; it no longer depends on one machine's folders.
- English and Italian.
- A new icon, original artwork with no console or controller shapes.
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
