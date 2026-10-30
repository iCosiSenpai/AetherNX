# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

The launcher ships as two native SwiftUI surfaces sharing one model (`dm/ios/Sources/LauncherSettings.swift`): the iPhone/iPad settings screen shown before the game, and the Mac app's settings window. Both follow Apple's platform conventions (iOS/iPadOS 26 and macOS 26 or later).

## Users

Players who own a Nintendo Switch game and have packed it themselves into an iPhone/iPad IPA (sideloaded) or a Mac app with `scripts/build_ipa_from_nsp.py`. They open the game's own app; the launcher is the first thing they see each time, before the game takes the whole screen. Many hold a game controller, often in landscape, sometimes with the device docked to a display.

## Product Purpose

Start the player's game with the settings they chose. Before each start the launcher shows which game this is, lets the player start it at once, and lets them change the settings the game's profile offers (frame rate, render scale, controls, performance switches) and the cloud-saves folder shared between the Mac and the iPhone. Success: the player recognises the game, trusts what will happen when they press Play, and can adjust a setting without hunting for it.

## Positioning

Each launcher belongs to one game: the game's own name, icon and tested defaults, not a library or emulator front end. Settings are the ones this game's build was tested with; a value set by an env file or a front end's launch is shown fixed, with where it came from.

## Operating Context

- Shown full screen on iPhone/iPad (portrait or landscape, any size from a small iPhone to a large iPad) and as a window on the Mac.
- Input: touch, Mac pointer and keyboard, and game controllers. Controller navigation is essential: every control must be reachable and operable with a pad, with a visible focus, and Play reachable directly.
- Identity, Play and settings carry equal weight on the screen.
- Settings come from `launcher.json` (schema in `docs/launcher.schema.json`): kinds `choice`, `range`, `toggle`; sections (`Game`, `Controls`, `Performance`, others may appear); optional `level: basic`, `needs` sub-settings, `base` size for the render scale.

## Capabilities and Constraints

- Contracts in `docs/frontends.md` and `docs/settings.md` must hold: only choices that differ from the tested default are saved (`launcher.<VAR>` in the app's preferences), reset forgets them only when Play applies, precedence launch environment > env.txt > bundle env.txt > saved choices > tested defaults, `DM_LAUNCHER=0` skips the screen, `DM_SAVED_CHOICES=0` ignores saved choices.
- C entry points `dm_show_launcher` (iOS) and `dm_mac_launcher` (Mac) and the cloud-saves functions in `CloudSaves.h` stay as they are.
- Strings are English (project rule); no localisation exists yet.
- The Mac window is measured in `dm/ios/tests/launcher_layout_check.swift`; the model in `launcher_storage_check.swift`.

## Brand Commitments

Product name HorizonNative (maintainer iCosiSenpai). No logo or brand palette exists; each launcher wears its game's own icon and name. Nothing from any game is shipped in the repository.

## Evidence on Hand

No screenshots of the current launcher are committed. Game gallery images in `docs/images/` belong to the README and are not shipped in apps.

## Product Principles

1. The game comes first: the player always knows which game and which version they are about to start.
2. Nothing hidden about what Play will do: fixed values, overrides and cloud-save state are shown with their source.
3. Every control works with touch, pointer, keyboard and a game controller alike.
4. Tested defaults are a safe place to return to, one action away.

## Accessibility & Inclusion

Dynamic Type up to the accessibility sizes, VoiceOver labels and values on every control, sufficient contrast in light and dark appearance, and full controller/keyboard focus navigation.
