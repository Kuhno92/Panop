#!/usr/bin/env bash
# Builds the Go tunnel framework when it is missing or its sources changed (a few minutes the first time,
# nothing after). The app needs Packages/PanopTunnel/build/PanopTunnel.xcframework to resolve its packages,
# and it is generated, not committed. Scripts that build the app call this first; open the project in Xcode
# only after running it once.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/Packages/PanopTunnel"
VARIANT=""
OUT="build"
if [[ "${1:-}" == "--selftest" ]]; then VARIANT="--selftest"; OUT="build-selftest"; fi
STAMP="$DIR/$OUT/.stamp"

want="$(cat "$DIR"/go/*.go "$DIR/go/go.mod" "$DIR/go/go.sum" "$ROOT/Scripts/build-tunnel.sh" | shasum -a 256 | cut -d' ' -f1)"
if [[ -d "$DIR/$OUT/PanopTunnel.xcframework" && "$(cat "$STAMP" 2>/dev/null)" == "$want" ]]; then
  exit 0
fi
echo "Building the VPN tunnel framework (Go) ..." >&2
"$ROOT/Scripts/build-tunnel.sh" $VARIANT >&2
echo "$want" > "$STAMP"
