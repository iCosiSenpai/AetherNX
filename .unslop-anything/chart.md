# Chart

Stack: SwiftUI (Swift 5 mode), Xcode 27.2: AetherNX Studio (macOS 26+, `studio/`), AetherNX Companion (iOS/iPadOS 26+, `companion/`), each game's launcher (iOS/iPadOS and macOS, `dm/ios/Sources`, `dm/mac`); the website is plain HTML and CSS (`site/`)
Platforms: Mac (Studio, game launchers), iPhone and iPad (Companion, game launchers), web (site)
Visits: on

Written on 2026-11-28 from PRODUCT.md, DESIGN.md and the code, without the owner's answers to the chart's four questions: the lines below marked "inferred" are guesses to confirm.

## Top tasks
1. Studio: add a game, build it for the Mac or install it on an iPhone or iPad, and play it (Home, a game's page)
2. Studio: keep saves, mods and cheats in step across devices (a game's page: Saves, Mods, Cheats)
3. Companion: see the library's saves, mods and cheats on the phone, and follow or ask for an install from the Mac (Library, a game, Mac)
4. A game's launcher: start the game with the settings it was tested with (the launcher screen, DESIGN.md)

## Users and context
People who own Switch games and build them for their own Apple devices, at a Mac desk (Studio) or holding a controller in landscape (the launchers). Inferred: technical enough to have dumped their games, not developers.

## Brand
- Color: Studio and the Companion follow the system accent; the app icon is a silver "A" on deep navy with cyan and violet light (`assets/AppIcon.icns`, `assets/aethernx-logo.png`)
- Type: system type only (SF Pro); the website uses Mona Sans (`site/fonts`)
- Keep: each game's launcher wears its own icon's colour (DESIGN.md, "One derived tint per game")

## Accepted
- status-dot in `dm/ios/Sources/LauncherRow.swift` and `InGameMenu.swift`: the 7 pt tint dot marks a changed value, by design (DESIGN.md); inferred, 2026-11-28
- slop-gradient in `studio/Sources/ConsoleView.swift`: the navy-to-indigo fallback behind a game with no artwork follows the app icon's navy; inferred, 2026-11-28
- slop-gradient in `companion/Sources/App/WelcomeView.swift` (`AppMark`): the companion's drawn mark; ask the owner before changing it; inferred, 2026-11-28
- sparkle-icon `wand.and.stars` for cheats (Studio, Companion): a cheat is the "magic" here, and the same symbol is used everywhere for it; inferred, 2026-11-28
- fixed-text-size in `studio/Sources`: macOS has no Dynamic Type for these views; the sizes are glyphs and the Home title; inferred, 2026-11-28

## Off limits
- The launchers' C entry points and settings contracts (PRODUCT.md, "Capabilities and Constraints")
