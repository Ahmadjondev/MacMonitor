#!/bin/bash
# Compiles Sources/*.swift into a universal (arm64 + x86_64) executable that runs
# on macOS 13+. Used by build.sh, release.sh, notarize.sh and CI.
#
#   scripts/compile.sh <output-path>
#
# Without an explicit -target, swiftc builds for the host only (one arch, and a
# minimum OS equal to the SDK), so every build goes through this script.
set -euo pipefail

OUT="${1:?usage: scripts/compile.sh <output-path>}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
MIN_OS="13.0"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for ARCH in arm64 x86_64; do
  echo "    swiftc -O ($ARCH, macOS $MIN_OS+)"
  swiftc -O -target "$ARCH-apple-macos$MIN_OS" "$PROJ"/Sources/*.swift -o "$TMP/MacMonitor-$ARCH"
done

mkdir -p "$(dirname "$OUT")"
lipo -create "$TMP/MacMonitor-arm64" "$TMP/MacMonitor-x86_64" -output "$OUT"
