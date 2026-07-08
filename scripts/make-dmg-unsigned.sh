#!/usr/bin/env bash
set -euo pipefail

# Zeus — ONE-STEP unsigned .dmg for private distribution (SPEC §8, P8-F).
#
# Builds the app fresh, ad-hoc signs it (so it launches on Apple Silicon), and wraps it in a
# compressed .dmg — no Developer ID cert, no notarization, no Apple account required. Use this to
# hand a build to a teammate / tester, NOT for public download.
#
# The app is ad-hoc signed (CODE_SIGN_IDENTITY="-"), not left fully unsigned: an unsigned arm64
# binary is refused by the kernel and won't launch at all. Ad-hoc costs nothing and lets it run.
#
# Because the .dmg is not notarized, Gatekeeper flags it on any Mac that downloaded it (the quarantine
# bit). The recipient clears it once, either way:
#   • Terminal:  xattr -dr com.apple.quarantine /Applications/Zeus.app
#   • or:        right-click the app ▸ Open, then System Settings ▸ Privacy & Security ▸ Open Anyway
#
# Usage:
#   scripts/make-dmg-unsigned.sh
#
# Environment:
#   SCHEME    (optional) scheme to build          [default: Zeus]
#   CONFIG    (optional) build configuration       [default: Release]
#   VOL_NAME  (optional) mounted volume / title    [default: Zeus]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Zeus/Zeus.xcodeproj"
SCHEME="${SCHEME:-Zeus}"
CONFIG="${CONFIG:-Release}"
VOL_NAME="${VOL_NAME:-Zeus}"

BUILD="$ROOT/build"
DD="$BUILD/dd-unsigned"                 # isolated derived data for this build
PRODUCTS="$DD/Build/Products/$CONFIG"
STAGE="$BUILD/dmg-stage-unsigned"

mkdir -p "$BUILD"

echo "▸ Building $SCHEME ($CONFIG), ad-hoc signed…"
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM=""

APP="$(/usr/bin/find "$PRODUCTS" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] && [ -d "$APP" ] || { echo "✗ No .app produced under $PRODUCTS" >&2; exit 1; }

APP_NAME="$(basename "$APP")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.0)"
DMG="$BUILD/${VOL_NAME}-${VERSION}-unsigned.dmg"

echo "▸ Staging $APP_NAME ($VERSION)…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/$APP_NAME"     # preserves the ad-hoc signature + xattrs
ln -s /Applications "$STAGE/Applications"     # drag-to-install target

echo "▸ Building compressed disk image…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"

rm -rf "$STAGE"

echo "✓ Unsigned disk image: $DMG"
echo "  Recipient clears quarantine once:  xattr -dr com.apple.quarantine /Applications/$APP_NAME"
