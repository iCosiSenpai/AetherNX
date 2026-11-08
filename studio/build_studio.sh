#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/AetherNX.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AetherNX</string>
    <key>CFBundleIdentifier</key>
    <string>com.icosisenpai.aethernx.studio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AetherNX</string>
    <key>CFBundleDisplayName</key>
    <string>AetherNX Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "[AetherNX] Compiling native SwiftUI Studio app (arm64-apple-macos14.0)..."
xcrun swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    "$SCRIPT_DIR/Sources/AetherNXApp.swift" \
    -o "$MACOS_DIR/AetherNX"

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
echo "[AetherNX] Built $APP_BUNDLE"
