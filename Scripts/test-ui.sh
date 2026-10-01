#!/usr/bin/env bash
#
# Run the UI tests (the PanopUITests target) on a simulator.
#
#   Scripts/test-ui.sh ios          the default
#   Scripts/test-ui.sh tvos         drives the Apple TV remote
#   PANOP_ONLY=PlayerTests Scripts/test-ui.sh ios
#
# The app is launched with `-panop-uitest`: in-memory storage, a seeded playlist, and an
# engine that plays instantly, so nothing here needs a network or a stream. Debug builds only.
# Not run on macOS, where driving an app needs an accessibility grant given by hand.
#
# Slow, since it boots a simulator and waits on real animations: minutes, not seconds.
# Pairs -derivedDataPath with the shared package clone, as AGENTS.md requires.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SHARED_SPM="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}"
DD_BASE="${PANOP_DD:-/tmp/panop-dd}"
platform="${1:-ios}"

case "$platform" in
    ios) runtime="iOS"; wanted="iPhone 17 Pro" ;;
    tvos) runtime="tvOS"; wanted="Apple TV 4K (3rd generation)" ;;
    *) echo "usage: $0 [ios|tvos]" >&2; exit 2 ;;
esac

id="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
runtime, wanted = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"]
for key, entries in sorted(devices.items(), reverse=True):
    if runtime.replace("OS", "OS-") in key.replace(".", "-") or runtime in key:
        for entry in entries:
            if entry.get("isAvailable") and entry["name"] == wanted:
                print(entry["udid"]); sys.exit()
' "$runtime" "$wanted")"

if [[ -z "$id" ]]; then
    echo "error: no available $wanted simulator for $runtime. Install the platform with:" >&2
    echo "    xcodebuild -downloadPlatform $runtime" >&2
    exit 1
fi

# xcodebuild clones the device for parallel testing, and a clone that fails to start leaves the
# run waiting forever ("Simulator device failed to launch ...xctrunner"). So: no clones, run on
# the device itself, and have it booted first.
xcrun simctl boot "$id" 2>/dev/null || true
xcrun simctl bootstatus "$id" -b >/dev/null

flags=()
if [[ -n "${PANOP_ONLY:-}" ]]; then
    IFS=',' read -r -a only <<<"$PANOP_ONLY"
    for name in "${only[@]}"; do
        flags+=("-only-testing:PanopUITests/$name")
    done
fi

log="$(mktemp -t panop-ui-test)"
echo "==> UI tests on $wanted (log: $log)"
set +e
xcodebuild test \
    -project Panop.xcodeproj \
    -scheme PanopUITests \
    -destination "platform=$runtime Simulator,id=$id" \
    -parallel-testing-enabled NO \
    -derivedDataPath "${DD_BASE}-ui-${platform}" \
    -clonedSourcePackagesDirPath "$SHARED_SPM" \
    ${flags[@]+"${flags[@]}"} >"$log" 2>&1
status=$?
set -e

grep -E "^Test case .* (passed|failed)" "$log" | sed -E "s/ on '.*'//" || true
grep -E "error:|Failing tests:|^\s+[A-Za-z]+Tests\." "$log" | head -20 || true
grep -E "^\*\* TEST (SUCCEEDED|FAILED) \*\*" "$log" || true
exit $status
