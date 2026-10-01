import Foundation
import LumeEngine
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

@MainActor
private final class Recorder {
    private(set) var events: [PlaybackEvent] = []
    private var task: Task<Void, Never>?

    init(_ engine: LumePlaybackEngine) {
        let stream = engine.events
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    func wait(seconds: Double = 20, for matches: (PlaybackEvent) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if events.contains(where: matches) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private func isReady(_ event: PlaybackEvent) -> Bool {
    if case .ready = event {
        true
    } else {
        false
    }
}

@Suite("LumeEngine adapter", .serialized, .engineGate)
@MainActor
struct LumeEngineTests {
    @Test
    func `plays a raw transport stream over HTTP`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }
        let engine = LumePlaybackEngine()
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()

        #expect(await recorder.wait { $0 == .stateChanged(.playing) }, "events: \(recorder.events)")
        #expect(await recorder.wait(for: isReady))
        #expect(engine.duration == nil, "a live stream has no duration")
        await engine.stop()
        #expect(engine.state == .idle)
    }

    /// The commands go to the session one at a time, in order. (The finite test stream
    /// is cut off by the server after a few seconds, which the session reports as a
    /// network error, so this looks at the first moments only.)
    @Test
    func `play then pause is applied in that order`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }
        let engine = LumePlaybackEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))

        engine.play()
        engine.pause()

        #expect(await recorder.wait { _ in
            guard let playing = recorder.events.firstIndex(of: .stateChanged(.playing)) else { return false }
            return recorder.events[playing...].contains(.stateChanged(.paused))
        }, "events: \(recorder.events)")
        await engine.stop()
    }

    @Test
    func `an address with no scheme is refused without touching the network`() async {
        let engine = LumePlaybackEngine()
        var error: PlaybackError?
        do {
            try await engine.load(PlaybackItem(url: "/hls/live/1.m3u8"))
        } catch let thrown as PlaybackError {
            error = thrown
        } catch {}
        #expect(error?.code == .invalidAddress)
        await engine.stop()
    }

    @Test
    func `a stream that cannot be reached fails the load with a retryable error`() async {
        let engine = LumePlaybackEngine()
        var error: PlaybackError?
        do {
            // Nothing listens on port 1.
            try await engine.load(PlaybackItem(url: "http://127.0.0.1:1/live.ts", mediaKind: .live))
        } catch let thrown as PlaybackError {
            error = thrown
        } catch {}
        #expect(error != nil)
        #expect(error?.isRetryable == true, "got \(String(describing: error))")
        await engine.stop()
    }

    @Test
    func `bytes that are not media fail the load`() async throws {
        let server = try LocalStreamServer(body: Data(repeating: 0x41, count: 64 * 1024), contentType: "video/mp2t")
        let url = try await server.start()
        defer { server.stop() }
        let engine = LumePlaybackEngine()
        var error: PlaybackError?
        do {
            try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        } catch let thrown as PlaybackError {
            error = thrown
        } catch {}
        // libVLC-style "format not recognised" is not what FFmpeg reports for this; it
        // says "Input/output error", so the coordinator retries before it moves on.
        #expect(error != nil)
        await engine.stop()
    }

    @Test
    func `engine errors translate to the codes the coordinator acts on`() {
        func code(_ engineCode: EngineError.Code, ffmpeg: Int32? = nil) -> PlaybackError.Code {
            LumePlaybackEngine.map(EngineError(code: engineCode, ffmpegCode: ffmpeg, message: "test")).code
        }
        #expect(code(.ioError) == .network)
        #expect(code(.openFailed) == .openFailed)
        #expect(code(.openFailed, ffmpeg: LumePlaybackEngine.invalidData) == .unsupportedFormat)
        #expect(code(.unsupported) == .unsupportedFormat)
        #expect(code(.decodeFailed) == .decodeFailed)
        #expect(code(.cancelled) == .cancelled)
        #expect(code(.internalError) == .internalError)
    }

    /// AVPlayer cannot read raw MPEG-TS; LumeEngine sits ahead of VLC in the default order,
    /// so it is the one that should pick the stream up.
    @Test
    func `the coordinator falls back from AVPlayer to LumeEngine and plays it`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }

        let coordinator = PlaybackCoordinator(
            policy: PlaybackPolicy(openTimeout: .seconds(4), startTimeout: .seconds(8), maxOpenRetries: 0),
            priority: [.avPlayer, .lumeEngine],
            makeEngine: { EngineRegistry.make($0) }
        )
        var statuses: [PlaybackStatus] = []
        let collector = Task {
            for await event in coordinator.events {
                if case let .status(status) = event {
                    statuses.append(status)
                }
            }
        }
        defer { collector.cancel() }

        coordinator.play(PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .live)))

        #expect(await waitFor(seconds: 30) { statuses.contains(.playing(.lumeEngine)) }, "statuses: \(statuses)")
        await coordinator.stop()
    }

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
}
