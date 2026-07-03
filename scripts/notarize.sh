#!/usr/bin/env bash
set -euo pipefail

# Zeus — Developer ID archive → notarize → staple (SPEC §8, P8-F).
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain (Xcode ▸ Settings ▸ Accounts
#      ▸ Manage Certificates, or downloaded from developer.apple.com).
#   2. A notarytool keychain profile holding your credentials:
#        xcrun notarytool store-credentials ZeusNotary \
#          --apple-id "you@example.com" --team-id "ABCDE12345" \
#          --password "<app-specific-password>"     # appleid.apple.com ▸ App-Specific Passwords
#
# Usage:
#   TEAM_ID=ABCDE12345 scripts/notarize.sh
#
# Environment:
#   TEAM_ID         (required) your Apple Developer Team ID
#   NOTARY_PROFILE  (optional) notarytool keychain profile name        [default: ZeusNotary]
#   SCHEME          (optional) scheme to archive                        [default: Zeus]
#   CONFIG          (optional) build configuration                      [default: Release]
#
# NOTE: requires a macOS host whose major version >= the app's MACOSX_DEPLOYMENT_TARGET (26.x) and
# the matching SDK. On an older host the archive step cannot build the app target — run this on a
# macOS 26 machine / CI runner.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Zeus/Zeus.xcodeproj"
SCHEME="${SCHEME:-Zeus}"
CONFIG="${CONFIG:-Release}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ZeusNotary}"

BUILD="$ROOT/build"
ARCHIVE="$BUILD/Zeus.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Zeus.app"
ZIP="$BUILD/Zeus.zip"
EXPORT_OPTS="$BUILD/ExportOptions.plist"

: "${TEAM_ID:?set TEAM_ID to your Apple Developer Team ID}"
mkdir -p "$BUILD"

echo "▸ Archiving ($SCHEME / $CONFIG)…"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "▸ Writing ExportOptions…"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST

echo "▸ Exporting Developer ID app…"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT"

echo "▸ Zipping for notarization…"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to the notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling the ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "✓ Notarized, stapled app: $APP"
echo "  (Verify Gatekeeper: spctl -a -vvv --type execute \"$APP\")"
