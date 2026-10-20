#!/usr/bin/env bash
# Builds Packages/PanopTunnel/build/PanopTunnel.xcframework: the Go WireGuard tunnel (see
# Packages/PanopTunnel/README.md) for iOS, tvOS and macOS, device and simulator.
#
#   Scripts/build-tunnel.sh              the framework as shipped -> Packages/PanopTunnel/build
#   Scripts/build-tunnel.sh --selftest   with TunnelSelfTest (a stand-in server, to prove the whole path on
#                                        a simulator) -> Packages/PanopTunnel/build-selftest
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
OUTDIR="build"
if [[ "${1:-}" == "--selftest" ]]; then TAGS="selftest"; OUTDIR="build-selftest"; fi

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
out="$ROOT/Packages/PanopTunnel/$OUTDIR/PanopTunnel.xcframework"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Stripped and path-free: smaller, and the build machine's paths do not end up in the binary.
gomobile bind -trimpath ${TAGS:+-tags "$TAGS"} -ldflags="-s -w" \
  -target ios,iossimulator,tvos,tvossimulator,macos \
  -iosversion=18.0 -tvosversion=18.0 -macosversion=15.0 \
  -o "$work/PanopTunnel.xcframework" .

# What gomobile writes is a framework whose binary is a static archive, in macOS's versioned layout even for
# iOS and tvOS, which those platforms refuse. Repack iOS and tvOS as shallow static frameworks with a real
# Info.plist (macOS keeps its versioned layout, which is the right one there).
args=()
for slice in "$work"/PanopTunnel.xcframework/*/; do
  name="$(basename "$slice")"
  fw="$slice/PanopTunnel.framework"
  if [[ "$name" != macos* ]]; then
    flat="$work/flat/$name/PanopTunnel.framework"
    mkdir -p "$flat"
    # A plain archive: gomobile wraps it in a one-architecture "universal" file, which hides it from Xcode.
    # Simulators are arm64 only (every Mac that runs a current Xcode is).
    lipo "$fw/Versions/A/PanopTunnel" -thin arm64 -output "$flat/PanopTunnel"
    cp -RL "$fw/Versions/A/Headers" "$flat/Headers"
    cp -RL "$fw/Versions/A/Modules" "$flat/Modules"
    case "$name" in
      ios*) platform=iPhoneOS; minimum=18.0 ;;
      *)    platform=AppleTVOS; minimum=18.0 ;;
    esac
    [[ "$name" == *simulator* ]] && platform="${platform/OS/Simulator}"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.panop.PanopTunnel" \
      -c "Add :CFBundleName string PanopTunnel" -c "Add :CFBundleExecutable string PanopTunnel" \
      -c "Add :CFBundlePackageType string FMWK" -c "Add :CFBundleVersion string 1" \
      -c "Add :CFBundleShortVersionString string 1.0" -c "Add :MinimumOSVersion string $minimum" \
      "$flat/Info.plist" >/dev/null
    fw="$flat"
  fi
  args+=(-framework "$fw")
done
rm -rf "$out" && mkdir -p "$(dirname "$out")"
xcodebuild -create-xcframework "${args[@]}" -output "$out" >/dev/null
du -shL "$out"/*/PanopTunnel.framework/PanopTunnel 2>/dev/null || true
