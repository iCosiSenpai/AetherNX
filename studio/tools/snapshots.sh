#!/bin/bash
# Pictures of AetherNX Studio's pages (studio/tools/snapshots.swift), into docs/images/studio/ by default: the app's sources as a library, then the program.
#   studio/tools/snapshots.sh [output folder] [light|dark] [width] [height]
set -euo pipefail
studio="$(cd "$(dirname "$0")/.." && pwd -P)"
root="$(cd "$studio/.." && pwd -P)"
out="${1:-$root/docs/images/studio}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
target=arm64-apple-macos26.0
xcrun swiftc -emit-library -enable-testing -parse-as-library -swift-version 5 -target "$target" -module-name AetherNXStudio -emit-module \
  -emit-module-path "$work/AetherNXStudio.swiftmodule" "$studio"/Sources/*.swift "$root/dm/ios/Sources/CloudFolders.swift" \
  "$root/companion/Sources/Core/LinkWire.swift" "$root/companion/Sources/Core/LinkTransport.swift" -o "$work/libAetherNXStudio.dylib"
# A version of its own (no bundle ID: it must not write into the app's preferences), the release before this one, so the Updates page shows an update
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>\n' "${SNAPSHOT_VERSION:-0.2.0}" > "$work/Info.plist"
xcrun swiftc -swift-version 5 -target "$target" -I "$work" -L "$work" -lAetherNXStudio -Xlinker -rpath -Xlinker "$work" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$work/Info.plist" "$studio/tools/snapshots.swift" -o "$work/snapshots"
# The app's string tables beside the program, as the app has them in its bundle: the scan then knows a game folder's note under its name in every
# language (GameExtras.noteNames). Without them this program, always in English, wrote "Read me.txt" beside the note of a Studio in another language.
cp -R "$studio"/Resources/*.lproj "$work/"
AETHERNX_ROOT="$root" "$work/snapshots" "$out" "${2:-dark}" "${3:-1440}" "${4:-900}" -AppleLanguages "(en)" -AppleLocale en_US
