#!/bin/bash
# Mac Monitor — build script.
# Compiles the Swift sources into a universal .app bundle in /Applications,
# embeds Info.plist + AppIcon.icns, and ad-hoc code-signs it.
#
# Override the destination with APP=..., e.g. APP=build/"Mac Monitor.app" ./build.sh
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="${APP:-/Applications/Mac Monitor.app}"

echo "==> Clean"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Info.plist + icon"
cp "$PROJ/Info.plist"             "$APP/Contents/Info.plist"
cp "$PROJ/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> Compile"
"$PROJ/scripts/compile.sh" "$APP/Contents/MacOS/MacMonitor"

echo "==> Ad-hoc sign"
codesign --force --deep --sign - "$APP"

# Run the new binary once from here. Its first exec makes Gatekeeper scan it; if that
# first exec were the LaunchAgent's instead, launch constraints would kill it
# (OS_REASON_CODESIGNING, "Launch Constraint Violation").
echo "==> Smoke test: $("$APP/Contents/MacOS/MacMonitor" --version)"

# refresh Finder/Dock icon cache for this bundle
touch "$APP"

echo "==> Done: $APP"
