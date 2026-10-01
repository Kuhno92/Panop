#!/usr/bin/env bash
#
# Run the app's unit tests (the PanopTests target) on one platform.
#
#   Scripts/test-app.sh                 macOS, the fast one
#   Scripts/test-app.sh ios|tvos        an available simulator
#   Scripts/test-app.sh --benchmark [catalog|playback]
#                                       benchmarks: macOS, Release build. Both by default
#
# These are the tests that need SwiftData, so they cannot live in the portable
# package. The logic tests are much faster: swift test --package-path Packages/PanopKit
#
# Pairs -derivedDataPath with the shared package clone, as AGENTS.md requires.
# Override the locations with PANOP_DD and PANOP_SPM, and run chosen suites with PANOP_ONLY.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SHARED_SPM="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}"
DD_BASE="${PANOP_DD:-/tmp/panop-dd}"

platform="macos"
benchmark=0
suites=(CatalogBenchmarks PlaybackBenchmarks)
for arg in "$@"; do
    case "$arg" in
        macos | ios | tvos) platform="$arg" ;;
        --benchmark) benchmark=1 ;;
        catalog) suites=(CatalogBenchmarks) ;;
        playback) suites=(PlaybackBenchmarks) ;;
        -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done

# First available simulator whose runtime name contains $1 ("iOS" or "tvOS").
simulator_id() {
    xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
wanted = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if wanted in runtime:
        for entry in entries:
            if entry.get("isAvailable"):
                print(entry["udid"]); sys.exit()
' "$1"
}

flags=()
if [[ $benchmark -eq 1 ]]; then
    # Debug is -Onone, which makes every number fiction. Testability is needed
    # for @testable import, and the hardened runtime refuses to load the
    # ad-hoc-signed package frameworks in a local Release build.
    platform="macos"
    flags=(-configuration Release ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO)
    for suite in "${suites[@]}"; do
        flags+=("-only-testing:PanopTests/$suite")
    done
    export TEST_RUNNER_PANOP_BENCHMARK=1
    rm -f /tmp/panop-bench-results.txt
fi

case "$platform" in
    macos) destination="platform=macOS" ;;
    ios | tvos)
        runtime=$([[ "$platform" == ios ]] && echo iOS || echo tvOS)
        id="$(simulator_id "$runtime")"
        if [[ -z "$id" ]]; then
            echo "error: no available $runtime simulator. Install one with:" >&2
            echo "    xcodebuild -downloadPlatform $runtime" >&2
            exit 1
        fi
        destination="platform=$runtime Simulator,id=$id"
        ;;
esac

# PANOP_ONLY=LiveStreamSmokeTests runs one suite (or Suite/test) instead of everything;
# a comma-separated list runs several.
if [[ -n "${PANOP_ONLY:-}" ]]; then
    IFS=',' read -r -a only <<<"$PANOP_ONLY"
    for name in "${only[@]}"; do
        flags+=("-only-testing:PanopTests/$name")
    done
fi

log="$(mktemp -t panop-test)"
echo "==> Testing on $platform (log: $log)"
set +e
xcodebuild test \
    -project Panop.xcodeproj \
    -scheme PanopTests \
    -destination "$destination" \
    -derivedDataPath "${DD_BASE}-test-${platform}$([[ $benchmark -eq 1 ]] && echo -bench)" \
    -clonedSourcePackagesDirPath "$SHARED_SPM" \
    ${flags[@]+"${flags[@]}"} >"$log" 2>&1
status=$?
set -e

grep -E "^Test case .* (passed|failed)" "$log" | sed -E "s/ on '.*'//" || true
grep -E "error:|Failing tests:|^\s+[A-Za-z]+Tests\." "$log" | head -20 || true
if [[ $benchmark -eq 1 && -f /tmp/panop-bench-results.txt ]]; then
    echo
    echo "==> Benchmark results"
    cat /tmp/panop-bench-results.txt
fi
grep -E "^\*\* TEST (SUCCEEDED|FAILED) \*\*" "$log" || true
exit $status
