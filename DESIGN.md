---
name: HorizonNative Launcher
description: The pre-game settings screen as the game's own product card, native SwiftUI on iPhone, iPad and Mac.
colors:
  tint-fallback-accent: "#0A84FF"
  ground-dark: "#000000"
  cell-dark: "#1C1C1E"
  ground-mac-light: "#FFFFFF"
  label-dark: "#FFFFFF"
  label-secondary-dark: "rgba(235, 235, 245, 0.6)"
  separator-dark: "rgba(84, 84, 88, 0.65)"
  warning-orange: "#FF9F0A"
  destructive-red: "#FF453A"
  on-tint: "#FFFFFF"
typography:
  title:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "28pt"
    fontWeight: 700
  value:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "20pt"
    fontWeight: 600
    fontFeature: "tnum"
  headline:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "17pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "17pt"
    fontWeight: 400
  subheadline:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "15pt"
    fontWeight: 400
  footnote:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "13pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "12pt"
    fontWeight: 400
rounded:
  nav-icon: "6pt"
  control-mac: "8pt"
  strip-cell: "10pt"
  row: "12pt"
  app-icon: "22.5%"
  capsule: "9999pt"
spacing:
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "14pt"
  xl: "16pt"
  xxl: "20pt"
components:
  button-play:
    backgroundColor: "{colors.tint-fallback-accent}"
    textColor: "{colors.on-tint}"
    typography: "{typography.value}"
    rounded: "{rounded.capsule}"
    padding: "0 18pt"
    height: "44pt"
  button-play-compact:
    backgroundColor: "{colors.tint-fallback-accent}"
    textColor: "{colors.on-tint}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
  summary-cell:
    textColor: "{colors.label-dark}"
    typography: "{typography.value}"
    rounded: "{rounded.strip-cell}"
    padding: "10pt 12pt"
    width: "84pt"
  setting-row:
    backgroundColor: "{colors.cell-dark}"
    textColor: "{colors.label-dark}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
  app-icon-header:
    rounded: "{rounded.app-icon}"
    size: "96pt"
---

# Design System: HorizonNative Launcher

## Overview

**Creative North Star: "The Game's Own Product Card"**

The launcher is a store-style product card for one game: its icon, name and version with Play at the top, an information row stating what Play will start with, then the grouped settings those facts come from. Everything else is Apple's own material: system type, inset-grouped lists on iPhone and iPad, a grouped Form on the Mac, system controls, system hairlines. The game's icon is the only image on the surface, and it lends the only brand colour.

The system is quiet by construction. Colour is derived, not designed: each launcher computes its tint from its icon at run time, so no two games look the same and no brand palette exists to drift. The tint carries meaning (Play, a changed value, the controller's focus) and nothing else. Density follows the platform: generous 17 pt rows on touch, compact 13 pt rows on the Mac, both reflowing whole rather than clipping.

The iPhone and iPad screen is always dark, because the game starts on black and a light screen would flash before it. The Mac window follows the system appearance.

**Key Characteristics:**
- One derived tint per game, bounded by WCAG luminance, falling back to the system accent.
- System type only, with tabular figures on every value.
- A hairline-divided summary strip that is one controller stop and never scrolls sideways.
- Changed values marked by a 7 pt tint dot; fixed values by a lock and their source.
- A 3 pt tint focus ring drawn outside the control, shown only once a controller is used.

## Colors

A system-neutral palette with one borrowed accent: the game icon's dominant hue, adjusted to pass contrast.

### Primary
- **Game Tint** (derived per game; falls back to the system accent `tint-fallback-accent`): the icon is drawn at 24 × 24, saturated and not-too-dark pixels vote for one of 18 hues weighted by saturation × brightness, and the winning hue's average colour is taken when it covers more than 3% of the icon's weight. It splits into two roles:
  - **Fill**: the hue scaled towards black until its relative luminance is at most 0.17, so white text on it reaches at least 4.77:1. Fills the Play capsule and the compact toolbar Play. It is the same tone in light and dark appearance.
  - **Mark**: the dark tone in light appearance; in dark appearance, the hue mixed with white until its luminance is at least 0.32 (about 6:1 on the dark grouped cell). Used for the changed-value dot and the focus ring.
- **System Accent fallback** (`tint-fallback-accent`, the dark-appearance system blue): used for both roles when the icon is grey, missing or unreadable. Review captures with the sample icon show this fallback.

### Neutral
- **Black Ground** (`ground-dark`): the iPhone/iPad page behind the grouped list; also the ground of the header and strip, which sit on no cell.
- **Grouped Cell** (`cell-dark`): the inset-grouped section background on iOS (system secondary grouped background).
- **Mac Ground** (`ground-mac-light`, system text background): set behind the whole Mac window, header and footer included, so the grouped Form's ground runs edge to edge. It adapts to dark appearance.
- **Label / Secondary Label** (`label-dark`, `label-secondary-dark`): primary text and every secondary line (version, captions, notes, readouts, picker values, slider end labels).
- **Separator** (`separator-dark`): the strip's vertical hairlines and the icon's 0.5 pt outline.

### Status
- **Warning Orange** (`warning-orange`, system orange): the triangle and text of an invalid-value notice, and the icon of an unreadable settings list. Never decorative.
- **Destructive Red** (`destructive-red`, system destructive role): iOS "Turn Off Cloud Saves" only.

### Named Rules
**The Borrowed Tint Rule.** The launcher has no colour of its own. Its accent is computed from the game's icon and clamped to luminance bounds (fill ≤ 0.17, dark-appearance mark ≥ 0.32); never hard-code a hue.

**The Tint Means Something Rule.** The tint appears on Play, on a changed-value dot and on the controller focus ring. Picker values are deliberately set to secondary so a menu's value never reads as "changed".

## Typography

**Display Font:** SF Pro (system), via text styles only
**Body Font:** SF Pro (system)
**Label/Mono Font:** none; figures use the system font's monospaced digits

**Character:** Entirely Apple's text styles, so Dynamic Type scales every line. The hierarchy comes from weight and grouping, not from size jumps.

### Hierarchy
Sizes are iOS defaults at the Large content size; on the Mac the same styles resolve smaller (title 22, title3 15, body 13).
- **Title** (bold, title style, 28 pt): the game name in the header; wraps up to three lines and carries the header trait.
- **Value** (semibold, title3, 20 pt, tabular): summary-strip values and the large Play label.
- **Headline** (semibold, 17 pt): the game name in the compact navigation bar; compact Play is semibold body.
- **Body** (regular, 17 pt): setting labels, picker and toggle rows, list buttons.
- **Subheadline** (regular, 15 pt, secondary): "Version x.y.z" under the title.
- **Footnote** (regular, 13 pt): row notes and lock sources, section footers, pad hints, invalid-value help. The Mac uses callout for its notices.
- **Caption** (regular, 12 pt, secondary): strip captions and slider end labels; caption2 sizes the strip's lock glyph.

### Named Rules
**The Tabular Value Rule.** Every value that can change (strip values, row readouts, slider ends, available memory) uses monospaced digits and a numeric content transition, so changing a value never shifts its neighbours.

## Layout

**iPhone / iPad.** Full-screen, forced dark, one inset-grouped List with compact section spacing. Content sits in a readable column at most 820 pt wide, centred, with at least 12 pt side margins; 820 pt is wide enough for the whole strip on one line on an iPad. Order: header (insets 12 top, 4 sides and bottom, on the bare ground), summary strip (no insets, bare ground) with the pad hint as its footer, an optional problem notice, one section per settings section, Reset to Tested Defaults with its footer (and live available memory), then Cloud Saves. Header icon: 96 pt, or 76 pt when the vertical size class is compact (phone landscape).

**Header reflow.** Icon, titles and Play sit in one row (16 pt gaps) with Play at its natural width; a long name wraps beside Play instead of pushing it down. Play drops below the icon and titles (14 pt gaps) only when the header is narrower than 520 pt (400 pt on the Mac) or the text is at an accessibility size.

**Navigation bar.** Inline and transparent until the content has scrolled 110 pt; then the bar becomes visible, the centre takes a 26 pt icon (6 pt corners) with the name, and the trailing edge a compact tinted glass Play. The items are absent, not hidden by opacity, before that point.

**Mac window.** 560 × 660 pt to start, minimum width 520 pt, placed at the top centre of the screen; the height follows the Form's content up to the visible screen. Header (64 pt icon) padded 20 pt on the sides and top, 12 pt below; strip padded 8 pt; a full-width divider; the grouped Form (basic settings, Advanced settings disclosure, Cloud Saves, Reset, which is always present); a divider; a footer bar (20 pt sides, 14 pt vertical) with "Show this window at launch" and Quit.

**Summary strip.** One line when every cell fits at its natural width, spare width going between cells around each hairline. Otherwise a grid of equal columns, as few lines as cells of at least 120 pt allow, cells spread evenly (seven cells in 520 pt give 4 + 3), 8 pt between lines, values allowed two lines, cells bottom-aligned so captions stay level. 8 pt padding all round leaves room for a focus ring. The strip never scrolls sideways.

**Spacing rhythm.** 4, 8, 12, 14, 16 and 20 pt recur; 3, 5, 6 and 7 pt are the tight internal gaps of labels, dots and notes.

### Named Rules
**The Whole Row Rule.** Rows reflow, they are never clipped: a range or invalid row's label and readout sit side by side when they fit and stack when they don't, notes wrap at full height, and the header stacks Play rather than truncating the name.

## Elevation & Depth

Flat. No custom shadows anywhere. Depth comes from the platform's own materials: grouped cells over the ground on iOS, the grouped Form on the Mac, the navigation bar's material once it becomes visible, and Liquid Glass on the compact toolbar Play. The header and strip deliberately sit on the bare ground, not in a cell, so they read as the page rather than as a setting.

## Shapes

Continuous (squircle) corners throughout. The app icon is clipped to 22.5% of its size (21.6 pt at 96 pt) with a 0.5 pt separator outline; a missing icon is replaced by a quaternary-filled tile of the same shape with a game-controller symbol. Play is a capsule on both platforms. Focus rings follow the control: a capsule around Play, 12 pt corners around iOS rows and cloud buttons, 10 pt around strip cells, 8 pt around Mac buttons and the Advanced disclosure, 6 pt around the Mac checkbox. Markers are small and round: a 7 pt tint circle for changed, a filled lock for fixed.

## Components

### Play Button
- **Shape:** capsule, bordered-prominent, large control size.
- **Primary (iOS):** game tint fill with white "Play" and a filled play symbol, value style, 18 pt horizontal padding, at least 44 pt tall. **Mac:** body-size label, 10 pt horizontal padding, at least 24 pt tall.
- **Keyboard:** the default action (Return) on both platforms.
- **Focus:** the capsule focus ring. In inactive Mac windows the system renders it grey; that is the platform, not a state of the system.
- **Compact:** in the iOS navigation bar after scroll, a tinted prominent-glass "Play" in semibold.

### Summary Strip Cell
- **Style:** no background; value (value style, centred, tabular) over a secondary caption; 10 pt vertical × 12 pt horizontal padding; at least 84 pt wide; separated by hairlines inset 12 pt top and bottom.
- **States:** changed adds a 7 pt tint dot before the value; locked adds a secondary lock instead (lock wins); a range setting shows its percentage here (the row shows pixels). Pointer hover uses the system highlight on iPad.
- **Action:** selecting a cell moves focus to its setting (or Cloud Saves) and scrolls it to centre.
- **Accessibility:** one element, label = caption, value = value plus ", fixed" or ", changed from the tested default", hinted as showing the setting.

### Setting Row
- **Kinds:** choice (menu picker, value in secondary), range (label and live readout, then the slider between its percentage end labels; the readout gives pixel size and percentage when the list has a base size), toggle (system switch; checkbox style is used only for the Mac's "Show this window at launch").
- **Changed:** a 7 pt tint dot before the label; a context menu offers "Use tested default (value)".
- **Locked:** a secondary lock before the label, the control disabled, and the note extended with its source ("Set by an env file" or "Set at launch").
- **Invalid:** a locked value the build does not offer shows no control; the label and the raw value as readout, then an orange warning label saying where to change it and which values it accepts.
- **Focused:** the 3 pt tint ring with 12 pt corners, drawn 6 pt outside the row so nothing moves.

### Lists and Sections
- **iOS:** inset-grouped List, compact section spacing, system section headers and footers. Reset to Tested Defaults is a plain list button, disabled until a value changed.
- **Mac:** grouped Form. Advanced settings is a disclosure whose rows appear in their own sections above it; its open state is remembered, and focusing a hidden row opens it. Reset is always present and disabled until something changed.

### Cloud Saves Section
- Folder as labelled content (secondary value, truncated in the middle on iOS and at the head on the Mac, iCloud Drive paths shown as "iCloud Drive › …" on the Mac); a choose button; a turn-off button when a folder is set. When an env file or the launch fixes the folder, the buttons are replaced by a footnote lock label naming the source.

### Controller Navigation (signature)
- **Order:** Play, the strip (one stop, re-entered at the cell last used), every visible row in section order, then Advanced (Mac), Cloud Saves and its turn-off, Reset (when something changed; on the Mac it comes after Cloud Saves), and on the Mac the launch checkbox and Quit.
- **Input:** polled every 16 ms so the game's own handlers stay untouched. Up/down move between stops; left/right move along the strip or step the focused value; A activates (steps a choice to its next value, flips a toggle, does nothing on a range, opens the folder picker on Cloud Saves); B returns to Play; Menu plays from anywhere. A held direction repeats after 0.4 s at about 11 per second.
- **Visibility:** no focus is drawn until a controller is used; the focused item scrolls to centre.
- **Pad hint:** once a controller is used, a footnote line "Choose · Back to Play · Play" with the connected controller's own button symbols.

### Motion
- Navigation-bar reveal, scroll-to-focus and the Mac's scroll after toggling Advanced use ease-out over 0.2 s; with Reduce Motion they jump with no animation.
- Values change through the system numeric-text content transition.
- Play dismisses the iOS screen without animation, so the game starts straight away.

## Do's and Don'ts

### Do:
- **Do** derive the tint from the game icon through the luminance bounds (fill ≤ 0.17, dark-appearance mark ≥ 0.32), falling back to the system accent.
- **Do** mark a changed value with the 7 pt tint dot, in the strip and in the row, and a fixed one with a lock and its source.
- **Do** use system text styles only, with monospaced digits on every value.
- **Do** draw controller focus as a 3 pt tint ring 6 pt outside the control, matching its shape, and only after a controller has been used.
- **Do** let the strip wrap into equal columns and rows stack before anything is clipped or scrolls sideways.
- **Do** gate every animation on Reduce Motion.
- **Do** keep Reset to Tested Defaults one action away, disabled until something changed.

### Don't:
- **Don't** tint picker values, section headers or secondary text; the tint is for Play, the changed dot and focus.
- **Don't** add a second accent, gradients, custom shadows or decorative imagery; the game's icon is the only image.
- **Don't** give the iPhone/iPad screen a light appearance; it stays dark before a game that starts on black.
- **Don't** hide the toolbar's Play by opacity; add the item only once the header has scrolled away.
- **Don't** show a control for an invalid fixed value; show the raw value and the way out.

## Accessibility

Built in: Dynamic Type through text styles, with the header stacking at accessibility sizes; VoiceOver labels, values and hints on strip cells, Play and sliders, with decorative dots, locks, slider end labels, icons and focus rings hidden; WCAG luminance bounds on the tint (white on fill ≥ 4.5:1, mark ≥ 3:1 on its surface); full keyboard (Return plays, Escape quits on the Mac) and controller reach; Reduce Motion respected for scrolling and the navigation bar.

Not yet verified on device: a full VoiceOver pass on both platforms; accessibility text sizes in iPhone landscape beyond the stacking capture; a physical controller on iPhone and Mac (focus captures used a debug switch); the outline contrast of a dark tint-fill capsule against the black iOS ground (its label contrast is guaranteed, its edge is not); whether the numeric-text transition calms under Reduce Motion.
