#!/usr/bin/env bash
# The Go tunnel's end-to-end self-test (a stand-in VPN server and the real client, in one process) on the
# Mac, the iOS simulator and the tvOS simulator. Usage: Scripts/test-tunnel.sh [macos|ios|tvos]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${1:-macos}"
"$ROOT/Scripts/ensure-tunnel.sh" --selftest
case "$platform" in
  macos) destination='platform=macOS' ;;
  ios)   destination="platform=iOS Simulator,name=${PANOP_IOS_DEVICE:-iPhone 17 Pro}" ;;
  tvos)  destination="platform=tvOS Simulator,name=${PANOP_TVOS_DEVICE:-Apple TV 4K (3rd generation)}" ;;
  *) echo "usage: $0 [macos|ios|tvos]" >&2; exit 2 ;;
esac
cd "$ROOT/Packages/PanopTunnel/SelfTest"
xcodebuild test -scheme PanopTunnelSelfTest-Package -destination "$destination" \
  -derivedDataPath "$ROOT/.build/tunnel-selftest-dd" \
  -clonedSourcePackagesDirPath ~/Library/Developer/Panop-SharedSPM
