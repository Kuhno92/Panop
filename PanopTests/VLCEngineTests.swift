import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing
import VLCKit

/// Collects an engine's events in the background.
@MainActor
private final class Recorder {
    private(set) var events: [PlaybackEvent] = []
    private var task: Task<Void, Never>?

    init(_ engine: VLCEngine) {
        let stream = engine.events
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    func wait(seconds: Double = 15, for matches: (PlaybackEvent) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if events.contains(where: matches) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func count(of event: PlaybackEvent) -> Int {
        events.filter { $0 == event }.count
    }
}

private func writeWAV(seconds: Double) throws -> URL {
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

@Suite("VLC engine", .serialized, .engineGate)
@MainActor
struct VLCEngineTests {
    @Test
    func `plays a file, reports ready with its duration, then ends`() async throws {
        let url = try writeWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()

        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        #expect(await recorder.wait {
            if case .ready = $0 {
                true
            } else {
                false
            }
        })
        let duration = try #require(engine.duration)
        #expect(abs(duration - 2) < 0.3)
        #expect(await recorder.wait { $0 == .ended })
        await engine.stop()
    }

    @Test
    func `pausing and resuming are reported`() async throws {
        let url = try writeWAV(seconds: 20)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })

        engine.pause()
        #expect(await recorder.wait { $0 == .stateChanged(.paused) })

        engine.play()
        #expect(await recorder.wait { _ in recorder.count(of: .stateChanged(.playing)) >= 2 })
        await engine.stop()
    }

    @Test
    func `seeking moves the position`() async throws {
        let url = try writeWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })

        engine.seek(to: 20)
        try await Task.sleep(for: .milliseconds(800))

        let position = try #require(engine.position)
        #expect(position > 19 && position < 24, "position was \(position)")
        await engine.stop()
    }

    @Test
    func `a resume position is applied on the first frame`() async throws {
        let url = try writeWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: url.absoluteString, startPosition: 15, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        try await Task.sleep(for: .milliseconds(500))

        let position = try #require(engine.position)
        #expect(position > 14 && position < 19, "position was \(position)")
        await engine.stop()
    }

    @Test
    func `stopping ends the event stream and does not block the main thread`() async throws {
        let url = try writeWAV(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })

        // Stopping must let the main thread keep running. A ticker on the main actor
        // that keeps ticking while stop runs proves it was not held.
        var ticks = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        await engine.stop()
        ticker.cancel()

        #expect(engine.state == .idle)
        #expect(ticks > 0)
        var iterator = engine.events.makeAsyncIterator()
        var drained = 0
        while await iterator.next() != nil, drained < 200 {
            drained += 1
        }
        #expect(drained < 200, "the event stream never finished")
    }

    /// Regression: a `VLCMediaPlayer` released on the main thread while playing can
    /// deadlock inside libVLC (`vlc_player_Delete` joins a thread that is waiting on the
    /// main queue), which froze a test host and would freeze the app on a channel change.
    /// Engines are dropped here without `stop()`, on the main actor, many times over.
    @Test
    func `dropping a playing engine on the main thread never deadlocks`() async throws {
        let url = try writeWAV(seconds: 30)
        defer { try? FileManager.default.removeItem(at: url) }

        // A hang would block the main actor, and with it any timeout on it. This one
        // runs on its own thread and turns a hang into a failure.
        let finished = Flag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
            if !finished.isSet {
                fatalError("libVLC deadlocked while a player was released on the main thread")
            }
        }

        for _ in 0 ..< 12 {
            var engine: VLCEngine? = VLCEngine()
            let window = engine.map { SurfaceWindow($0.surface) }
            try await engine?.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
            engine?.play()
            let deadline = ContinuousClock.now + .seconds(10)
            while engine?.state != .playing, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(engine?.state == .playing)
            window?.close()
            engine = nil
            try await Task.sleep(for: .milliseconds(20))
        }
        finished.set()
    }

    /// Regression: buffering progress is 0.0 to 1.0. Read as 0 to 100, a healthy stream
    /// sat in `.buffering` for ever after its first report.
    @Test
    func `a healthy stream settles at playing and stays there`() async throws {
        let url = try writeWAV(seconds: 20)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })

        try await Task.sleep(for: .seconds(2))

        #expect(engine.state == .playing, "stuck in \(engine.state)")
        // Anything it buffered, it must also have come back from.
        let buffering = recorder.count(of: .stateChanged(.buffering))
        #expect(recorder.count(of: .stateChanged(.playing)) > buffering)
        await engine.stop()
    }

    /// libVLC crashes the process if it renders into a view that is not on screen, so
    /// the engine holds back until the surface is in a window.
    @Test
    func `play waits for the surface to be on screen`() async throws {
        let url = try writeWAV(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))

        engine.play()
        try await Task.sleep(for: .seconds(1))
        #expect(engine.state != .playing, "it started drawing with nowhere to draw")
        #expect(recorder.count(of: .stateChanged(.playing)) == 0)

        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        await engine.stop()
    }

    /// Real video, pulled off screen mid-stream (the player was dismissed). This used to
    /// take the process down from libVLC's render thread.
    @Test
    func `video survives its surface leaving the screen`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream)
        let url = try await server.start()
        defer { server.stop() }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        try await Task.sleep(for: .milliseconds(800))

        window.detach()
        try await Task.sleep(for: .milliseconds(1500))

        await engine.stop()
    }

    @Test
    func `an address that is not a URL fails without playing`() async throws {
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        await #expect(throws: PlaybackError.self) {
            try await engine.load(PlaybackItem(url: "not a url"))
        }
        await engine.stop()
    }

    /// The case that matters: libVLC given something it cannot open. It may raise an
    /// error, or it may just stop; either way the engine has to say it failed.
    @Test(arguments: ["stream.mp4", "stream.ts", "stream.mkv"])
    func `bytes that are not media are reported as a failure`(name: String) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))

        engine.play()

        let failed = await recorder.wait(seconds: 20) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        #expect(failed, "libVLC gave up without telling anyone: \(recorder.events)")
        await engine.stop()
    }

    @Test
    func `a missing file is reported as a failure`() async throws {
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: "file:///nonexistent/\(UUID().uuidString).mp4"))

        engine.play()

        #expect(await recorder.wait(seconds: 20) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        })
        await engine.stop()
    }

    /// libVLC logs why it cannot reach a stream and fires no error event, so without this
    /// the engine sat "opening" until the coordinator's timeout (seen on an HTTPS stream
    /// whose TLS handshake failed). The text is libVLC's own.
    @Test
    func `a TLS failure logged while opening fails the engine as one another engine may not share`() async throws {
        let engine = VLCEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: "https://stream.invalid/live.m3u8"))

        VLCConnectionWatch.shared.handleMessage("TLS session handshake error", logLevel: .error, context: nil)

        #expect(await recorder.wait(seconds: 5) {
            if case let .failed(error) = $0 {
                error.code == .secureConnectionFailed
            } else {
                false
            }
        })
        await engine.stop()
    }

    @Test
    func `a plain connection failure is still a retryable network error`() async throws {
        let engine = VLCEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: "https://stream.invalid/live.m3u8"))

        VLCConnectionWatch.shared.handleMessage("HTTP connection failure", logLevel: .error, context: nil)

        #expect(await recorder.wait(seconds: 5) {
            if case let .failed(error) = $0 {
                error.code == .network && error.isRetryable
            } else {
                false
            }
        })
        await engine.stop()
    }

    @Test
    func `libVLC's lines are told apart`() {
        #expect(VLCConnectionWatch.failure(in: "TLS session handshake error") == .secureConnectionFailed)
        #expect(VLCConnectionWatch.failure(in: "HTTP connection failure") == .network)
        #expect(VLCConnectionWatch.failure(in: "buffer deadlock prevented") == nil)
        #expect(VLCConnectionWatch.failure(in: "handshake returned error -36") == nil)
    }

    @Test
    func `other libVLC log lines do not fail the engine`() async throws {
        let engine = VLCEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: "https://stream.invalid/live.m3u8"))

        VLCConnectionWatch.shared.handleMessage("buffer deadlock prevented", logLevel: .error, context: nil)
        VLCConnectionWatch.shared.handleMessage("lookup failed (-25300)", logLevel: .warning, context: nil)

        let failed = await recorder.wait(seconds: 0.5) {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        #expect(!failed)
        await engine.stop()
    }

    @Test
    func `a stopped engine is not told about connection failures`() async throws {
        let engine = VLCEngine()
        try await engine.load(PlaybackItem(url: "https://stream.invalid/live.m3u8"))
        await engine.stop()

        VLCConnectionWatch.shared.handleMessage("HTTP connection failure", logLevel: .error, context: nil)

        #expect(engine.state == .idle)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }
}
