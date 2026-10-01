import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import SwiftUI
import Testing
import VLCKit

/// Plays a real stream and logs everything the engine and the coordinator report, with
/// timestamps, to `/tmp/panop-live-probe.txt`. Off unless `PANOP_LIVE_URL` is set, since
/// it needs the network and a stream that is up:
///
///     TEST_RUNNER_PANOP_LIVE_URL='https://example/stream.m3u8' TEST_RUNNER_PANOP_LIVE_SECONDS=30 \
///       xcodebuild test -project Panop.xcodeproj -scheme PanopTests -destination 'platform=macOS' \
///       -only-testing:PanopTests/LiveStreamSmokeTests
///
/// Not an assertion about the stream: it exists so a person can see what really happened.
@Suite(
    "Live stream smoke test",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_LIVE_URL"] != nil),
    .serialized,
    .engineGate
)
@MainActor
struct LiveStreamSmokeTests {
    private let output = "/tmp/panop-live-probe.txt"

    private var url: String {
        ProcessInfo.processInfo.environment["PANOP_LIVE_URL"] ?? ""
    }

    private var seconds: Double {
        Double(ProcessInfo.processInfo.environment["PANOP_LIVE_SECONDS"] ?? "") ?? 25
    }

    private func line(_ text: String, since start: ContinuousClock.Instant) {
        let elapsed = ContinuousClock.now - start
        let value = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let entry = String(format: "[%6.2f s] ", value) + text + "\n"
        if let handle = FileHandle(forWritingAtPath: output) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(toFile: output, atomically: true, encoding: .utf8)
        }
    }

    @Test
    func `through the coordinator with only VLC`() async throws {
        try? FileManager.default.removeItem(atPath: output)
        let start = ContinuousClock.now
        line("coordinator, VLC only: \(url)", since: start)
        try await run(priority: [.vlcKit], start: start)
    }

    @Test
    func `through the coordinator with only LumeEngine`() async throws {
        let start = ContinuousClock.now
        line("", since: start)
        line("coordinator, LumeEngine only: \(url)", since: start)
        try await run(priority: [.lumeEngine], start: start)
    }

    @Test
    func `through the coordinator with AVPlayer then VLC`() async throws {
        let start = ContinuousClock.now
        line("", since: start)
        line("coordinator, AVPlayer then VLC: \(url)", since: start)
        try await run(priority: [.avPlayer, .vlcKit], start: start)
    }

    private func run(priority: [PlaybackEngineKind], start: ContinuousClock.Instant) async throws {
        // libVLC's own log says why a stream stays "opening", which the engine cannot.
        let logPath = "/tmp/panop-vlc-log.txt"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            let logger = VLCFileLogger.create(with: handle)
            logger.level = VLCLogLevel(rawValue: 3) ?? .info
            VLCConnectionWatch.shared.install(alongside: [logger])
        }
        let coordinator = PlaybackCoordinator(priority: priority, makeEngine: { EngineRegistry.make($0) })
        let attacher = SurfaceAttacher(coordinator)
        defer { attacher.stop() }
        let collector = Task {
            for await event in coordinator.events {
                line("coordinator: \(event)", since: start)
            }
        }
        defer { collector.cancel() }

        coordinator.play(PlaybackRequest(PlaybackItem(url: url, mediaKind: .live)))

        // Also tap the active engine's own events, which the coordinator does not republish.
        var watched: ObjectIdentifier?
        var taps: [Task<Void, Never>] = []
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let engine = coordinator.activeEngine, watched != ObjectIdentifier(engine) {
                watched = ObjectIdentifier(engine)
                let name = String(describing: type(of: engine))
                taps.append(Task { [line] in
                    // Engine events are single-consumer; the coordinator owns them, so
                    // sample state instead.
                    _ = line
                    _ = name
                })
                line("active engine: \(name) duration=\(String(describing: engine.duration))", since: start)
            }
            if let engine = coordinator.activeEngine {
                line("  sample: state=\(engine.state) position=\(String(describing: engine.position))", since: start)
            }
            try await Task.sleep(for: .milliseconds(1000))
        }
        taps.forEach { $0.cancel() }
        line("final status: \(coordinator.status)", since: start)
        await coordinator.stop()
    }

    #if os(macOS)
        /// The real `PlayerView`, hosted in a window, so SwiftUI owns the video surface as it
        /// does in the app. The coordinator on its own behaves differently from the screen.
        @Test
        func `through the real player view with VLC`() async throws {
            let start = ContinuousClock.now
            line("", since: start)
            line("real PlayerView, VLC first: \(url)", since: start)
            try await hostPlayerView(preferred: .vlcKit, start: start)
        }

        @Test
        func `through the real player view with AVPlayer`() async throws {
            let start = ContinuousClock.now
            line("", since: start)
            line("real PlayerView, AVPlayer first: \(url)", since: start)
            try await hostPlayerView(preferred: .avPlayer, start: start)
        }

        private func hostPlayerView(preferred: PlaybackEngineKind, start: ContinuousClock.Instant) async throws {
            let model = PlayerModel(
                title: "Smoke",
                request: PlaybackRequest(PlaybackItem(url: url, mediaKind: .live)),
                preferred: preferred
            )
            let hosting = NSHostingView(rootView: PlayerView(model: model).frame(width: 800, height: 450))
            hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.close() }

            var last = ""
            let deadline = ContinuousClock.now + .seconds(seconds)
            while ContinuousClock.now < deadline {
                let engine = model.engine.map { String(describing: type(of: $0)) } ?? "none"
                let now = "status=\(model.status) engine=\(engine) notice=\(model.notice ?? "-")"
                if now != last {
                    line(now, since: start)
                    last = now
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            line("final: \(model.status), join \(String(describing: model.joinTime))", since: start)
            await model.stop()
        }
    #endif
}
