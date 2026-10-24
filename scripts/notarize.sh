#!/bin/bash
# Signed + notarized release — TEMPLATE. Use this once you have a paid Apple
# Developer ID ($99/yr). Until then, ship the ad-hoc dist/MacMonitor.dmg from
# scripts/release.sh (users right-click → Open once).
#
# One-time setup:
#   1) In Xcode/Apple Developer, create a "Developer ID Application" certificate.
#   2) Store notarytool credentials in the keychain:
#        xcrun notarytool store-credentials macmonitor-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#   3) Run:  DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/notarize.sh
set -euo pipefail

: "${DEV_ID:?Set DEV_ID to your 'Developer ID Application: Name (TEAMID)' identity}"
PROFILE="${KEYCHAIN_PROFILE:-macmonitor-notary}"

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$PROJ/dist/stage"
APP="$STAGE/Mac Monitor.app"
DMG="$PROJ/dist/MacMonitor.dmg"

echo "==> Build"
rm -rf "$PROJ/dist"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJ/Info.plist"             "$APP/Contents/Info.plist"
cp "$PROJ/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
"$PROJ/scripts/compile.sh" "$APP/Contents/MacOS/MacMonitor"

echo "==> Sign with Developer ID (hardened runtime)"
codesign --force --deep --options runtime --timestamp --sign "$DEV_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Package .dmg"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mac Monitor" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Notarize (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done (signed + notarized): $DMG"
