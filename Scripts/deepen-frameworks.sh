#!/usr/bin/env bash
# macOS only. FFmpegKit (KSPlayer's FFmpeg) ships its macOS frameworks as shallow bundles, with Info.plist and the
# binary at the root, which macOS does not accept ("contains Info.plist, expected
# Versions/Current/Resources/Info.plist"). This rebuilds each such framework in the Embedded Frameworks folder
# with the versioned layout and signs it again. Run as a build phase of the app, after "Embed Frameworks".
# A framework that already has Versions/ (VLCKit, LumeEngine, AetherEngine) is left alone.
set -euo pipefail

[[ "${PLATFORM_NAME:-macosx}" == "macosx" ]] || exit 0
frameworks="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[[ -d "$frameworks" ]] || exit 0

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]] && identity=""
[[ -z "$identity" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]] && identity="-"

for fw in "$frameworks"/*.framework; do
    [[ -d "$fw" && ! -d "$fw/Versions" && -f "$fw/Info.plist" ]] || continue
    name="$(basename "$fw" .framework)"
    exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$fw/Info.plist" 2>/dev/null || echo "$name")"

    rm -rf "$fw/_CodeSignature"
    mkdir -p "$fw/Versions/A/Resources"
    mv "$fw/Info.plist" "$fw/Versions/A/Resources/Info.plist"
    for entry in "$fw"/*; do
        base="$(basename "$entry")"
        [[ "$base" == "Versions" ]] && continue
        mv "$entry" "$fw/Versions/A/$base"
    done
    ln -s A "$fw/Versions/Current"
    for entry in "$fw/Versions/A"/*; do
        base="$(basename "$entry")"
        ln -s "Versions/Current/$base" "$fw/$base"
    done
    [[ -e "$fw/Versions/A/$exe" ]] || { echo "error: $fw has no executable $exe" >&2; exit 1; }

    if [[ -n "$identity" ]]; then
        codesign --force --sign "$identity" --timestamp=none --preserve-metadata=identifier,entitlements,flags "$fw"
    fi
done
