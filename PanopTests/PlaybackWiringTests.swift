import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

private let credentials = ProviderCredentials(
    baseURL: "http://panel.example:8080",
    username: "alice",
    password: "s3cret"
)

private func target(
    kind: MediaKind = .live,
    streamURL: String? = nil,
    remoteID: String? = "42",
    containerExtension: String? = nil
) -> PlaybackTarget {
    PlaybackTarget(
        playlist: "p",
        entryID: "e",
        kind: kind,
        name: "Channel",
        streamURL: streamURL,
        remoteID: remoteID,
        containerExtension: containerExtension
    )
}

private func build(_ target: PlaybackTarget, source: PlaylistSource?) throws -> PlaybackRequest {
    try PlaybackRequestBuilder.request(for: target, source: source, transport: StubTransport { _ in (200, "") })
}

@Suite("Playback request building")
struct PlaybackRequestBuilderTests {
    /// AVPlayer cannot read a raw transport stream, so it is offered HLS. The
    /// FFmpeg-based engines read the raw stream directly and with less delay.
    @Test
    func `an Xtream live channel is HLS for AVPlayer and a raw stream for the rest`() throws {
        let request = try build(target(), source: .xtream(credentials))

        #expect(request.item(.avPlayer).url == "http://panel.example:8080/live/alice/s3cret/42.m3u8")
        #expect(request.item(.vlcKit).url == "http://panel.example:8080/live/alice/s3cret/42.ts")
        #expect(request.item(.lumeEngine).url == "http://panel.example:8080/live/alice/s3cret/42.ts")
        #expect(request.item(.avPlayer).mediaKind == .live)
        #expect(request.item(.avPlayer).title == "Channel")
    }

    @Test
    func `an Xtream movie uses its container extension`() throws {
        let request = try build(target(kind: .movie, containerExtension: "mkv"), source: .xtream(credentials))
        #expect(request.item(.avPlayer).url == "http://panel.example:8080/movie/alice/s3cret/42.mkv")
        #expect(request.item(.vlcKit).url == request.item(.avPlayer).url)
    }

    @Test
    func `an M3U entry plays its own address on every engine`() throws {
        let request = try build(
            target(streamURL: "http://host/live/9.ts", remoteID: nil),
            source: .remoteM3U("http://x")
        )
        #expect(request.item(.avPlayer).url == "http://host/live/9.ts")
        #expect(request.item(.vlcKit).url == "http://host/live/9.ts")
    }

    @Test
    func `a direct source wins over building an address`() throws {
        let request = try build(target(streamURL: "http://cdn/direct.m3u8"), source: .xtream(credentials))
        #expect(request.item(.avPlayer).url == "http://cdn/direct.m3u8")
    }

    @Test
    func `a series shell is not playable`() {
        #expect(throws: PlaybackTargetError.self) {
            try build(target(kind: .series), source: .xtream(credentials))
        }
    }

    @Test
    func `an entry with no address and no Xtream login says so`() {
        #expect(throws: PlaybackTargetError.self) { try build(target(remoteID: nil), source: .xtream(credentials)) }
        #expect(throws: PlaybackTargetError.self) { try build(target(), source: nil) }
        #expect(throws: PlaybackTargetError.self) { try build(target(), source: .remoteM3U("http://x")) }
    }

    @Test
    func `an unusable server address is reported`() {
        let bad = ProviderCredentials(baseURL: "not a url", username: "a", password: "b")
        #expect(throws: PlaybackTargetError.self) { try build(target(), source: .xtream(bad)) }
    }
}

@Suite("Playback messages")
struct PlaybackMessagesTests {
    @Test
    func `a fallback names both engines`() {
        let text = PlaybackMessages.text(for: .fellBack(
            from: .avPlayer,
            to: .vlcKit,
            reason: PlaybackError(code: .unsupportedFormat)
        ))
        #expect(text.contains("AVPlayer"))
        #expect(text.contains("VLC"))
    }

    @Test
    func `a format failure says the players cannot open the format`() {
        let failure = PlaybackFailure(attempts: [
            PlaybackAttempt(engine: .avPlayer, error: PlaybackError(code: .unsupportedFormat)),
            PlaybackAttempt(engine: .vlcKit, error: nil)
        ])
        let text = PlaybackMessages.text(for: failure)
        #expect(text.contains("format"))
        #expect(text.contains("Tried: AVPlayer"))
        #expect(text.contains("Not available yet: VLC"))
    }

    @Test
    func `a network failure points at the connection`() {
        let failure = PlaybackFailure(attempts: [PlaybackAttempt(
            engine: .avPlayer,
            error: PlaybackError(code: .network)
        )])
        #expect(PlaybackMessages.text(for: failure).contains("connection"))
    }

    @Test
    func `nothing to try at all is stated plainly`() {
        let failure = PlaybackFailure(attempts: [PlaybackAttempt(engine: .vlcKit, error: nil)])
        #expect(PlaybackMessages.text(for: failure).contains("needs a player"))
    }

    @Test
    func `an engine is listed once however often it was tried`() {
        let error = PlaybackError(code: .network)
        let failure = PlaybackFailure(attempts: [
            PlaybackAttempt(engine: .avPlayer, error: error),
            PlaybackAttempt(engine: .avPlayer, error: error),
            PlaybackAttempt(engine: .avPlayer, error: error)
        ])
        #expect(PlaybackMessages.text(for: failure).components(separatedBy: "AVPlayer").count == 2)
    }
}

@Suite("Engine registry")
struct EngineRegistryTests {
    @Test
    func `only engines with an adapter are offered`() {
        #if os(macOS)
            // FFmpegKit's macOS frameworks cannot be embedded, so KSPlayer is linked on iOS and tvOS only.
            #expect(EngineRegistry.selectable == [.avPlayer, .vlcKit, .lumeEngine, .aetherEngine])
        #else
            #expect(EngineRegistry.selectable == [.avPlayer, .vlcKit, .lumeEngine, .aetherEngine, .ksPlayer])
        #endif
    }

    @Test
    @MainActor
    func `an engine builds only where it has an adapter`() {
        #expect(EngineRegistry.make(.avPlayer) != nil)
        #expect(EngineRegistry.make(.vlcKit) != nil)
        #expect(EngineRegistry.make(.lumeEngine) != nil)
        #if os(macOS)
            #expect(EngineRegistry.make(.ksPlayer) == nil, "KSPlayer is not linked on macOS, so it has no adapter")
        #else
            #expect(EngineRegistry.make(.ksPlayer) != nil)
        #endif
    }
}

@Suite("Player model", .serialized, .engineGate)
@MainActor
struct PlayerModelTests {
    private func wav(seconds: Double) throws -> URL {
        let sampleRate = 8000
        let count = Int(Double(sampleRate) * seconds)
        var data = Data()
        func append(_ value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(count * 2))
        for index in 0 ..< count {
            append(Int16(6000 * sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate))))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    private func waitFor(_ condition: () -> Bool, seconds: Double = 10) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test
    func `plays, reports the join time, and exposes the engine to draw`() async throws {
        let url = try wav(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = PlayerModel(
            title: "Test",
            request: PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .movie)),
            preferred: .avPlayer,
            makeEngine: { $0 == .avPlayer ? AVPlayerEngine() : nil }
        )

        model.start()

        #expect(await waitFor { model.status == .playing(.avPlayer) })
        #expect(await waitFor { model.joinTime != nil })
        #expect(model.engine is AVPlayerEngine)
        #if os(tvOS)
            #expect(!model.supportsAirPlay)
        #else
            #expect(model.supportsAirPlay, "AVPlayer is the engine that can AirPlay")
        #endif
        #expect(model.engineName == "AVPlayer")
        #expect(!model.isWorking)
        #expect(model.failureText == nil)
        await model.stop()
        #expect(model.status == .idle)
        #expect(model.engine == nil)
    }

    @Test
    func `pause and resume toggle`() async throws {
        let url = try wav(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = PlayerModel(
            title: "Test",
            request: PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .movie)),
            preferred: .avPlayer,
            makeEngine: { $0 == .avPlayer ? AVPlayerEngine() : nil }
        )
        model.start()
        #expect(await waitFor { model.status == .playing(.avPlayer) })

        model.togglePause()
        #expect(await waitFor { model.isPaused })

        model.togglePause()
        #expect(await waitFor { model.status == .playing(.avPlayer) })
        await model.stop()
    }

    @Test
    func `a fallback is explained to the user`() async throws {
        let good = try wav(seconds: 3)
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 2048).write(to: bad)
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }
        let model = PlayerModel(
            title: "Test",
            request: PlaybackRequest(mediaKind: .live) { kind in
                PlaybackItem(url: (kind == .avPlayer ? bad : good).absoluteString, mediaKind: .live)
            },
            preferred: .avPlayer,
            // Every slot is AVPlayer: only one adapter exists, and what is under
            // test is the model's handling of a real rejection.
            makeEngine: { _ in AVPlayerEngine() }
        )

        model.start()

        #expect(await waitFor { model.notice != nil })
        #expect(model.notice?.contains("couldn't open this stream") == true)
        await model.stop()
    }

    @Test
    func `a stream nothing can open ends in a plain failure message`() async throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data(repeating: 7, count: 2048).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        let model = PlayerModel(
            title: "Test",
            request: PlaybackRequest(PlaybackItem(url: bad.absoluteString, mediaKind: .live)),
            preferred: .avPlayer,
            makeEngine: { $0 == .avPlayer ? AVPlayerEngine() : nil }
        )

        model.start()

        #expect(await waitFor { model.failureText != nil })
        let text = try #require(model.failureText)
        #expect(text.contains("format"))
        #expect(text.contains("AVPlayer"))
        await model.stop()
    }

    /// The report that started this: a bad address showed "Connection dropped".
    @Test
    func `a failed open is not described as a dropped connection`() {
        let text = PlaybackMessages.text(for: .reconnecting(
            engine: .vlcKit,
            reason: PlaybackError(code: .openFailed)
        ))
        #expect(!text.contains("connection"))
        #expect(text.contains("open"))
    }

    @Test
    func `a network drop is described as one`() {
        let text = PlaybackMessages.text(for: .reconnecting(
            engine: .vlcKit,
            reason: PlaybackError(code: .network)
        ))
        #expect(text.contains("connection dropped"))
    }

    @Test
    func `an invalid address is not retried and says so`() {
        #expect(!PlaybackError(code: .invalidAddress).isRetryable)
        let failure = PlaybackFailure(attempts: [PlaybackAttempt(
            engine: .avPlayer,
            error: PlaybackError(code: .invalidAddress)
        )])
        #expect(PlaybackMessages.text(for: failure).contains("address"))
    }
}

struct PlaybackAddressValidationTests {
    private func target(_ url: String) -> PlaybackTarget {
        PlaybackTarget(playlist: "p", entryID: "e", kind: .live, name: "X", streamURL: url)
    }

    @Test(arguments: ["/hls/live/1/1.m3u8", "1.m3u8", "http:///nohost.ts", "not a url"])
    func `an address with no scheme or host is refused with a clear message`(url: String) {
        #expect(throws: PlaybackTargetError.self) {
            try PlaybackRequestBuilder.request(
                for: target(url),
                source: nil,
                transport: StubTransport { _ in (404, "") }
            )
        }
    }

    @Test(arguments: [
        "http://host/a.ts", "https://host/a.m3u8", "udp://@239.1.1.1:1234",
        "rtmp://host/app/stream", "file:///tmp/a.ts"
    ])
    func `complete addresses are accepted`(url: String) throws {
        _ = try PlaybackRequestBuilder.request(
            for: target(url),
            source: nil,
            transport: StubTransport { _ in (404, "") }
        )
    }

    @Test
    func `a film resumes where it was left, and a channel never does`() throws {
        let movie = PlaybackTarget(
            playlist: "p", entryID: "m", kind: .movie, name: "Film",
            streamURL: "http://host/movie/1.mp4", resumeAt: 1234
        )
        let channel = PlaybackTarget(
            playlist: "p", entryID: "c", kind: .live, name: "Chan",
            streamURL: "http://host/live/1.ts", resumeAt: 99
        )

        let film = try PlaybackRequestBuilder.request(
            for: movie,
            source: nil,
            transport: StubTransport { _ in (404, "") }
        )
        let live = try PlaybackRequestBuilder.request(
            for: channel,
            source: nil,
            transport: StubTransport { _ in (404, "") }
        )

        #expect(film.item(.avPlayer).startPosition == 1234)
        #expect(live.item(.avPlayer).startPosition == nil, "a live channel has nothing to resume")
    }
}
