#!/usr/bin/env bash
#
# Sets the build number (CURRENT_PROJECT_VERSION) of the app. App Store Connect wants a higher one for every upload of
# the same version. With no argument it goes up by one; with a number it is set to that.
#
#   Scripts/bump-build.sh        # 1 -> 2
#   Scripts/bump-build.sh 17

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PBX="Panop.xcodeproj/project.pbxproj"
current="$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PBX" | grep -o '[0-9]*$')"
next="${1:-$((current + 1))}"
[[ "$next" =~ ^[0-9]+$ ]] || { echo "error: the build number must be a whole number" >&2; exit 1; }

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $next;/" "$PBX"
echo "build number: $current -> $next"
