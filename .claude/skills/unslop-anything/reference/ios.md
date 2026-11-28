# iOS and iPadOS

For anything that ships to Apple hardware: SwiftUI, UIKit, and cross-platform stacks on iPhone and iPad.

The question for every screen: would someone who has used an iPhone for ten years trust this, or stop at a control that is almost right?

## Structure

- Tab bar for two to five top-level sections. Tabs are places, never actions. No hamburger for the main destinations.
- Navigation stack for drilling in. Large titles on top-level screens, collapsing on scroll; inline titles deeper in.
- Sheets for short, self-contained tasks, with detents where a partial height makes sense. Full-screen covers for immersive flows only.
- Edge-swipe back always works. A custom back button must not cost the gesture.
- Safe areas respected: nothing tappable under the Dynamic Island, the home indicator, or the rounded corners.

## Controls

- System controls before custom ones: `Toggle`, `Picker`, segmented control, `Stepper`, `Menu`, context menus, swipe actions, confirmation dialogs.
- SF Symbols for icons, at the text style's weight and scale. Do not mix in a web icon set.
- Destructive actions use the destructive role and ask for confirmation only when the loss is real.
- Settings-shaped content goes in an inset grouped `List`, not a stack of cards.

## Type and color

- Dynamic Type through text styles (`.largeTitle` to `.caption2`). Custom fonts scale with `relativeTo:` or `UIFontMetrics`.
- SF Pro carries body, labels, and controls. A brand face is for display moments.
- Semantic colors (`label`, `secondaryLabel`, `systemBackground`, `separator`, the tint). Raw hex breaks in dark mode and increased contrast.
- One tint for interactive elements. It is not decoration.
- System materials behind bars and sheets. Content surfaces stay opaque.

## Motion and feedback

- System transitions: push, sheet, dismiss in reverse. Custom transitions that fight the navigation model disorient.
- Reduce Motion replaces slides and parallax with a crossfade.
- Haptics through `.sensoryFeedback` or `UIFeedbackGenerator`, for confirmations and selection changes, not every tap.

## Checking it

- Run on the Simulator: `xcrun simctl io booted screenshot <file>.png`. With several booted, use the device UDID from `xcrun simctl list devices booted`.
- Dark mode: `xcrun simctl ui booted appearance dark`.
- Largest text: `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`. Reset with `large` afterward.
- Check one small iPhone (SE size) and, if iPad is a target, one iPad in Split View.
- The Simulator is fine for layout. Gestures, haptics, and performance need a device. Say which you used.
