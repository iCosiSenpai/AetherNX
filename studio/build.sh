#!/bin/bash
# Builds AetherNX Studio into build/AetherNX.app.
#   studio/build.sh                      ad-hoc signed, for this Mac
#   studio/build.sh --sign "<identity>"  signed for distribution (hardened runtime, secure timestamp)
set -euo pipefail

studio="$(cd "$(dirname "$0")" && pwd -P)"
root="$(cd "$studio/.." && pwd -P)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
build_number="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)"
identity=""
if [ "${1:-}" = "--sign" ]; then identity="${2:?--sign needs an identity}"; fi

app="$root/build/AetherNX.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

sed -e "s/@VERSION@/$version/" -e "s/@BUILD@/$build_number/" "$studio/Info.plist" > "$app/Contents/Info.plist"
cp "$root/assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp -R "$studio/Resources/." "$app/Contents/Resources/"

echo "Compiling AetherNX Studio ${version}..."
xcrun swiftc \
  -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos26.0 \
  -module-name AetherNXStudio \
  "$studio"/Sources/*.swift \
  -o "$app/Contents/MacOS/AetherNX"

if [ -n "$identity" ]; then
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
else
  codesign --force --sign - "$app"
fi
echo "Built $app"
