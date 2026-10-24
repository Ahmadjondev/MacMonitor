#!/bin/bash
# Builds Mac Monitor and packages a styled drag-to-install .dmg
# (background image, app icon + Applications shortcut, fixed window).
# Ad-hoc signed. For a signed/notarized release run scripts/notarize.sh after.
#
# Note: the styling step controls Finder via AppleScript — the first run may ask
# for "Automation" permission. If it's denied, you still get a working (plain) dmg.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$PROJ/dist/stage"
APP="$STAGE/Mac Monitor.app"
# The writable image lives outside the home folder: Finder's .DS_Store keeps its path
# in the background-picture alias, which would otherwise ship /Users/<name> in the dmg.
RW_DIR="$(mktemp -d /tmp/macmonitor-dmg.XXXXXX)"
RW="$RW_DIR/rw.dmg"
DMG="$PROJ/dist/MacMonitor.dmg"
VOL="Mac Monitor"

echo "==> Clean dist/"
rm -rf "$PROJ/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE/.background"

echo "==> Bundle metadata + icon"
cp "$PROJ/Info.plist"             "$APP/Contents/Info.plist"
cp "$PROJ/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Compile (universal, macOS 13+)"
"$PROJ/scripts/compile.sh" "$APP/Contents/MacOS/MacMonitor"

echo "==> Ad-hoc sign"
codesign --force --deep --sign - "$APP"

echo "==> Stage dmg contents"
cp "$PROJ/assets/dmg-background.png" "$STAGE/.background/bg.png"
ln -s /Applications "$STAGE/Applications"

echo "==> Create writable dmg"
rm -f "$RW" "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" -nobrowse -noautoopen >/dev/null
sleep 1

echo "==> Style window (Finder)"
osascript <<OSA || echo "   (styling skipped — grant Automation permission and rerun for the styled dmg)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 112
    set background picture of vo to file ".background:bg.png"
    set position of item "Mac Monitor.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/$VOL" >/dev/null || true

echo "==> Compress final dmg"
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
rm -rf "$RW_DIR"
rm -rf "$STAGE"

echo "==> Done: $DMG"
ls -lh "$DMG"
