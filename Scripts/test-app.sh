#!/usr/bin/env bash
#
# Run the app's unit tests (the PanopTests target) on one platform.
#
#   Scripts/test-app.sh                 macOS, the fast one
#   Scripts/test-app.sh ios|tvos        an available simulator
#   Scripts/test-app.sh --benchmark [catalog|playback|real]
#                                       benchmarks: macOS, Release build. The first two by default.
#                                       `real` needs TEST_RUNNER_PANOP_DEV_XTREAM='url|user|pass' in the
#                                       environment and imports from that provider
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
        real) suites=(RealProviderBenchmarks) ;;
        -h | --help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# The scheme also holds the UI tests (Scripts/test-ui.sh). They are slow, need a simulator
# and, on macOS, an accessibility grant, so they are never part of this fast run.
flags=(-skip-testing:PanopUITests)
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

# On macOS the tests are hosted inside the app, and a test bundle signed one way will not load
# into an app signed another (different Team IDs). A project that names a development team signs
# the app with it, while the bundle is ad hoc, so tests sign everything ad hoc and do not depend on
# whose team is set.
if [[ "$platform" == macos ]]; then
    flags+=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

# PANOP_ONLY=LiveStreamSmokeTests runs one suite (or Suite/test) instead of everything;
# a comma-separated list runs several.
if [[ -n "${PANOP_ONLY:-}" ]]; then
    IFS=',' read -r -a only <<<"$PANOP_ONLY"
    for name in "${only[@]}"; do
        flags+=("-only-testing:PanopTests/$name")
    done
fi

log="$(mktemp -t panop-test)"
# Whatever happens, leave no simulator clones behind (see the script).
trap '"$ROOT/Scripts/clean-test-clones.sh"' EXIT
echo "==> Testing on $platform (log: $log)"

# The test host sometimes never starts its tests and xcodebuild then waits for it forever: the
# system's test manager (macOS) or the simulator is wedged. A run that has not started one test
# five minutes after it began (a cold build takes up to three) is stuck, so it is killed, the
# thing that wedged is restarted, and the run tried again, up to three times. The numbers below
# are in seconds. Benchmarks are left alone: they print nothing while they measure.
stall_after=420
status=1
for attempt in 1 2 3; do
    xcodebuild test \
        -project Panop.xcodeproj \
        -scheme PanopTests \
        -destination "$destination" \
        -parallel-testing-enabled NO \
        -derivedDataPath "${DD_BASE}-test-${platform}$([[ $benchmark -eq 1 ]] && echo -bench)" \
        -clonedSourcePackagesDirPath "$SHARED_SPM" \
        ${flags[@]+"${flags[@]}"} >"$log" 2>&1 &
    pid=$!
    began=$SECONDS
    stuck=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 10
        if [[ $benchmark -eq 0 ]] && ! grep -qE "^Test (Suite|case)" "$log" && (( SECONDS - began > stall_after )); then
            stuck=1
            pkill -P "$pid" 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
            break
        fi
    done
    set +e
    wait "$pid" 2>/dev/null
    status=$?
    set -e
    if (( stuck == 0 )); then
        break
    fi
    echo "==> attempt $attempt never started a test; restarting what wedged" >&2
    if [[ "$platform" == macos ]]; then
        pkill -f "Panop.app/Contents/MacOS/Panop" 2>/dev/null || true
        killall -9 testmanagerd 2>/dev/null || true
    else
        xcrun simctl shutdown "$id" 2>/dev/null || true
    fi
    sleep 3
done

grep -E "^Test case .* (passed|failed)" "$log" | sed -E "s/ on '.*'//" || true
grep -E "error:|Failing tests:|^\s+[A-Za-z]+Tests\." "$log" | head -20 || true
if [[ $benchmark -eq 1 && -f /tmp/panop-bench-results.txt ]]; then
    echo
    echo "==> Benchmark results"
    cat /tmp/panop-bench-results.txt
fi
grep -E "^\*\* TEST (SUCCEEDED|FAILED) \*\*" "$log" || true
exit $status
