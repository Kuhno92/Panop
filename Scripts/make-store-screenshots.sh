#!/usr/bin/env bash
#
# Takes the App Store screenshots of the demo content (fictional channels, films and series with generated artwork) on the
# simulators whose screens match what App Store Connect asks for, and exports the pictures into build/store/<name>/.
#
#   Scripts/make-store-screenshots.sh [iphone|ipad|tvos|all]
#
# iPhone 6.9" (1320 x 2868), iPad 13" (2064 x 2752) and Apple TV (3840 x 2160). The Mac's are taken by
# Scripts/make-store-screenshots-mac.sh.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build/store"
mkdir -p "$OUT"

run() {
    local name="$1" platform="$2" device="$3"
    echo "==> $name ($device)"
    PANOP_UI_DEVICE="$device" PANOP_ONLY="StoreHomeScene,StoreLiveScene,StoreMoviesScene" \
        Scripts/test-ui.sh "$platform" >/tmp/store-$name.log 2>&1 || tail -20 "/tmp/store-$name.log"
    local bundle
    bundle="$(ls -dt /tmp/panop-dd-ui-"$platform"/Logs/Test/*.xcresult | head -1)"
    rm -rf "$OUT/$name" && mkdir -p "$OUT/$name/raw"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$OUT/$name/raw" >/dev/null
    /usr/bin/python3 - "$OUT/$name" <<'PY'
import json, os, sys
root = sys.argv[1]
for entry in json.load(open(os.path.join(root, "raw", "manifest.json"))):
    for a in entry["attachments"]:
        name = a["suggestedHumanReadableName"].split("_0_")[0]
        os.replace(os.path.join(root, "raw", a["exportedFileName"]), os.path.join(root, name + ".png"))
PY
    rm -rf "$OUT/$name/raw"
    ls "$OUT/$name"
}

case "${1:-all}" in
    iphone) run iphone ios "iPhone 17 Pro Max" ;;
    ipad) run ipad ios "iPad Pro 13-inch (M5)" ;;
    tvos) run tvos tvos "Apple TV 4K (3rd generation)" ;;
    all)
        run iphone ios "iPhone 17 Pro Max"
        run ipad ios "iPad Pro 13-inch (M5)"
        run tvos tvos "Apple TV 4K (3rd generation)"
        ;;
esac
