// Prints the window number of the biggest on-screen window of a process, for `screencapture -l`.
//   swift Scripts/window-id.swift <pid>
import CoreGraphics
import Foundation

func say(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let mine = windows
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
func area(_ window: [String: Any]) -> Double {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}

guard let best = mine.max(by: { area($0) < area($1) }),
      let number = best[kCGWindowNumber as String] as? Int else { exit(1) }
say(String(number))
