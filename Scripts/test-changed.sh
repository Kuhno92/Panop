#!/usr/bin/env bash
#
# Run only the tests a change can affect. This is the loop to use between edits; the full
# matrix (Scripts/test-app.sh and Scripts/test-ui.sh on every platform) is for the end of a
# piece of work, or when this script says to.
#
#   Scripts/test-changed.sh               what is uncommitted (changed and new files)
#   Scripts/test-changed.sh --since HEAD~2   what changed since a revision, plus uncommitted
#   Scripts/test-changed.sh --dry-run     print what it would run
#
# Measured on this machine, why it is built this way:
#   package tests        seconds
#   app tests, macOS     about 30 s, and they do not depend on the platform
#   app tests, iOS       about 50 s even for one suite (simulator boot)
#   UI tests, iOS        about 4.5 min for all 19, since every test launches the app (6 s at
#                        least) and several wait on the clock; one suite is 1 to 2 min
# So: a change is checked on the cheapest thing that can see it, and a screen change runs only
# that screen's UI suites, on iOS. tvOS UI tests run when the change is about focus or the
# remote, and every platform runs at the end.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

since=""
dry=0
while (($#)); do
    case "$1" in
        --since) since="$2"; shift 2 ;;
        --dry-run) dry=1; shift ;;
        *) echo "usage: $0 [--since REV] [--dry-run]" >&2; exit 2 ;;
    esac
done

files="$( {
    [[ -n "$since" ]] && git diff --name-only "$since" HEAD
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
    true
} | sort -u)"

if [[ -z "$files" ]]; then
    echo "nothing changed"
    exit 0
fi

package=0 app=0 ui_suites="" tvos=0 everything=0
add_ui() { case ",$ui_suites," in *",$1,"*) ;; *) ui_suites="${ui_suites:+$ui_suites,}$1" ;; esac; }

while IFS= read -r file; do
    case "$file" in
        Packages/PanopKit/*) package=1 ;;
        Panop/Views/Home/*) app=1; add_ui HomeTests ;;
        Panop/Views/LiveTV/*) app=1; add_ui LiveTVTests; add_ui FavouritesTests ;;
        Panop/Views/Browse/*) app=1; add_ui MoviesTests; add_ui SeriesTests ;;
        Panop/Views/Player/*) app=1; add_ui PlayerTests; add_ui ControlsAutoHideTests ;;
        Panop/Views/Settings/*) app=1; add_ui SettingsTests ;;
        Panop/Views/*|Panop/UITestSupport.swift|Panop/PanopApp.swift|PanopUITests/PanopUITestCase.swift)
            # Shared screens and the test harness itself can break any of them.
            app=1; everything=1 ;;
        PanopUITests/*Tests.swift)
            suite="$(basename "$file" .swift)"; add_ui "$suite" ;;
        Panop/*|PanopTests/*) app=1 ;;
        Panop.xcodeproj/*|Package.swift|vendor/*|Config/*) app=1; everything=1 ;;
    esac
    # Focus and remote handling only show on Apple TV.
    case "$file" in
        *PlayerControls*|*PlayerView*|*Focus*|*tvOS*) tvos=1 ;;
    esac
done <<<"$files"

plan() { echo "==> $*"; ((dry)) || "$@"; }

echo "changed: $(wc -l <<<"$files" | tr -d ' ') files"
((package)) && plan swift test --package-path Packages/PanopKit
((app)) && plan Scripts/test-app.sh macos
if ((everything)); then
    plan Scripts/test-ui.sh ios
elif [[ -n "$ui_suites" ]]; then
    ((dry)) && echo "==> PANOP_ONLY=$ui_suites Scripts/test-ui.sh ios" || PANOP_ONLY="$ui_suites" Scripts/test-ui.sh ios
fi
if ((tvos)); then
    if [[ -n "$ui_suites" && $everything -eq 0 ]]; then
        ((dry)) && echo "==> PANOP_ONLY=$ui_suites Scripts/test-ui.sh tvos" || PANOP_ONLY="$ui_suites" Scripts/test-ui.sh tvos
    else
        plan Scripts/test-ui.sh tvos
    fi
fi
echo "==> done. Before finishing the work, run the full matrix:"
echo "    Scripts/test-app.sh ios; Scripts/test-app.sh tvos; Scripts/test-ui.sh ios; Scripts/test-ui.sh tvos"
