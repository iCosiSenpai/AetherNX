# Performance

Bugs, lag, and crashes together are the biggest group of complaints in low-rated app reviews: about a third on the App Store and two fifths on Google Play, more than everything a design pass can fix. A design review cannot measure them. So this file does two things: it lists what you can catch in code, and it makes sure the report never implies a clean bill of health it did not earn.

## The rule

Performance is never scored from code alone. Every report carries a Performance line:

- `Not profiled.` plus the static leads you found, when you only read code. This is the default.
- `Profiled on <device or emulator>, <build type>, with <tool>:` plus the numbers, when you actually measured.

Simulators and debug builds are not evidence of speed. Say which one produced the number.

## What code can show

These are leads. Report them under Noticeable with "suspected", not as measured problems.

**Lists**
- Items mapped inside a plain scroll container instead of a virtualized list [`unvirtualized-list`]
- React Native `FlatList` without `keyExtractor`, with inline `renderItem` closures re-created every render, or with `getItemLayout` missing on fixed-height rows; FlashList without `estimatedItemSize` on older versions
- SwiftUI `List` or `ForEach` over a collection without stable identity (`id: \.self` on mutable values)
- Compose `LazyColumn` `items` without `key`, or unstable lambdas and collections causing recomposition of every row
- Flutter `ListView(children:)` with many children instead of `ListView.builder`

**The main thread**
- JSON parsing, sorting, filtering, or image processing in a render, `body`, composable, or `build` method
- Synchronous storage reads (`AsyncStorage` in a loop, `UserDefaults` of large blobs, `SharedPreferences` commit on the main thread)
- Network or database calls started from view construction instead of a task or effect

**Images**
- Full-size remote images shown as thumbnails with no resizing or caching library already in the project
- Large images bundled as PNG where the platform asset catalog or vector would do

**Startup**
- Every SDK initialized before the first frame
- Fonts, remote config, and analytics blocking the first screen

**Web**
- `<img>` without `width` and `height` or an aspect ratio, so the page jumps as images load
- Hero images not preloaded, or every image loaded eagerly
- Web fonts blocking text with no `font-display`, or four families and weights where one would do
- Client components and large libraries shipped for content that could render on the server
- Layout read and written in the same frame inside scroll handlers

**Animation**
- JS-driven animations on React Native where the native driver or Reanimated is available
- Layout animations on every list row

## How to profile, per stack

Only when the user wants it and you can run the app. Use release or profile builds on a physical device where possible.

| Stack | Tool | What to read |
|---|---|---|
| SwiftUI, UIKit | Instruments: Time Profiler, Hangs, SwiftUI template | Hangs over 250 ms, view body counts, main-thread time during scroll |
| Compose, Android Views | Android Studio Profiler, Macrobenchmark, `adb shell dumpsys gfxinfo <package>` | Janky frames percentage, startup time, recomposition counts in Layout Inspector |
| React Native, Expo | Perf Monitor, React DevTools profiler, Flashlight on Android | JS and UI thread FPS while scrolling, commit durations |
| Flutter | DevTools Performance view in profile mode | Frame build and raster times over 16 ms, shader jank |
| Ionic, Capacitor | Safari Web Inspector or Chrome DevTools against the device WebView | Long tasks, layout shifts, scroll FPS |
| Web | Lighthouse in a production build, the DevTools Performance panel with CPU throttling, field data from the Chrome UX Report when the site has traffic | LCP, INP, and CLS; long tasks over 50 ms; bundle size per route |

## What to write

Under Noticeable, for each lead: the file and line, what is suspected, and the fix. Under Not checked, always: "Performance not profiled" unless you did. If the user asked about performance specifically and you could not profile, say so in the verdict line instead of burying it.
