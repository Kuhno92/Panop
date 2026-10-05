#!/usr/bin/env bash
#
# Puts back the binary packages (LumeEngine's FFmpeg, VLCKit) that Xcode's "Reset Package Caches" deletes and does not
# download again, so a build stops with "There is no XCFramework found at .../SourcePackages/artifacts/...".
#
#   Scripts/restore-package-artifacts.sh
#
# They are copied from the shared package folder the scripts build with (see AGENTS.md) into the SourcePackages
# folder of every Xcode DerivedData folder for this project. Nothing already there is replaced. Quit and reopen
# Xcode afterwards, so it reads the packages again.

set -euo pipefail

SHARED="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}/artifacts"
if [[ ! -d "$SHARED/lumeengine" || ! -d "$SHARED/vlckit" ]]; then
    echo "No saved packages in $SHARED. Run Scripts/build-all-platforms.sh once to download them." >&2
    exit 1
fi

restored=0
for derived in "$HOME"/Library/Developer/Xcode/DerivedData/Panop-*; do
    [[ -d "$derived/SourcePackages" ]] || continue
    mkdir -p "$derived/SourcePackages/artifacts"
    for name in lumeengine vlckit; do
        if [[ ! -d "$derived/SourcePackages/artifacts/$name" ]]; then
            cp -R "$SHARED/$name" "$derived/SourcePackages/artifacts/"
            echo "restored $name into ${derived##*/}"
            restored=$((restored + 1))
        fi
    done
done
echo "$restored restored"
