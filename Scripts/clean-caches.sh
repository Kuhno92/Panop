#!/usr/bin/env bash
#
# Reclaim disk from Panop build caches. Dry run unless --apply is given.
#
#   Scripts/clean-caches.sh            list what would go and how big it is
#   Scripts/clean-caches.sh --apply    delete it
#
# Deleted: per-build DerivedData under /tmp/panop-dd-*, Xcode's Panop-*
# DerivedData (minus SourcePackages), and SwiftPM scratch in every worktree.
#
# Kept on purpose:
#   ~/Library/Developer/Panop-SharedSPM   re-downloading VLCKit alone is ~865 MB
#   .build/tools, artifacts, checkouts    pre-commit runs SwiftFormat, SwiftLint and
#                                         lefthook from here; rebuilding takes minutes
#
# Everything removed regenerates on the next build.

set -euo pipefail

apply=0
case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    -h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DD="$HOME/Library/Developer/Xcode/DerivedData"

# Deleting DerivedData under a running build corrupts it.
if pgrep -x xcodebuild >/dev/null; then
    echo "error: xcodebuild is running; refusing to delete under it." >&2
    exit 1
fi

free_kb() { df -k "$HOME" | awk 'NR==2 { print $4 }'; }
before="$(free_kb)"
total_kb=0

reap() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    local kb
    kb="$(du -sk "$path" 2>/dev/null | cut -f1)"
    total_kb=$((total_kb + kb))
    printf '  %6s MB  %s\n' "$((kb / 1024))" "${path/#$HOME/~}"
    if [[ $apply -eq 1 ]]; then rm -rf "$path"; fi
}

[[ $apply -eq 1 ]] || echo "Dry run. Nothing is deleted without --apply."
echo

echo "Per-build DerivedData"
for path in /tmp/panop-dd-* /private/tmp/panop-dd-*; do
    [[ -e "$path" ]] && reap "$path"
done

echo "Xcode DerivedData for Panop"
for dir in "$XCODE_DD"/Panop-*; do
    [[ -d "$dir" ]] || continue
    # Xcode's own package checkout lives here; leave it or the next build
    # re-fetches everything.
    for child in "$dir"/*; do
        [[ "$(basename "$child")" == "SourcePackages" ]] && continue
        reap "$child"
    done
done

echo "SwiftPM scratch, main checkout and every worktree"
while read -r wt; do
    [[ -d "$wt/.build" ]] || continue
    for child in "$wt"/.build/*; do
        [[ -e "$child" ]] || continue
        # setup.sh symlinks swiftlint and lefthook into .build/artifacts, so
        # removing it (or the checkouts SwiftFormat builds from) breaks the hook.
        case "$(basename "$child")" in
            tools | artifacts | checkouts | repositories | workspace-state.json) continue ;;
        esac
        reap "$child"
    done
    # A worktree's own PanopKit scratch dir is disposable too.
    reap "$wt/Packages/PanopKit/.build"
done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

echo
if [[ $apply -eq 1 ]]; then
    git -C "$ROOT" worktree prune
    after="$(free_kb)"
    echo "Reclaimed about $(((after - before) / 1024)) MB."
else
    echo "Would reclaim about $((total_kb / 1024)) MB. Re-run with --apply."
fi
