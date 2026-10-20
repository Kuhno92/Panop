#!/usr/bin/env bash
# Builds Packages/PanopTunnel/build/PanopTunnel.xcframework: the Go WireGuard tunnel (see
# Packages/PanopTunnel/README.md) for iOS, tvOS and macOS, device and simulator.
#
#   Scripts/build-tunnel.sh              the framework as shipped
#   Scripts/build-tunnel.sh --selftest   also compiles TunnelSelfTest, which proves the whole path on-device
#
# The Go toolchain and gomobile are fetched into .build/tools (gitignored, pinned below), nothing global.
set -euo pipefail

GO_VERSION=1.26.10
GOMOBILE_VERSION=v0.1.13    # github.com/sagernet/gomobile: the fork that adds tvOS (what sing-box builds with)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.build/tools"
export GOPATH="$TOOLS/gopath" GOCACHE="$TOOLS/gocache" GOFLAGS=-mod=mod
export PATH="$TOOLS/go/bin:$GOPATH/bin:$PATH"

TAGS=""
[[ "${1:-}" == "--selftest" ]] && TAGS="selftest"

if ! [[ -x "$TOOLS/go/bin/go" ]] || [[ "$("$TOOLS/go/bin/go" version)" != *"go$GO_VERSION "* ]]; then
  [[ "$(uname -m)" == "arm64" ]] || { echo "This script fetches the arm64 Go toolchain." >&2; exit 1; }
  mkdir -p "$TOOLS/dl" && cd "$TOOLS/dl"
  archive="go$GO_VERSION.darwin-arm64.tar.gz"
  curl -fsSLO "https://go.dev/dl/$archive"
  want="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    for f in r['files']:
        if f['filename']=='$archive': print(f['sha256'])")"
  echo "$want  $archive" | shasum -a 256 -c -
  rm -rf "$TOOLS/go" "$TOOLS/goroot-extract" && mkdir -p "$TOOLS/goroot-extract"
  tar -xzf "$archive" -C "$TOOLS/goroot-extract" && mv "$TOOLS/goroot-extract/go" "$TOOLS/go"
fi

if ! command -v gomobile >/dev/null; then
  (cd "$ROOT/Packages/PanopTunnel/go" && GOFLAGS= go install \
    "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION" "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION")
  gomobile init
fi

cd "$ROOT/Packages/PanopTunnel/go"
go get "github.com/sagernet/gomobile/bind@$GOMOBILE_VERSION" >/dev/null
out="$ROOT/Packages/PanopTunnel/build/PanopTunnel.xcframework"
rm -rf "$out" && mkdir -p "$(dirname "$out")"
# Stripped and path-free: smaller, and the build machine's paths do not end up in the binary.
gomobile bind -trimpath ${TAGS:+-tags "$TAGS"} -ldflags="-s -w" \
  -target ios,iossimulator,tvos,tvossimulator,macos \
  -iosversion=18.0 -tvosversion=18.0 -macosversion=15.0 \
  -o "$out" .
du -sh "$out"/*/PanopTunnel.framework/PanopTunnel 2>/dev/null || true
