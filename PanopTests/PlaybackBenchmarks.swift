import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// How long the player takes to show a first frame, with the network removed.
///
/// Off unless `PANOP_BENCHMARK=1`. It measures the floor: engine creation, load,
/// and first frame for a local file. A real channel adds the provider's response
/// and the stream's own start-up, which this cannot see. Run with
/// `Scripts/test-app.sh --benchmark`; only meaningful in a Release build.
@Suite(
    "Playback benchmarks",
    .enabled(if: ProcessInfo.processInfo.environment["PANOP_BENCHMARK"] == "1"),
    .serialized,
    .engineGate
)
@MainActor
struct PlaybackBenchmarks {
    private func record(_ line: String) {
        print("BENCH \(line)")
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

    @Test
    func `time to first frame for a local file`() async throws {
        let url = try await writeVideo(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        var joins: [Double] = []
        for _ in 0 ..< 20 {
            let coordinator = PlaybackCoordinator(
                priority: [.avPlayer],
                makeEngine: { $0 == .avPlayer ? AVPlayerEngine() : nil }
            )
            var iterator = coordinator.events.makeAsyncIterator()
            coordinator.play(PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .live)))

            while let event = await iterator.next() {
                if case let .joined(_, seconds) = event {
                    joins.append(seconds)
                    break
                }
            }
            await coordinator.stop()
        }

        let sorted = joins.sorted()
        func ms(_ value: Double) -> String {
            String(format: "%.0f ms", value * 1000)
        }
        record("first frame, local file, engine created fresh each time (20 zaps)")
        record("  first (cold): \(ms(joins.first ?? 0))")
        record(
            "  fastest \(ms(sorted.first ?? 0)), median \(ms(sorted[sorted.count / 2])), slowest \(ms(sorted.last ?? 0))"
        )
        #expect(joins.count == 20)
    }

    // MARK: - Every engine, the same way

    /// Time from asking to play until the first frame, each time with a freshly made
    /// engine, which is how the coordinator zaps. Returns nil for a zap that did not
    /// reach a picture.
    private func zap(
        _ kind: PlaybackEngineKind,
        url: String,
        mediaKind: MediaKind
    ) async -> Double? {
        let coordinator = PlaybackCoordinator(
            policy: PlaybackPolicy(openTimeout: .seconds(10), startTimeout: .seconds(10), maxOpenRetries: 0),
            priority: [kind],
            makeEngine: { EngineRegistry.make($0) }
        )
        let attacher = SurfaceAttacher(coordinator)
        defer { attacher.stop() }
        var iterator = coordinator.events.makeAsyncIterator()
        coordinator.play(PlaybackRequest(PlaybackItem(url: url, mediaKind: mediaKind)))
        var joined: Double?
        while let event = await iterator.next() {
            if case let .joined(_, seconds) = event {
                joined = seconds
                break
            }
            if case .status(.failed) = event {
                break
            }
        }
        await coordinator.stop()
        // Let the previous engine finish going away, as a person's pause between zaps would.
        try? await Task.sleep(for: .milliseconds(150))
        return joined
    }

    private func report(_ label: String, _ joins: [Double?]) {
        let ok = joins.compactMap(\.self)
        func ms(_ value: Double) -> String {
            String(format: "%5.0f ms", value * 1000)
        }
        guard !ok.isEmpty else {
            record("  \(label): no zap reached a picture")
            return
        }
        let sorted = ok.sorted()
        record(
            "  \(label): first \(ms(ok[0])), median \(ms(sorted[sorted.count / 2])), " +
                "slowest \(ms(sorted.last ?? 0))" +
                (ok.count < joins.count ? "  (\(joins.count - ok.count) failed)" : "")
        )
    }

    @Test
    func `every engine on the same local video`() async throws {
        let url = try await writeVideo(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        record("first frame, local mp4, 15 zaps each, a fresh engine every time")
        for kind in [PlaybackEngineKind.avPlayer, .vlcKit, .lumeEngine] {
            var joins: [Double?] = []
            for _ in 0 ..< 15 {
                await joins.append(zap(kind, url: url.absoluteString, mediaKind: .movie))
            }
            report(kind.displayName, joins)
        }
    }

    /// The stream most IPTV channels are: raw MPEG-TS over HTTP. AVPlayer cannot read it.
    @Test
    func `the two engines that read a transport stream over HTTP`() async throws {
        let stream = try await TransportStreamFixture.make(seconds: 3)
        let server = try LocalStreamServer(body: stream, holdOpen: true)
        let address = try await server.start()
        defer { server.stop() }
        record("first frame, MPEG-TS over local HTTP, 15 zaps each, a fresh engine every time")
        for kind in [PlaybackEngineKind.vlcKit, .lumeEngine] {
            var joins: [Double?] = []
            for _ in 0 ..< 15 {
                await joins.append(zap(kind, url: address.absoluteString, mediaKind: .live))
            }
            report(kind.displayName, joins)
        }
    }

    /// Real streams over the real network, which the synthetic ones above cannot stand in
    /// for: how long a player waits depends on how much of the stream it wants to see
    /// first, and on a real channel that is time. Needs `PANOP_LIVE_URL`; the numbers
    /// move with the network, so read them as a comparison between engines.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANOP_LIVE_URL"] != nil))
    func `a real stream, each engine`() async throws {
        let address = try #require(ProcessInfo.processInfo.environment["PANOP_LIVE_URL"])
        record("first frame, real stream \(address), 8 zaps each, a fresh engine every time")
        for kind in [PlaybackEngineKind.avPlayer, .vlcKit, .lumeEngine] {
            var joins: [Double?] = []
            for _ in 0 ..< 8 {
                await joins.append(zap(kind, url: address, mediaKind: .live))
            }
            report(kind.displayName, joins)
        }
    }
}
