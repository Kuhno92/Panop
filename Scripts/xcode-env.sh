#!/usr/bin/env bash
# Lets the Xcode window build Panop for macOS. Project settings do not reach package targets, and the macOS compile of
# FFmpegKit (KSPlayer's FFmpeg) fails with explicit modules on ("module file ...Libavformat-<hash>.pcm not found"), so
# Xcode is pointed at Config/Xcode-global.xcconfig through XCODE_XCCONFIG_FILE, which applies to every target.
#
#   Scripts/xcode-env.sh            set it for this login session, then quit and reopen Xcode
#   Scripts/xcode-env.sh --login    also keep it across logins (a LaunchAgent in ~/Library/LaunchAgents)
#   Scripts/xcode-env.sh --remove   undo both
#
# The command-line scripts (build-all-platforms.sh, test-app.sh) do not need this; they pass the setting themselves.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/Config/Xcode-global.xcconfig"
agent="$HOME/Library/LaunchAgents/com.panop.xcode-xcconfig.plist"

case "${1:-}" in
--remove)
    launchctl unsetenv XCODE_XCCONFIG_FILE || true
    launchctl bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
    rm -f "$agent"
    echo "Removed. Quit and reopen Xcode."
    exit 0
    ;;
--login)
    mkdir -p "$(dirname "$agent")"
    cat >"$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.panop.xcode-xcconfig</string>
  <key>ProgramArguments</key><array>
    <string>/bin/launchctl</string><string>setenv</string><string>XCODE_XCCONFIG_FILE</string><string>$config</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
    ;;
"") ;;
*)
    echo "usage: $0 [--login|--remove]" >&2
    exit 2
    ;;
esac

launchctl setenv XCODE_XCCONFIG_FILE "$config"
echo "XCODE_XCCONFIG_FILE=$config"
echo "Quit Xcode completely and open it again so it picks this up."
