#!/usr/bin/env bash
#
# Build the Panop app for every supported platform.
#
# Always pairs -derivedDataPath with -clonedSourcePackagesDirPath. Without the
# shared clone dir, each DerivedData directory re-downloads the whole package
# graph: VLCKit's xcframework alone is ~865 MB, so a few parallel builds will
# fill a disk. See AGENTS.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Panop.xcodeproj"
SCHEME="${PANOP_SCHEME:-Panop}"
SHARED_SPM="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}"
DD_BASE="${PANOP_DD:-/tmp/panop-dd}"

if [[ ! -d "$PROJECT" ]]; then
    echo "error: $PROJECT does not exist yet."
    echo "The app target has not been created. Until then use:"
    echo "    swift test --package-path Packages/PanopKit"
    exit 1
fi

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

build() {
    local label="$1" destination="$2"
    # macOS: explicit modules off, or the compile of FFmpegKit (KSPlayer's FFmpeg) fails (docs/engines.md).
    local extra=()
    [[ "$label" == macos ]] && extra=(SWIFT_ENABLE_EXPLICIT_MODULES=NO)
    log "Building for $label"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -derivedDataPath "${DD_BASE}-${label}" \
        -clonedSourcePackagesDirPath "$SHARED_SPM" \
        CODE_SIGNING_ALLOWED=NO \
        PANOP_ICLOUD_ENTITLED=NO \
        ${extra[@]+"${extra[@]}"} \
        -quiet
    echo "    $label ok"
}

# Resolve concrete simulator names rather than hardcoding, so this keeps working
# as Xcode ships new device sets.
ios_sim="$(xcrun simctl list devices available --json \
    | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)["devices"]
for rt,devs in sorted(d.items(), reverse=True):
    if "iOS" in rt:
        for x in devs:
            if x.get("isAvailable"): print(x["name"]); sys.exit()
' 2>/dev/null || true)"

tv_sim="$(xcrun simctl list devices available --json \
    | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)["devices"]
for rt,devs in sorted(d.items(), reverse=True):
    if "tvOS" in rt:
        for x in devs:
            if x.get("isAvailable"): print(x["name"]); sys.exit()
' 2>/dev/null || true)"

if [[ -n "$ios_sim" ]]; then
    build "ios" "platform=iOS Simulator,name=$ios_sim"
else
    echo "warning: no available iOS simulator found, skipping" >&2
fi

if [[ -n "$tv_sim" ]]; then
    build "tvos" "platform=tvOS Simulator,name=$tv_sim"
else
    # No tvOS runtime installed. A generic destination still compiles and links
    # for tvOS, which catches the great majority of platform mistakes. Install
    # the runtime to actually launch the app:
    #   xcodebuild -downloadPlatform tvOS
    echo "note: no tvOS simulator runtime installed, doing a compile-only check" >&2
    build "tvos" "generic/platform=tvOS"
fi

build "macos" "platform=macOS"

log "All platforms built"
echo
echo "DerivedData left at ${DD_BASE}-*. Remove it when you are done:"
echo "    rm -rf ${DD_BASE}-*"
