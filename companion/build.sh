#!/bin/bash
# Builds AetherNX Companion for the iOS Simulator, unsigned (docs/companion.md, The prototype).
#   companion/build.sh                 generate the Xcode project (XcodeGen) and build
#   companion/build.sh --run [device]  then install and open it in that Simulator (booted if needed), with the demo library
# Nothing is signed or installed on a device.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
out="${COMPANION_BUILD:-$here/../build/companion}"
command -v xcodegen >/dev/null || { echo "[RED] xcodegen is missing: brew install xcodegen" >&2; exit 1; }

(cd "$here" && xcodegen generate --quiet)
xcodebuild -project "$here/AetherNXCompanion.xcodeproj" -scheme AetherNXCompanion -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$out" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="$out/Build/Products/Debug-iphonesimulator/AetherNXCompanion.app"
echo "Built $app"

if [ "${1:-}" = "--run" ]; then
  device="${2:-iPhone 17}"
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl install "$device" "$app"
  xcrun simctl launch "$device" io.github.icosisenpai.aethernx.companion -demo
fi
