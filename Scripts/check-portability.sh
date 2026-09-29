#!/usr/bin/env bash
#
# Verifies that PanopKit still compiles and tests off-Apple.
#
# This is the local counterpart to the Linux CI job. Run it before any PR that
# touches Packages/PanopKit. See docs/adr/0007-portable-core.md for why the
# core must stay portable.
#
# Needs Docker. If Docker is unavailable it falls back to the SwiftLint rule,
# which catches the common case (an Apple-only import) but not a Foundation API
# that simply does not exist on Linux.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SWIFT_IMAGE="${PANOP_SWIFT_IMAGE:-swift:6.3}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log "Building PanopKit on Linux ($SWIFT_IMAGE)"
    docker run --rm \
        -v "$ROOT":/src \
        -w /src \
        "$SWIFT_IMAGE" \
        swift test --package-path Packages/PanopKit
    log "PanopKit is portable"
    exit 0
fi

echo "Docker is not available, so the Linux build cannot be verified here." >&2
echo "Falling back to the SwiftLint import check only." >&2
echo >&2

if [[ ! -x .build/tools/bin/swiftlint ]]; then
    echo "error: swiftlint not found. Run Scripts/setup.sh first." >&2
    exit 1
fi

log "Checking for Apple-only imports in PanopKit"
.build/tools/bin/swiftlint lint --strict --quiet
log "No forbidden imports found"

echo
echo "This is a partial check. A Foundation API missing on Linux would still"
echo "pass here. Start Docker, or rely on the Linux CI job, for full coverage."
