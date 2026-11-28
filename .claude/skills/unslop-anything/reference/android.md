# Android

For anything that ships to Android: Jetpack Compose, Android Views, and cross-platform stacks on phones, tablets, and foldables.

The question for every screen: would a long-time Android user trust this, or trip on an iPhone app wearing a Material costume?

## Structure

- Navigation bar for three to five top destinations on phones; navigation rail or a permanent drawer on wide windows. Do not stretch the phone layout across a tablet.
- System Back always works and predictive back previews where it lands. Intercept Back only to guard real data loss, with `OnBackPressedCallback` or `BackHandler`, never `onBackPressed`.
- Edge to edge with window insets: status bar, navigation bar, display cutout, and the IME (`WindowInsets.safeDrawing`, `Modifier.imePadding()`).
- Top app bar for screen context. One FAB, only when the screen has one clear primary action.

## Controls

- Material 3 components: filled, tonal, outlined, and text buttons; chips; switches; snackbars; bottom sheets; dialogs only for decisions that must interrupt.
- Snackbars for transient feedback, with an action when undo makes sense.
- Material Symbols for icons, one style throughout.
- No iOS-shaped switches, action sheets, or back chevrons on Android.

## Type and color

- The Material type scale (display, headline, title, body, label). Sizes in `sp` so text follows the user's font size.
- Color roles (`primary`, `onPrimary`, `surface`, `surfaceContainer`, `outline`, `error`), never raw hex in components.
- Dynamic color where it fits the brand, with a static fallback scheme.
- Dark theme designed, not inverted. Elevation through tonal surfaces.
- If `Color.kt` still holds `Purple40` and `Purple80` from the project template, the app has no color decisions yet.

## Motion and feedback

- Material motion: container transform, shared axis, fade through. Honor "Remove animations".
- Haptics through `HapticFeedbackConstants` or `LocalHapticFeedback`, for confirmations and long presses.

## Checking it

- Screenshot from an emulator or device: `adb exec-out screencap -p > <file>.png`. With several attached, add `-s <serial>`.
- Dark theme: `adb shell cmd uimode night yes`.
- Large text: `adb shell settings put system font_scale 2.0`. Read the old value first with `adb shell settings get system font_scale` and restore it afterward.
- Check a small phone, and a tablet or foldable if the app supports them.
- Emulators are fine for layout. Gestures, refresh rate, and performance need hardware. Say which you used.
