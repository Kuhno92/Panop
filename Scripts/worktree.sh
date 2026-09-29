#!/usr/bin/env bash
#
# Create or remove a git worktree that is ready to commit and build in.
#
#   Scripts/worktree.sh add <branch> [base]    default base: main
#   Scripts/worktree.sh remove <branch>
#
# Worktrees live next to the repo as ../Panop-<branch>, with slashes in the
# branch name turned into dashes.
#
# Why this exists instead of plain `git worktree add`:
#   - Git hooks are shared by all worktrees, and ours runs
#     <worktree>/.build/tools/bin/lefthook. A fresh worktree has no .build, so
#     the hook would skip silently and let unformatted code through. Linking
#     the main checkout's tools fixes that without recompiling SwiftFormat.
#   - vendor/LumeEngine is a submodule and is empty in a new worktree.
#   - The printed build command carries a private DerivedData path plus the
#     shared package clone, which AGENTS.md requires as a pair.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve the main checkout even when run from inside another worktree.
MAIN="$(git -C "$ROOT" worktree list --porcelain | sed -n '1s/^worktree //p')"

die() { echo "error: $1" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

dir_for() { echo "$(dirname "$MAIN")/Panop-${1//\//-}"; }

add() {
    local branch="${1:-}" base="${2:-main}"
    [[ -n "$branch" ]] || die "usage: worktree.sh add <branch> [base]"
    local dir
    dir="$(dir_for "$branch")"
    [[ ! -e "$dir" ]] || die "$dir already exists"

    log "Creating $dir"
    if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$MAIN" worktree add "$dir" "$branch"
    else
        git -C "$MAIN" worktree add -b "$branch" "$dir" "$base"
    fi

    if [[ -d "$MAIN/.build/tools" ]]; then
        mkdir -p "$dir/.build"
        ln -s "$MAIN/.build/tools" "$dir/.build/tools"
    else
        echo "warning: $MAIN/.build/tools is missing; run Scripts/setup.sh in the main checkout." >&2
    fi

    [[ -f "$MAIN/.env" ]] && cp "$MAIN/.env" "$dir/.env"

    log "Initialising submodules"
    git -C "$dir" submodule update --init --recursive \
        || echo "warning: submodule init failed; the app target will not resolve until it succeeds." >&2

    local name
    name="$(basename "$dir")"
    cat <<EOF

Ready: $dir

Build here with a private DerivedData and the shared package clone:

  cd $dir
  PANOP_DD=/tmp/panop-dd-$name Scripts/build-all-platforms.sh

Scripts/clean-caches.sh removes those directories when you are done.
EOF
}

remove() {
    local branch="${1:-}"
    [[ -n "$branch" ]] || die "usage: worktree.sh remove <branch>"
    local dir
    dir="$(dir_for "$branch")"
    [[ -d "$dir" ]] || die "$dir does not exist"

    # The tools link points at the main checkout. Drop it first so nothing can
    # follow it while the worktree is being deleted.
    [[ -L "$dir/.build/tools" ]] && rm "$dir/.build/tools"

    # No --force: git refuses when there are uncommitted changes, which is the
    # behaviour we want. The branch itself is left alone.
    git -C "$MAIN" worktree remove "$dir"
    rm -rf "/tmp/panop-dd-$(basename "$dir")"-*
    echo "Removed $dir (branch $branch kept)."
}

case "${1:-}" in
    add) shift; add "$@" ;;
    remove) shift; remove "$@" ;;
    *) die "usage: worktree.sh add <branch> [base] | remove <branch>" ;;
esac
