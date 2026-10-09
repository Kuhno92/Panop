import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// The reason a second engine exists, proven on real bytes: a raw MPEG-TS stream over
/// HTTP, served the way an IPTV provider serves a live channel.
@Suite("Raw transport stream over HTTP", .serialized, .engineGate)
@MainActor
struct RawTransportStreamTests {
    @Test
    func `the fixture is a real transport stream`() async throws {
        let stream = try await TransportStreamFixture.shared()
        #expect(stream[0] == 0x47, "a transport stream starts with the sync byte")
        #expect(stream.count % 188 == 0, "and is made of 188-byte packets")
        #expect(stream.count > 188 * 20)
    }

    @Test
    func `VLC plays it`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        var events: [PlaybackEvent] = []
        let collector = Task { for await event in engine.events {
            events.append(event)
        } }
        defer { collector.cancel() }

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()

        #expect(await waitFor { events.contains(.stateChanged(.playing)) })
        await engine.stop()
    }

    /// What AVPlayer does with the same bytes decides whether the fallback ever fires.
    @Test
    func `AVPlayer cannot, and says so in a way that triggers fallback`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }
        let engine = AVPlayerEngine()

        let outcome = await withTimeout(seconds: 20) {
            do {
                try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
                return "loaded"
            } catch let error as PlaybackError {
                return "failed:\(error.code.rawValue)"
            } catch {
                return "other"
            }
        }
        await engine.stop()
        try? outcome.write(toFile: "/tmp/panop-avplayer-ts-outcome.txt", atomically: true, encoding: .utf8)

        // Either AVPlayer refuses the format (the fallback path) or it never answers
        // (the coordinator's timeout path). It must not load it.
        #expect(outcome == "failed:unsupportedFormat" || outcome == "timed out", "AVPlayer said: \(outcome)")
    }

    /// The whole point, end to end on real engines and real bytes: AVPlayer is tried
    /// first, cannot read the stream, and VLC takes over by itself.
    @Test
    func `the coordinator falls back from AVPlayer to VLC and plays it`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }

        let coordinator = PlaybackCoordinator(
            // Short, because AVPlayer may not answer at all and the wait is the timeout.
            policy: PlaybackPolicy(openTimeout: .seconds(4), startTimeout: .seconds(8), maxOpenRetries: 0),
            priority: [.avPlayer, .vlcKit],
            makeEngine: { EngineRegistry.make($0) }
        )
        let attacher = SurfaceAttacher(coordinator)
        defer { attacher.stop() }
        var statuses: [PlaybackStatus] = []
        var notices: [PlaybackNotice] = []
        let collector = Task {
            for await event in coordinator.events {
                switch event {
                case let .status(status): statuses.append(status)
                case let .notice(notice): notices.append(notice)
                default: break
                }
            }
        }
        defer { collector.cancel() }

        coordinator.play(PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .live)))

        #expect(await waitFor(seconds: 30) { statuses.contains(.playing(.vlcKit)) }, "statuses: \(statuses)")
        let fallback = notices.compactMap { notice -> (PlaybackEngineKind, PlaybackEngineKind)? in
            if case let .fellBack(from, to, _) = notice {
                (from, to)
            } else {
                nil
            }
        }.first
        #expect(fallback?.0 == .avPlayer)
        #expect(fallback?.1 == .vlcKit)
        await coordinator.stop()
    }

    /// With a short stall tolerance, any spurious "buffering" would trigger a
    /// reconnect. A healthy stream must be left alone.
    @Test(.needsAudioDevice)
    func `a healthy VLC stream is not reconnected`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }

        let coordinator = PlaybackCoordinator(
            policy: PlaybackPolicy(openTimeout: .seconds(4), startTimeout: .seconds(8), stallTolerance: .seconds(1)),
            priority: [.vlcKit],
            makeEngine: { EngineRegistry.make($0) }
        )
        var reconnects = 0
        var playing = false
        // Surfaces belong on screen: see SurfaceWindow.
        let attacher = SurfaceAttacher(coordinator)
        defer { attacher.stop() }
        let collector = Task {
            for await event in coordinator.events {
                if case .notice(.reconnecting) = event {
                    reconnects += 1
                }
                if case .status(.playing) = event {
                    playing = true
                }
            }
        }
        defer { collector.cancel() }

        coordinator.play(PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .live)))
        #expect(await waitFor { playing })
        try await Task.sleep(for: .seconds(2))

        #expect(reconnects == 0, "a healthy stream was reconnected \(reconnects) times")
        await coordinator.stop()
    }

    // MARK: - Helpers

    private func waitFor(seconds: Double = 20, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Runs `body`, or returns "timed out" if it takes longer.
    private func withTimeout(seconds: Double, _ body: @escaping @MainActor () async -> String) async -> String {
        await withCheckedContinuation { continuation in
            let once = ContinuationOnce(continuation)
            let work = Task { @MainActor in await once.finish(body()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                once.finish("timed out")
                work.cancel()
            }
        }
    }
}

private final class ContinuationOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?

    init(_ continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: String) {
        let taken = lock.withLock {
            let current = continuation
            continuation = nil
            return current
        }
        taken?.resume(returning: value)
    }
}
