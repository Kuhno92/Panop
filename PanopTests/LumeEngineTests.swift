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

    /// The path the one-variant playlist takes: the picker fetches the multivariant playlist,
    /// writes a local file, and the engine reads that file while its entries are on the network.
    /// Three servers stand in for the broadcaster: the multivariant playlist, the variant's
    /// playlist, and its one segment.
    @Test
    func `plays a stream from a multivariant playlist by way of the local one-variant file`() async throws {
        let segments = try await LocalStreamServer(body: TransportStreamFixture.shared())
        let segmentURL = try await segments.start()
        let variant = try LocalStreamServer(
            body: Data("""
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-TARGETDURATION:10
            #EXT-X-MEDIA-SEQUENCE:0
            #EXTINF:5.0,
            \(segmentURL.absoluteString)
            #EXT-X-ENDLIST

            """.utf8),
            contentType: "application/vnd.apple.mpegurl"
        )
        let variantURL = try await variant.start()
        let overview = try LocalStreamServer(
            body: Data("""
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=1000000
            \(variantURL.absoluteString)
            #EXT-X-STREAM-INF:BANDWIDTH=2000000
            \(variantURL.absoluteString)

            """.utf8),
            contentType: "application/vnd.apple.mpegurl"
        )
        let overviewURL = try await overview.start().appendingPathComponent("index.m3u8")
        defer {
            segments.stop()
            variant.stop()
            overview.stop()
        }
        let engine = LumePlaybackEngine()
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: overviewURL.absoluteString, mediaKind: .live))
        engine.play()

        #expect(await recorder.wait(for: isReady), "events: \(recorder.events)")
        let file = try #require(engine.playlistFile, "the engine was given the one-variant file, not the original")
        #expect(FileManager.default.fileExists(atPath: file.path))
        await engine.stop()
        #expect(!FileManager.default.fileExists(atPath: file.path), "the file goes when playback does")
    }

    /// The commands go to the session one at a time, in order. The server holds the
    /// connection open: a finite stream that ends is reported as a network error.
    @Test
    func `play then pause is applied in that order`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream, holdOpen: true)
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

    /// LumeEngine returns subtitle text and draws nothing, so the adapter has to look the
    /// cue up against the playback clock. A sidecar file is the one way to test it without
    /// building a stream with a subtitle track in it.
    @Test
    func `a subtitle file's text shows while it plays and goes when subtitles are switched off`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream, holdOpen: true)
        let url = try await server.start()
        defer { server.stop() }
        let srt = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).srt")
        try "1\n00:00:00,000 --> 00:10:00,000\nHello subtitles\n".write(to: srt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: srt) }
        let engine = LumePlaybackEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        #expect(engine.subtitles.text == nil, "nothing shows before subtitles are on")

        try await engine.loadExternalSubtitles(url: srt.absoluteString)

        #expect(
            await waitFor { engine.subtitles.text == "Hello subtitles" },
            "text: \(String(describing: engine.subtitles.text))"
        )

        engine.selectSubtitleTrack(id: nil)
        #expect(engine.subtitles.text == nil)
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
