#!/usr/bin/env bash
#
# Fixes "There is no XCFramework found at .../SourcePackages/artifacts/..." in Xcode, which follows File > Packages >
# Reset Package Caches: the binary packages (LumeEngine's FFmpeg, VLCKit) are gone and Xcode does not fetch them again.
#
#   Scripts/restore-package-artifacts.sh      (quit Xcode first)
#
# Copying the files back by hand is not enough: Xcode keeps its own record of where each one was downloaded from and
# with which checksum, and does not accept files it did not download. So the downloaded packages and that record are
# removed, and the package tool downloads them again into the folder Xcode uses.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if pgrep -x Xcode >/dev/null; then
    echo "Quit Xcode first (Cmd-Q), then run this again." >&2
    exit 1
fi

for packages in "$HOME"/Library/Developer/Xcode/DerivedData/Panop-*/SourcePackages; do
    [[ -d "$packages" ]] || continue
    rm -rf "$packages/artifacts" "$packages/workspace-state.json"
    echo "cleared ${packages%/SourcePackages}"
done

# Into the default location, which is the one Xcode reads.
xcodebuild -resolvePackageDependencies -project Panop.xcodeproj -scheme Panop | tail -3
echo "Done. Open the project in Xcode and build."
