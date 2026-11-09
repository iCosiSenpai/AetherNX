#!/bin/bash
# Builds, signs, notarizes and packages AetherNX Studio for a GitHub release, into build/release/:
# AetherNX-<version>.zip and AetherNX-<version>.dmg, both stapled.
#
#   AETHERNX_SIGN_IDENTITY="Developer ID Application: <name> (<team ID>)" studio/release.sh
#
# Notarization uses a notarytool keychain profile, NOTARY unless AETHERNX_NOTARY_PROFILE names another
# (xcrun notarytool store-credentials NOTARY --key <AuthKey.p8> --key-id <id> --issuer <issuer>).
set -euo pipefail

studio="$(cd "$(dirname "$0")" && pwd -P)"
root="$(cd "$studio/.." && pwd -P)"
identity="${AETHERNX_SIGN_IDENTITY:?set AETHERNX_SIGN_IDENTITY to a Developer ID Application identity}"
profile="${AETHERNX_NOTARY_PROFILE:-NOTARY}"
team="$(sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' <<< "$identity")"
[ -n "$team" ] || { echo "the identity must end with its team ID in parentheses" >&2; exit 1; }
version="$(tr -d '[:space:]' < "$root/VERSION")"
out="$root/build/release"
app="$root/build/AetherNX.app"

# Fail in seconds, not after the build, when the profile does not authenticate.
xcrun notarytool history --keychain-profile "$profile" > /dev/null

notarize() {   # submit a file, wait, and stop unless Apple accepted it
  local result status
  result="$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json)"
  status="$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("status", ""))' <<< "$result")"
  if [ "$status" != "Accepted" ]; then
    echo "notarization of $(basename "$1"): $status" >&2
    echo "$result" >&2
    exit 1
  fi
  echo "notarized: $(basename "$1")"
}

bash "$studio/build.sh" --sign "$identity"

requirement="=anchor apple generic and certificate leaf[subject.OU] = \"$team\""
codesign --verify --deep --strict -R "$requirement" "$app"
if codesign -d --entitlements - --xml "$app" 2> /dev/null | grep -q get-task-allow; then
  echo "the app carries get-task-allow: not a release build" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/submit.zip"
notarize "$out/submit.zip"
xcrun stapler staple "$app"
rm "$out/submit.zip"
# The zip is made again after stapling: the one sent to Apple holds the app without its ticket.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/AetherNX-$version.zip"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "AetherNX $version" -srcfolder "$staging" -ov -format UDZO "$out/AetherNX-$version.dmg"
codesign --force --timestamp --sign "$identity" "$out/AetherNX-$version.dmg"
notarize "$out/AetherNX-$version.dmg"
xcrun stapler staple "$out/AetherNX-$version.dmg"

spctl -a -vvv -t install "$app" 2>&1 | grep -q "source=Notarized Developer ID" || { echo "Gatekeeper does not accept the app" >&2; exit 1; }
spctl -a -vvv -t open --context context:primary-signature "$out/AetherNX-$version.dmg" 2>&1 | grep -q "source=Notarized Developer ID" || { echo "Gatekeeper does not accept the disk image" >&2; exit 1; }

(cd "$out" && shasum -a 256 "AetherNX-$version.zip" "AetherNX-$version.dmg" | tee SHA256SUMS)
echo "Release files in $out"
