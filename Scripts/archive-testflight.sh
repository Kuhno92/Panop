#!/usr/bin/env bash
#
# Archives Panop for TestFlight, and with --upload sends it to App Store Connect.
#
#   Scripts/archive-testflight.sh [ios|tvos|macos|all]            # archives only: build/archives/
#   Scripts/archive-testflight.sh all --upload                    # archives, then uploads each
#
# Signed under the personal team (4HUJUM5AUG, see Config/ExportOptions.plist), by Xcode's automatic signing:
# -allowProvisioningUpdates lets it make the distribution certificate and profiles itself, so the Xcode account for
# that team must be signed in. The build number must be higher than the last upload: Scripts/bump-build.sh.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM="4HUJUM5AUG"
SHARED_SPM="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}"
DD_BASE="${PANOP_DD:-/tmp/panop-dd-archive}"
OUT="$ROOT/build/archives"
platforms=(ios tvos macos)
upload=false

for arg in "$@"; do
    case "$arg" in
        ios|tvos|macos) platforms=("$arg") ;;
        all) platforms=(ios tvos macos) ;;
        --upload) upload=true ;;
        *) echo "usage: $0 [ios|tvos|macos|all] [--upload]" >&2; exit 1 ;;
    esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
mkdir -p "$OUT"

for label in "${platforms[@]}"; do
    case "$label" in
        ios) destination="generic/platform=iOS" ;;
        tvos) destination="generic/platform=tvOS" ;;
        macos) destination="generic/platform=macOS" ;;
    esac
    # macOS: explicit modules off, or the compile of FFmpegKit (KSPlayer's FFmpeg) fails (docs/engines.md).
    extra=()
    [[ "$label" == macos ]] && extra=(SWIFT_ENABLE_EXPLICIT_MODULES=NO)

    archive="$OUT/Panop-$label.xcarchive"
    rm -rf "$archive"
    log "Archiving $label"
    xcodebuild archive \
        -project Panop.xcodeproj \
        -scheme Panop \
        -configuration Release \
        -destination "$destination" \
        -archivePath "$archive" \
        -derivedDataPath "$DD_BASE-$label" \
        -clonedSourcePackagesDirPath "$SHARED_SPM" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM" \
        ${extra[@]+"${extra[@]}"} \
        -quiet
    echo "    $archive"

    if $upload; then
        log "Uploading $label to App Store Connect"
        xcodebuild -exportArchive \
            -archivePath "$archive" \
            -exportOptionsPlist Config/ExportOptions.plist \
            -exportPath "$OUT/export-$label" \
            -allowProvisioningUpdates
    fi
done

$upload || echo "Archived only. Add --upload to send to App Store Connect."
