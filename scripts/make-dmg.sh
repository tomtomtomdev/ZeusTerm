#!/usr/bin/env bash
set -euo pipefail

# Zeus — package the exported app into a distributable .dmg (SPEC §8, P8-F).
#
# Wraps the app produced by scripts/notarize.sh (build/export/Zeus.app) in a compressed disk
# image with a drag-to-/Applications layout. Uses only hdiutil (built into macOS) — no Homebrew
# create-dmg dependency.
#
# Recommended order:
#   1. TEAM_ID=ABCDE12345 scripts/notarize.sh      # archive → export → notarize → staple the .app
#   2. scripts/make-dmg.sh                          # wrap the stapled .app in a .dmg
#      # then, to distribute the DMG itself, notarize + staple the image (Gatekeeper checks it):
#      TEAM_ID=ABCDE12345 NOTARIZE_DMG=1 scripts/make-dmg.sh
#
# Usage:
#   scripts/make-dmg.sh
#
# Environment:
#   APP             (optional) path to the .app to package          [default: build/export/Zeus.app]
#   VOL_NAME        (optional) mounted volume / window title         [default: Zeus]
#   NOTARIZE_DMG    (optional) set to 1 to notarize + staple the dmg [default: unset]
#   TEAM_ID         (required only when NOTARIZE_DMG=1) Apple Team ID
#   NOTARY_PROFILE  (optional) notarytool keychain profile name      [default: ZeusNotary]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="${APP:-$BUILD/export/Zeus.app}"
VOL_NAME="${VOL_NAME:-Zeus}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ZeusNotary}"

[ -d "$APP" ] || { echo "✗ App not found: $APP (run scripts/notarize.sh first, or set APP=…)" >&2; exit 1; }

APP_NAME="$(basename "$APP")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0)"
DMG="$BUILD/${VOL_NAME}-${VERSION}.dmg"
STAGE="$BUILD/dmg-stage"

echo "▸ Staging $APP_NAME ($VERSION)…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/$APP_NAME"      # preserves signature + xattrs
ln -s /Applications "$STAGE/Applications"      # drag-to-install target

echo "▸ Building compressed disk image…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"

rm -rf "$STAGE"

if [ "${NOTARIZE_DMG:-}" = "1" ]; then
  : "${TEAM_ID:?set TEAM_ID to notarize the dmg}"
  echo "▸ Signing the dmg (Developer ID)…"
  codesign --force --sign "Developer ID Application" --timestamp "$DMG"

  echo "▸ Submitting the dmg to the notary service (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "▸ Stapling the dmg…"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "✓ Disk image: $DMG"
echo "  (Verify Gatekeeper: spctl -a -vvv --type open --context context:primary-signature \"$DMG\")"
