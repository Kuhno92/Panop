import AppKit
import Foundation
@testable import Panop
import PanopCore
import SwiftData
import SwiftUI
import Testing

/// How long the real screens keep the main thread, against a real provider.
///
/// Each screen is hosted in a window placed far off every display, so nothing is drawn where a
/// person could see it and nothing of the desktop is read. Scrolling is done by moving the scroll
/// view's clip view and drawing, at the pace of a 60 Hz display. A step that takes longer than its
/// slot overran, and an overrun is a dropped frame: the number to watch is how many, and how long.
///
/// Off unless `PANOP_DEV_XTREAM=url|username|password` is set (read from the environment only), and
/// only meaningful in an optimised build. See `RealProviderBenchmarks` for how to run it.
@Suite(
    "Frame time benchmarks",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] != nil),
    .serialized
)
@MainActor
struct FrameTimeBenchmarks {
    private let slot = 1.0 / 60.0

    private func record(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/panop-bench-results.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Runs the main run loop for `duration`, in slots of one frame, and returns how far each slot
    /// overran. A slot that overran is a time the main thread was busy when a frame was due.
    private func pump(_ duration: Double, window: NSWindow? = nil, each: () -> Void = {}) -> [Double] {
        var overruns: [Double] = []
        let end = ContinuousClock.now + .seconds(duration)
        while ContinuousClock.now < end {
            let began = ContinuousClock.now
            each()
            window?.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(max(0, slot - seconds(since: began))))
            overruns.append(max(0, seconds(since: began) - slot) * 1000)
        }
        return overruns
    }

    private func summary(_ label: String, _ overruns: [Double]) {
        let sorted = overruns.sorted()
        let slow = overruns.filter { $0 > 8 }.count
        record(String(
            format: "FRAME %@: %d frames, %d over by 8 ms or more, p95 overrun %.1f ms, worst %.1f ms",
            label, overruns.count, slow, sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count) * 0.95)], sorted.last ?? 0
        ))
    }

    private func host(_ content: some View, app: TestApp) -> NSWindow {
        let view = NavigationStack { content }
            .environment(\.cloudModelContext, ModelContext(app.cloud))
            .environment(app.services.library)
            .environment(app.services.userState)
            .environment(app.services.syncStatus)
            .modelContainer(app.services.catalogContainer)
        // Borderless, so the window system does not pull it back onto a display.
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: 1100, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        return window
    }

    private func largestScrollView(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ node: NSView) {
            if let scroll = node as? NSScrollView,
               scroll.frame.width * scroll.frame.height > (best.map { $0.frame.width * $0.frame.height } ?? 0)
            {
                best = scroll
            }
            node.subviews.forEach(visit)
        }
        visit(view)
        return best
    }

    private func scroll(_ window: NSWindow, steps: Int, delta: CGFloat) -> [Double] {
        guard let root = window.contentView, let scrollView = largestScrollView(in: root) else { return [] }
        let clip = scrollView.contentView
        var y: CGFloat = 0
        return pump(Double(steps) * slot, window: window) {
            y += delta
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    @Test
    func `the screens against a real provider`() async throws {
        let parts = (ProcessInfo.processInfo.environment["PANOP_DEV_XTREAM"] ?? "").split(separator: "|")
            .map(String.init)
        try #require(parts.count == 3)
        let app = try TestApp(transport: URLSessionTransport())
        defer { app.cleanUp() }
        let playlist = try await app.services.library.add(
            .xtream(name: "Dev", baseURL: parts[0], username: parts[1], password: parts[2])
        )
        await app.services.sync.waitForCompletion(playlist.id)

        let screens: [(String, AnyView)] = [
            ("Live TV", AnyView(LiveTVView())),
            ("Movies", AnyView(VODBrowseView(kind: .movie))),
            ("Series", AnyView(VODBrowseView(kind: .series))),
            ("Home", AnyView(HomeView(onBrowse: {})))
        ]
        for (name, screen) in screens {
            let began = ContinuousClock.now
            let window = host(screen, app: app)
            window.displayIfNeeded()
            record(String(
                format: "FRAME %@: first draw after creating the screen took %.1f ms",
                name,
                seconds(since: began) * 1000
            ))
            summary("\(name), first second after it appears", pump(1.0, window: window))
            summary("\(name), scrolling", scroll(window, steps: 90, delta: 70))
            window.orderOut(nil)
        }
    }
}
