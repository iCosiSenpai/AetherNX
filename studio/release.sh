#!/bin/bash
# Builds, signs, notarizes and packages AetherNX Studio for a GitHub release, into build/release/:
# AetherNX-<version>.zip (with a stapled app) and a stapled AetherNX-<version>.dmg.
# Install dmgbuild 1.6.7 in your release environment, or point AETHERNX_DMGBUILD at it.
#
#   AETHERNX_SIGN_IDENTITY="Developer ID Application: <name> (<team ID>)" studio/release.sh
#
# Notarization uses a notarytool keychain profile, NOTARY unless AETHERNX_NOTARY_PROFILE names another
# (xcrun notarytool store-credentials NOTARY --key <AuthKey.p8> --key-id <id> --issuer <issuer>). Or it uses the App Store Connect API key itself:
# AETHERNX_NOTARY_KEY=<AuthKey_<id>.p8> AETHERNX_NOTARY_ISSUER=<issuer> (AETHERNX_NOTARY_KEY_ID when the file's name does not carry the key ID).
# The key needs no keychain item, which notarytool cannot read while the Mac's screen is locked (a release run through a remote session).
set -euo pipefail

studio="$(cd "$(dirname "$0")" && pwd -P)"
root="$(cd "$studio/.." && pwd -P)"
identity="${AETHERNX_SIGN_IDENTITY:?set AETHERNX_SIGN_IDENTITY to a Developer ID Application identity}"
profile="${AETHERNX_NOTARY_PROFILE:-NOTARY}"
team="$(sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' <<< "$identity")"
[ -n "$team" ] || { echo "the identity must end with its team ID in parentheses" >&2; exit 1; }
version="$(tr -d '[:space:]' < "$root/VERSION")"
out="$root/build/release"
dmgbuild="${AETHERNX_DMGBUILD:-dmgbuild}"
command -v "$dmgbuild" >/dev/null || { echo "install dmgbuild 1.6.7 to create the installer" >&2; exit 1; }
app="$root/build/AetherNX.app"

if [ -n "${AETHERNX_NOTARY_KEY:-}" ]; then
  key_id="${AETHERNX_NOTARY_KEY_ID:-}"
  if [ -z "$key_id" ]; then
    key_id="$(basename "$AETHERNX_NOTARY_KEY" .p8)"
    key_id="${key_id#AuthKey_}"
  fi
  [ -n "$key_id" ] || { echo "set AETHERNX_NOTARY_KEY_ID: the key file's name does not carry its ID" >&2; exit 1; }
  notary=(--key "$AETHERNX_NOTARY_KEY" --key-id "$key_id" --issuer "${AETHERNX_NOTARY_ISSUER:?set AETHERNX_NOTARY_ISSUER to the issuer ID of the API key}")
else
  notary=(--keychain-profile "$profile")
fi

# Fail in seconds, not after the build, when the credentials do not authenticate.
xcrun notarytool history "${notary[@]}" > /dev/null

notarize() {   # submit a file, wait, and stop unless Apple accepted it
  local result status
  result="$(xcrun notarytool submit "$1" "${notary[@]}" --wait --output-format json)"
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

mkdir -p "$out"
staging="$(mktemp -d "$out/.staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
zip="$staging/AetherNX-$version.zip"
dmg="$staging/AetherNX-$version.dmg"

ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/submit.zip"
notarize "$staging/submit.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

"$dmgbuild" -s "$studio/dmg_settings.py" \
  -D "app=$app" -D "icon=$root/assets/AppIcon.icns" -D "background=$studio/Installer.tiff" \
  "AetherNX $version" "$dmg"

# Verify the mounted copy too. Finder metadata added during packaging can invalidate an app's signature.
(
  mount="$staging/mounted"
  mkdir "$mount"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg" > /dev/null
  trap 'hdiutil detach "$mount" > /dev/null' EXIT
  codesign --verify --deep --strict -R "$requirement" "$mount/AetherNX.app"
  xcrun stapler validate "$mount/AetherNX.app"
  [ "$(readlink "$mount/Applications")" = /Applications ]
  cmp "$studio/Installer.tiff" "$mount/.background.tiff"
)

codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

spctl -a -vvv -t install "$app" 2>&1 | grep -q "source=Notarized Developer ID" || { echo "Gatekeeper does not accept the app" >&2; exit 1; }
spctl -a -vvv -t open --context context:primary-signature "$dmg" 2>&1 | grep -q "source=Notarized Developer ID" || { echo "Gatekeeper does not accept the disk image" >&2; exit 1; }

(cd "$staging" && shasum -a 256 "AetherNX-$version.zip" "AetherNX-$version.dmg" | tee SHA256SUMS)
mv "$zip" "$dmg" "$staging/SHA256SUMS" "$out/"
echo "Release files in $out"
