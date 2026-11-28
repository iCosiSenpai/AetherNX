# Stacks

Native building blocks per stack. Prefer these to custom replacements. A cross-platform app still owes each platform its own guarantees: read [ios.md](ios.md) and [android.md](android.md) for the ones it ships to.

| Stack | Navigation | Lists and refresh | Sheets | Polish |
|---|---|---|---|---|
| SwiftUI | `NavigationStack`, `TabView` | `List`, `.swipeActions`, `.refreshable` | `.sheet` with `.presentationDetents` | SF Symbols, `.font(.body)` styles, `ContentUnavailableView`, `.sensoryFeedback` |
| UIKit | `UINavigationController`, `UITabBarController` | `UICollectionView` lists, `UIRefreshControl` | `UISheetPresentationController` | SF Symbols, `preferredFont(forTextStyle:)`, `UIContentUnavailableConfiguration` |
| Jetpack Compose | `Scaffold`, `TopAppBar`, `NavigationBar`, `NavigationSuiteScaffold` | `LazyColumn` with `key`, `PullToRefreshBox` | `ModalBottomSheet` | `MaterialTheme.typography`, `WindowInsets.safeDrawing`, `Modifier.imePadding()` |
| React Native, Expo | Native stack, native tabs where available | `FlatList` or FlashList, `RefreshControl` | Native modal presentation (`presentation: 'formSheet'`) or a sheet library already in the project | `Pressable`, `react-native-safe-area-context`, `KeyboardAvoidingView`, `expo-haptics` |
| Flutter | `NavigationBar`, `CupertinoTabBar`, platform page routes | `ListView.builder`, `RefreshIndicator`, `CupertinoSliverRefreshControl` | `showModalBottomSheet` | `Theme.of(context).textTheme`, `SafeArea`, `.adaptive` constructors, `HapticFeedback` |
| Angular Native | Its native stack and tabs | Its virtualized native list | Its native modal presentation | It renders on React Native's Fabric, so apply the React Native row through the project's Angular components |
| NativeScript Angular | `page-router-outlet`, `ActionBar`, `TabView` | `ListView` | `ModalDialogService` | `iosOverflowSafeArea`, platform text styles, no web-style hover |
| Ionic, Capacitor | `ion-tabs`, `ion-nav` or the framework router, `ion-header` | `ion-list`, `ion-refresher`, virtual scrolling for long lists | `ion-modal` with breakpoints | Platform `mode`, `env(safe-area-inset-*)`, `@capacitor/haptics`, no hover-only behavior |

## Stack-specific tells

**React Native and Expo**
- `TouchableOpacity` everywhere with the default fade and no other pressed state; prefer `Pressable` with a real pressed style.
- `Alert.alert` used for every error, success, and confirmation.
- One shared `SafeAreaView` at the root that leaves headers or tab bars double-padded or under the notch.
- A JS tab bar or stack that recreates native ones and loses the native feel.
- Expo template leftovers: the default tint, the `ParallaxScrollView` and `HelloWave` from the starter screens, `ThemedText` with no real type scale behind it.

**Flutter**
- Material widgets on iOS where `.adaptive` constructors or Cupertino equivalents exist.
- `Colors.deepPurple` still the seed color from `flutter create`.
- `WillPopScope`, which is deprecated and breaks predictive back; use `PopScope`.
- Fixed `TextScaler` or clamped scaling to stop overflow instead of fixing the layout.

**Ionic and Capacitor**
- `mode="md"` forced on iOS, or `mode="ios"` forced on Android, without a brand reason.
- Desktop CSS: hover states, wide max-widths, multi-column grids on a phone.
- Missing `viewport-fit=cover` and safe-area insets, so headers sit under the notch.

**Compose and SwiftUI**
- Previews full of invented data that ships as the real empty state.
- A `Card` or rounded `RoundedRectangle` background on every row instead of a list.
