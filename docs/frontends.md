# Front ends

A graphical app can pack games, keep a library and start them using HorizonNative. This page lists the existing contracts: how to run a build and follow its progress, what a built app says about its settings, and how to start a game with them. These interfaces can support a new UI without rewriting the engine. Propose missing events or settings in this repository.

- [Building: the NSP script](#building-the-nsp-script)
- [The settings list](#the-settings-list)
- [Starting a game](#starting-a-game)
- [What a front end cannot see yet](#what-a-front-end-cannot-see-yet)

## Building: the NSP script

`scripts/build_ipa_from_nsp.py <NSP folder>` builds one game: an IPA by default, a Mac app with `--platform mac-app`, at the path `-o` names. Its options are in [The packing script in detail](development.md#the-packing-script-in-detail) and `--help`.

With `--progress json` it asks nothing and writes one JSON object per line on stdout. Every object has `ev` (the event) and `t` (Unix time, seconds):

| `ev` | Fields | When |
|---|---|---|
| `stage` | `k`, `n` (stage k of n), `name`, `step` | a stage starts; `n` can grow during the build (a provisional profile's heap check) |
| `step` | `k`, `name`, `step` | a new step within the stage; its count starts again |
| `progress` | `k`, `name`, `step`, `done`, `total`, `unit` (`''`, `'B'` for bytes, `'files'`, …), `est` (the total is an estimate), `note`, `frac` (0 to 0.99, or `null` when the work cannot be counted), `eta` (seconds or `null`), `elapsed` | the count changes; at most every 0.5 s while only the count moves |
| `stage_end` | `k`, `name`, `ok`, `summary`, `elapsed` | a stage ends |
| `say` | `msg` | a message; one starting with `[RED] ` is an error |

The exit code is 0 for a finished build, 1 for a build that stopped on an error (its last `say` says why, starting with `[RED] `; an unexpected error also prints its traceback on stderr), 2 for invalid command-line arguments, and 130 when interrupted. Argument parsing happens before JSON mode starts: an argument error writes its usage and error to stderr and emits no JSON events. A front end must check the process's exit status and capture stderr as well as the JSON stream. Each tool's full output goes to `<NSP folder>/<title ID>_build/logs/`, not to stdout. The build folder `<title ID>_build/` keeps what the next build can reuse, so a second build after a change takes a fraction of the first.

## The settings list

A built app carries the settings its game supports, as the iPhone app's settings screen shows them ([Settings](settings.md)): `dm/launcher.json` in the app inside an IPA, `Contents/Resources/dm/launcher.json` in a Mac app. The Mac app's list leaves out the settings only the iPhone app reads (the frame-rate counter, touch feedback). `dm/games/settings.py` writes it from `dm/games/settings.tsv`, whose header describes the rows. Breath of the Wild's Mac list, shortened:

```json
{"schema": 1, "game": "01007EF00011E000", "settings": [
 {"env": "DM_FPS_TARGET", "kind": "choice", "section": "Game", "label": "Frame rate", "note": "…", "default": "60",
  "options": [["30", "30 fps"], ["60", "60 fps"]], "level": "basic"},
 {"env": "DM_RENDER_SCALE", "kind": "range", "section": "Game", "label": "Render scale", "note": "…", "default": "1.0", "min": 0.5, "max": 1.0, "step": 0.05},
 {"env": "DM_FPS_HOLD", "kind": "toggle", "section": "Performance", "label": "Hold frames when late", "note": "…", "default": "on", "on": "on", "off": "off"}
]}
```

- `env`: the environment switch the setting sets. `kind`: `choice` (one of `options`, each `[value, label]`), `range` (a number from `min` to `max` in `step`s) or `toggle` (`on` or `off`, the values the switch takes).
- `section`: the heading the row goes under, today `Game`, `Controls` or `Performance`. Sections come in the order of their first rows, and rows in the order to show them. A new section may appear in schema 1: a reader draws a section it does not know like the others, under its name, as the iPhone app does.
- `default`: the value for this app's platform ([Tested defaults](settings.md#tested-defaults)), with profile defaults resolved for its game. A front end that keeps only the choices that differ from it lets a newer build's tested defaults reach the player, as the iPhone app does.
- `base` (optional, render scale only): `{"docked": [w, h], "handheld": [w, h]}`, the 3D views' size that the scale multiplies, so a front end can show 0.75 as 1200×675 docked. It comes from the game's profile (`render_base`), and only some games have it.
- `level` (optional): `basic` marks a setting to show first, for a front end that shows a short list and puts the rest behind a second step. Without it, the front end decides.
- `needs` (optional): `<VAR>=<value>` makes the row a sub-setting of the row that sets `<VAR>`, drawn only while that row has that value (Rumble strength only while rumble is on). A row naming a variable the list does not have stays drawn.
- An app without the file has no settings to offer: start it as it is.

**Compatibility.** [launcher.schema.json](launcher.schema.json) describes the file as a JSON Schema, so a front end can check it and generate its types from it. `schema` is 1, and schema 1 grows only by optional fields: a reader ignores fields it does not know, draws sections it does not know, and a field never changes its meaning. A new `kind` would be schema 2, since a reader cannot draw a kind it does not know. A list written before the field existed has no `schema` and is 1. In `settings.tsv`, the optional fields come from the last column, `meta` (`key=value` pairs separated by `;`); a new key is added in `settings.py`'s `META`, here and in the schema together, and `test_launcher_settings.py` fails when the three disagree.

## Starting a game

**A Mac app** is started like any app, or by running its `Contents/MacOS/HorizonNative` with the chosen settings in its environment (`DM_FPS_TARGET=30`, …). The launcher there runs the host as a child, forwards SIGTERM, SIGINT and SIGHUP to it and exits with its exit code. Once the host has exited the launcher sends the save to the cloud folder, when there is one; a SIGTERM, SIGINT or SIGHUP then ends the launcher itself (the send goes at the next start), and is never forwarded to a process that has already exited. A variable already in the environment wins; then come `~/Library/Application Support/HorizonNative/<title ID>/env.txt` and the bundle's `dm/env.txt`, one `KEY=VALUE` per line ([A Mac app](development.md#a-mac-app)). The save is in `save/` in that Application Support folder; the log is `~/Library/Logs/HorizonNative/<title ID>.log`, the previous run's `<title ID>.prev.log`. The title ID is `DMTitleID` in the app's `Info.plist`.

A Mac app shows its own settings window before the game, drawn from its `launcher.json` and keeping its choices in the same store ([Saved choices](#saved-choices), [The Mac settings window](settings.md#the-mac-settings-window)). It shows a variable the launch environment or an `env.txt` sets as fixed. A `launcher.json` that cannot be decoded is shown as an error in the window, whose Play then starts the game as without the window (saved choices checked against `DMSettings`); an app without the file starts at once, as before. A front end that draws the settings itself starts the app with `DM_LAUNCHER=0` in its environment (or `--no-launcher` on its command line) to skip the window. The saved choices still apply, so a front end that writes them gets the same game as the window would.

Settings a player chose in a front end and wants kept, also for a start from Finder or the Dock, go in the app's saved choices ([Saved choices](#saved-choices)), not in its environment.

**An IPA** is installed by the player (sideloading); its own settings screen starts the game. Lines in the app's `Documents/env.txt` win over that screen ([Settings in a file](settings.md#settings-in-a-file)). The save and `log.txt` are in the app's Documents folder.

## Saved choices

Each app keeps the player's choices in its own preferences domain, its bundle ID (`CFBundleIdentifier` in `Info.plist`, `io.github.icosisenpai.horizonnative.<title ID>` unless the app was packed with another): one string per setting, under the key `launcher.<env>` (`launcher.DM_FPS_TARGET` = `"30"`). The iPhone app's settings screen keeps them there, and a Mac app's launcher (`dm/mac/launcher.c`) reads them at every start, so a start from Finder or the Dock has them too. A front end writes the same keys (`CFPreferencesSetAppValue` with the app's bundle ID, or `defaults write io.github.icosisenpai.horizonnative.<title ID> launcher.DM_FPS_TARGET -string 30`), and a settings window inside the app would too: there is one set of choices, and every view of it agrees.

- **Only choices that differ from the tested default are kept.** A setting the player left at its default follows the defaults of a later build. Remove a key when the player picks the default again. For "Reset to tested defaults", remove the keys of the settings the player can change; the app's own screen does that when Play applies the defaults, and keeps the saved choice of a setting fixed for this start.
- **Checked when read.** The launcher uses a saved value only when this build still offers it: one of a `choice`'s options, a `toggle`'s `on` or `off`, or a number from a `range`'s `min` to `max`. It checks against the app's own list, which the packer copies into `Info.plist` as `DMSettings`. Any other value, a value that is not a string, or a key no setting has is ignored; it stays saved until the settings screen's Play replaces it with the player's choice. So a rebuild that stops offering a value falls back to its tested default.
- **The order**, the first that sets a variable wins:
  1. the launch environment (a front end's launch overrides, a terminal);
  2. the player's `env.txt` (`~/Library/Application Support/HorizonNative/<title ID>/env.txt`; on the iPhone, `Documents/env.txt`), which may come from anyone, so it sets only what `dm/host/env_file.h` allows: `DM_` and `MTL_` switches, not the folders the app sets (`DM_ROMFS`, `DM_SAVE`, `DM_TEMP`, `DM_AOC_DIR` …), and no value with a `/` except `DM_SAVE_SYNC`;
  3. the bundle's `dm/env.txt`;
  4. saved choices;
  5. the tested defaults (the host's own, from the game's profile).
- **Launch overrides are temporary.** A front end that starts the game with a variable in its environment overrides the saved choice for that start only. It writes the store only when the player means to keep the choice.
- **`DM_SAVED_CHOICES=0`** (in the environment or an `env.txt`) starts with the tested defaults and leaves the saved choices as they are. **`DM_LAUNCHER=0`** only skips the settings screen (the iPhone's, or a Mac app's window): the saved choices still apply.
- **A sandboxed front end** cannot write another app's preferences domain; this store is for unsandboxed front ends that integrate with HorizonNative.

### The cloud saves folder

The folder a Mac app's save is synced through ([Cloud saves](settings.md#cloud-saves)) is not a row of the settings list, since a folder is none of its kinds. It has a key of its own in the same store: `cloudSaves.folder`, a string with the folder's absolute path (`defaults write io.github.icosisenpai.horizonnative.<title ID> cloudSaves.folder "$HOME/Library/Mobile Documents/com~apple~CloudDocs/My Saves"`). Remove the key, or write an empty string, to turn cloud saves off. The app's settings window shows and changes the same key, so the player sees the folder a front end chose.

- **Read at every start** by `dm/mac/launcher.c`, with or without the window, and passed on to the host as `DM_SAVE_SYNC`. A change takes effect at the game's next start.
- **The order** is that of the saved choices: `DM_SAVE_SYNC` in the launch environment wins (a folder for this start only, or `0` to start without cloud saves), then an `env.txt`, then this key. `DM_SAVE_SYNC=icloud` is iCloud Drive › HorizonNative Saves.
- **The sync state belongs to one cloud file.** `<DM_SAVE>.sync` records the save last known to be the same here and in the cloud, and since this version the cloud file it was in step with (a `cloud` line). After the folder changes, the next start treats the new folder as a first sync and sends the save there even if it did not change. A state file without the line counts for any folder.
- **One folder serves every game.** Each game keeps its own `<title ID>/save.dmsync` in it, so a front end can write the same path into each app's domain to give its whole library one cloud folder. A path that already ends in the game's title ID is taken as that game's own folder.
- **The iPhone app** keeps its folder as a security-scoped bookmark that only its own folder picker can make, so it is chosen there. Without one, an app signed with an iCloud container (`DM_ICLOUD_CONTAINER`, the maintainer's team) syncs through that container's `Documents` folder ("automatic iCloud", `CloudSaves.h`), which iCloud Drive shows as **HorizonNative**: a Mac front end that writes `cloudSaves.folder = $HOME/Library/Mobile Documents/iCloud~io~github~icosisenpai~horizonnative/Documents` into each Mac app's domain puts the whole library on the same saves. The preference `cloudSavesAutoOff` (a boolean in the iPhone app's own domain) turns automatic iCloud off.

### Add-on content outside the app

`DM_AOC_DIR` may list several folders separated by `:`; the first that holds an index (`<index>.img` or `<index>/`) wins, and the game is told about every index any of them holds. The iPhone app puts its `Documents/aoc` before the DLC packed into it, and a Mac app its `~/Library/Application Support/HorizonNative/<title ID>/aoc`: a front end adds a DLC bought after the app was built by writing its image there (`scripts/push_aoc.sh` does it for an iPhone), with no rebuild. A game update changes the code built into the app and needs a new build.

## The in-game menu (iPhone)

The iPhone app has a menu of its own while the game runs (`dm/ios/Sources/InGameMenu.swift`, [The in-game menu](settings.md#the-in-game-menu)): the touch controls' menu button, a controller's Home button or − and + held together open it, and the game is paused meanwhile (the guest clock's reason 3, `hle_os.c`). Its picture settings act at once through the host's present (`dm_present_set_upscale`, `dm_present_set_sharpen`, `dm_present_set_nearest`, `dm_present_set_stretch` in `nvn_mtl.m`, declared for Swift in `ingame.h`); the next present shows them. It saves the rows the settings list also has under the same `launcher.<env>` keys and by the same rules as the settings screen ([Saved choices](#saved-choices)): only values that differ from the default, nothing for a variable an `env.txt` or the launch environment sets. The touch controls' own options (layout, opacity, size, hidden, each group's position) are kept in the app's defaults as `DmPadLayout`, `DmPadOpacity`, `DmPadScale`, `DmPadHidden` and `DmPadOffsets` (one offset pair per control group, in the layout's units).

## What a front end cannot see yet

While a game runs, the host says what happens only in its log, as text meant for people: a controller that connects or goes away, the preparing of shaders before the first frame, a red line. A front end that reads the log to show these would break when a line's wording changes. Events a program can read (one JSON object per line, as the NSP script's) would be the next piece of this interface; until then, treat log lines as diagnostics, not as an interface.
