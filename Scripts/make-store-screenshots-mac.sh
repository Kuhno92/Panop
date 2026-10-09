#!/usr/bin/env bash
#
# The Mac's App Store screenshots: the demo content (fictional channels, films and series with generated artwork) in a
# window of 1280 x 800 points, which a Retina display captures as 2560 x 1600, a size the store takes.
#
#   Scripts/make-store-screenshots-mac.sh
#
# Runs the Debug app with the UI-test launch arguments and takes the window with `screencapture -l`, so the terminal
# running this needs Screen Recording permission (System Settings, Privacy and Security). Pictures go to build/store/mac.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DD="${PANOP_DD:-/tmp/panop-dd-shot-mac}"
OUT="$ROOT/build/store/mac"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild build -project Panop.xcodeproj -scheme Panop -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$HOME/Library/Developer/Panop-SharedSPM" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS= PANOP_ICLOUD_ENTITLED=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO -quiet 2>&1 | grep -E "error:|BUILD" | grep -v "exit code 0" || true
APP="$DD/Build/Products/Debug/Panop.app/Contents/MacOS/Panop"

shot() {
    local name="$1" tab="$2"
    PANOP_DEMO_ART_DIR="$ROOT/docs/store-art" PANOP_DEMO=1 PANOP_HERO=1 PANOP_START_TAB="$tab" "$APP" -panop-uitest -AppleLanguages "(en)" >/dev/null 2>&1 &
    local pid=$!
    sleep 14
    local id=""
    for _ in 1 2 3 4 5 6; do
        id="$(swift Scripts/window-id.swift "$pid" 2>/dev/null || true)"
        [[ -n "$id" ]] && break
        sleep 4
    done
    [[ -n "$id" ]] || { echo "error: no window for $name" >&2; kill "$pid" 2>/dev/null || true; return 1; }
    screencapture -l"$id" -o -x "$OUT/$name.png"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 2
    sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2 | tr '\n' ' '; echo
}

shot 01-home home
shot 02-live live
shot 04-movies movies
