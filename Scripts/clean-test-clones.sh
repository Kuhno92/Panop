#!/usr/bin/env bash
#
# Delete the simulator clones that `xcodebuild test` leaves in ~/Library/Developer/XCTestDevices.
#
# xcodebuild clones the simulator for parallel testing and does not remove the clones when a run
# is interrupted or fails to start. They pile up (14 were found), each one a full device on disk.
# The test scripts call this on exit, so a run leaves nothing behind; run it by hand after any
# xcodebuild test of your own. Only the testing set is touched, never the real simulators.

set -uo pipefail

set_path="$HOME/Library/Developer/XCTestDevices"
[[ -d "$set_path" ]] || exit 0
xcrun simctl --set "$set_path" shutdown all >/dev/null 2>&1 || true
xcrun simctl --set "$set_path" delete all >/dev/null 2>&1 || true
