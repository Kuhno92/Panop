#!/usr/bin/env bash
#
# One-time setup after cloning Panop.
#
# Everything here uses Xcode's toolchain only. No Homebrew, no Mint, no global
# installs, so every machine and CI runner gets the exact tool versions pinned
# in Package.resolved.
#
# Safe to re-run.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN_DIR=".build/tools/bin"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }

log "Resolving vendored developer tooling"
swift package resolve

mkdir -p "$BIN_DIR"

# SwiftLint ships a prebuilt binary in its artifact bundle.
log "Locating SwiftLint"
swiftlint_bin="$(find .build/artifacts -type f -name swiftlint -perm +111 2>/dev/null | grep -v '/linux/' | head -1 || true)"
if [[ -n "$swiftlint_bin" ]]; then
    ln -sf "$ROOT/$swiftlint_bin" "$BIN_DIR/swiftlint"
    echo "    $("$BIN_DIR/swiftlint" version 2>/dev/null || echo unknown)"
else
    warn "SwiftLint binary not found. Pre-commit linting will be skipped."
fi

# lefthook ships per-platform binaries; pick the one matching this machine.
log "Locating lefthook"
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) lefthook_pattern="MacOS_arm64" ;;
    Darwin-x86_64) lefthook_pattern="MacOS_x86_64" ;;
    Linux-aarch64 | Linux-arm64) lefthook_pattern="Linux_arm64" ;;
    Linux-x86_64) lefthook_pattern="Linux_x86_64" ;;
    *) lefthook_pattern="" ;;
esac
lefthook_bin=""
if [[ -n "$lefthook_pattern" ]]; then
    lefthook_bin="$(find .build/artifacts -type f -name "*${lefthook_pattern}*" -perm +111 2>/dev/null | head -1 || true)"
fi
if [[ -n "$lefthook_bin" ]]; then
    ln -sf "$ROOT/$lefthook_bin" "$BIN_DIR/lefthook"
else
    warn "lefthook binary not found for $(uname -s)-$(uname -m). Git hooks will not be installed."
fi

# SwiftFormat is distributed as source and must be compiled once. This is the
# slow part of setup (a few minutes); every later run is cached.
log "Building SwiftFormat (first run compiles from source, this takes a while)"
swift build -c release \
    --package-path .build/checkouts/SwiftFormat \
    --product swiftformat \
    --scratch-path .build/tools >/dev/null
swiftformat_bin="$(find .build/tools -type f -name swiftformat -perm +111 2>/dev/null | head -1 || true)"
if [[ -n "$swiftformat_bin" ]]; then
    ln -sf "$ROOT/$swiftformat_bin" "$BIN_DIR/swiftformat"
    echo "    swiftformat $("$BIN_DIR/swiftformat" --version 2>/dev/null || echo unknown)"
else
    warn "SwiftFormat binary not found after build. Pre-commit formatting will be skipped."
fi

if [[ -x "$BIN_DIR/lefthook" ]]; then
    log "Installing git hooks"
    "$BIN_DIR/lefthook" install
fi

log "Verifying the portable core builds"
if [[ -f Packages/PanopKit/Package.swift ]]; then
    swift build --package-path Packages/PanopKit >/dev/null
    echo "    PanopKit builds"
else
    echo "    PanopKit not created yet, skipping"
fi

cat <<'EOF'

Setup complete.

  swift test --package-path Packages/PanopKit    fast logic tests, no simulator
  Scripts/build-all-platforms.sh                 build the app for iOS, tvOS, macOS

Read AGENTS.md before making changes. docs/ARCHITECTURE.md is authoritative for
design questions.
EOF
