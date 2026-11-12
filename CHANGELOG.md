# Changelog

## 1.0.0

A new Studio: one window for everything, a home for your library, mods and cheats, a setup that explains itself, and installs that move only what changed. The engine is the same as in 0.2.0 (nxnative up to `7479adf`): the next nxnative sync comes as an engine update, without a new app.

**One window**

- The sidebar has **Home**, your games, and AetherNX's own pages: **Activity**, **Devices**, **Updates** and **Settings**. Settings is a page of the window (⌘, opens it, as does the gear in the toolbar), not a window of its own; so is the update notice at launch.
- **Home**: the game you played last, large, with Play; tiles for the engine, your keys, your devices, the cloud and updates, each opening its page; and every game in a grid that takes as many columns as the window has room for, on a laptop or a large display.
- **A game's page** uses the width: two columns when the window is wide (what the game is and what was built on the left, saves, mods and cheats on the right), a strip of facts (play time, last session, version, size, what it is built for), and buttons that become icons when the window is narrow.
- **Builds and installs say what they are doing**: "Step 5 of 9", what that step does and why, the step within it, the time left, and the steps already done with their times. When it ends well the card says so for a few seconds and the page goes back to how it was; a failure stays, with what went wrong and **Try Again**.

**Mods and cheats**

- A **Mods** section on each game's page: turn mods on and off, choose which wins when two change the same file, add a mod folder or a .zip, move one to the Trash, or look for mods on GameBanana. No rebuild: they apply at the game's next start. Code mods (exefs) are told apart, since the engine does not run them.
- A **Cheats** section: the game's Atmosphère cheat files and how many cheats each holds, with **Add**; single cheats are turned on and off from the game's Cheats menu while it runs.
- Both folders sit next to the game's save. The new cloud choice **iCloud Drive › AetherNX** gives each game a folder with its name, holding its save, its Mods and its Cheats, so every Mac (and, choosing the same folder there, every iPhone or iPad) sees the same ones.

**Saves**

- The cloud folder panel opens at once, as a sheet in the folder in use, instead of listing the whole of iCloud Drive first.

**Setup**

- The Setup Assistant checks what this Mac needs before anything else (Xcode, its command-line tools, Git, Homebrew, Python), says what each piece is for and why, and installs what it can: **Install with Homebrew**, the Metal toolchain, the Python packages, or **Install Everything Missing** in one go. `./aethernx doctor` explains each missing piece too, and also checks Xcode's license, `afcclient` and your signing certificate.

**Faster installs on iPhone and iPad**

- The game files can stay on the device: **Game files: Automatic** keeps them there when the device is on a cable and `afcclient` is installed (`brew install libimobiledevice`), so installing again copies only the app. Fire Emblem Fortune's Weave's install moved 29 GB, 27 of them its data, at every install.
- The graphics pipelines compile in parallel where the Mac's memory allows (two at a time on 16 GB): Fortune's Weave's took 6 minutes one after the other.

**Updates**

- The Updates page explains the two parts that update apart: the app, from its releases, and the engine, from its repository, in seconds and without a new app. It lists the engine's new changes and says what they mean: a rebuild to get engine fixes, shaders translated again, or nothing to do.

**Install on your iPhone or iPad from the Mac**

- **Install** on a game's page (Build → Install on iPhone or iPad, ⇧⌘I) builds the game, signs it with your own Apple team, free or paid, and installs it on a device paired with the Mac: no Xcode window and no sideloading tool. Installing again keeps the saves and the game files on the device. Settings → **iPhone & iPad** chooses the device, the team, whether the game files stay out of the app (copied once, for games too big to install whole), and for a Mac with no Apple ID in Xcode an App Store Connect API key.
- `./aethernx install <game folder>` does the same from a terminal, and `./aethernx devices` lists the paired devices and the signing teams. A bundle ID that belongs to another team is signed under your team's own and kept; a profile that cannot carry the Increased Memory Limit, or a team without the iCloud container, is signed without it and says so.
- The route follows [NX2Apple](https://github.com/LNPANDY/NX2Apple)'s launcher ([credits](CREDITS.md)).

**Saves**

- A **Saves** section on each game's page: the save on this Mac, the cloud folder its Mac app syncs through with **Change** (iCloud Drive › HorizonNative, iCloud Drive › HorizonNative Saves, another folder, off), when the cloud's copy last changed and what the last session said about the sync.
- Settings → General → **Cloud saves** sets one folder for the whole library; a game with a choice of its own keeps it.

**Also**

- **Make Bug Report…** (a game's More menu, and Help) and `./aethernx report <game folder>`: the game's logs, versions and settings in one zip on the Desktop, never any game data.
- `scripts/push_aoc.sh` sends add-on content over AFC, as `push_romfs.sh` sends the game's image: a DLC as large as a game no longer goes through the Mac's memory, an image is renamed into place only once the device holds all of it, and the DLC already on the phone stay.
- [The Increased Memory Limit](docs/playing.md#the-increased-memory-limit): which ways of installing keep it, and how to read from `log.txt` whether it took effect.

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
