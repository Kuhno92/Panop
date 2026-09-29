import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// A short mono 16-bit sine wave as a WAV file, generated at test time. AVPlayer
/// plays it like any other media, so these tests run the real engine with no
/// network and no committed fixture.
private func writeWAV(seconds: Double, name: String = UUID().uuidString) throws -> URL {
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
    append(UInt16(1)) // PCM
    append(UInt16(1)) // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: "data".utf8)
    append(UInt32(count * 2))
    for index in 0 ..< count {
        append(Int16(6000 * sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate))))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
    try data.write(to: url)
    return url
}

private func writeGarbage(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    try Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)
    return url
}

/// A short H.264 video of solid colour frames, written with AVAssetWriter. Real
/// video, so it exercises the surface, not just the audio path.
func writeVideo(seconds: Double) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    let size = 64
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: size,
        AVVideoHeightKey: size
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size,
        kCVPixelBufferHeightKey as String: size
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frames = Int(seconds * 10)
    for frame in 0 ..< frames {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(frame * 20 % 255), CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else {
        throw writer.error ?? PlaybackError(code: .internalError, message: "could not write test video")
    }
    return url
}

/// Collects an engine's events in the background.
@MainActor
private final class Recorder {
    private(set) var events: [PlaybackEvent] = []
    private var task: Task<Void, Never>?

    init(_ engine: AVPlayerEngine) {
        let stream = engine.events
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    func wait(for matches: (PlaybackEvent) -> Bool, seconds: Double = 8) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if events.contains(where: matches) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    var finished: Bool {
        task?.isCancelled == true
    }
}

@Suite("AVPlayer engine", .serialized)
@MainActor
struct AVPlayerEngineTests {
    // MARK: - Playing real media

    @Test
    func `loads a file and reports it ready with its duration`() async throws {
        let url = try writeWAV(seconds: 1.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))

        #expect(await recorder.wait {
            if case .ready = $0 {
                true
            } else {
                false
            }
        })
        let duration = try #require(engine.duration)
        #expect(abs(duration - 1.5) < 0.1)
        #expect(engine.state == .buffering)
        await engine.stop()
    }

    @Test
    func `plays through to the end`() async throws {
        let url = try writeWAV(seconds: 1.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))

        engine.play()

        #expect(await recorder.wait { $0 == .stateChanged(.playing) })
        #expect(await recorder.wait { $0 == .ended })
        await engine.stop()
    }

    @Test
    func `pausing is reported and playing resumes`() async throws {
        let url = try writeWAV(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) })

        engine.pause()
        #expect(await recorder.wait { $0 == .stateChanged(.paused) })

        engine.play()
        #expect(await recorder.wait { event in
            if case .stateChanged(.playing) = event {
                recorder.events.filter { $0 == .stateChanged(.playing) }.count >= 2
            } else {
                false
            }
        })
        await engine.stop()
    }

    @Test
    func `a resume position is applied at load`() async throws {
        let url = try writeWAV(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()

        try await engine.load(PlaybackItem(url: url.absoluteString, startPosition: 4, mediaKind: .movie))

        let position = try #require(engine.position)
        #expect(abs(position - 4) < 0.5)
        await engine.stop()
    }

    @Test
    func `seeking moves the position`() async throws {
        let url = try writeWAV(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))

        engine.seek(to: 3)
        try await Task.sleep(for: .milliseconds(300))

        let position = try #require(engine.position)
        #expect(abs(position - 3) < 0.5)
        await engine.stop()
    }

    @Test
    func `stopping releases the item and ends the event stream`() async throws {
        let url = try writeWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()

        await engine.stop()

        #expect(engine.player.currentItem == nil)
        #expect(engine.state == .idle)
        // The stream must finish, or a consumer would wait on it forever.
        var iterator = engine.events.makeAsyncIterator()
        var drained = 0
        while await iterator.next() != nil, drained < 100 {
            drained += 1
        }
        #expect(drained < 100)
    }

    // MARK: - Video reaches the surface

    /// The audio fixtures cannot show a black-screen bug. This one plays real
    /// video and waits for the layer that draws it to say it has a picture.
    @Test
    func `real video reaches the surface`() async throws {
        let url = try await writeVideo(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        let view = PlayerLayerView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        view.playerLayer.player = engine.player

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()

        let deadline = ContinuousClock.now + .seconds(10)
        while !view.playerLayer.isReadyForDisplay, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(view.playerLayer.isReadyForDisplay, "the layer never received a picture")
        #expect(view.playerLayer.videoRect.width > 0)
        #expect(engine.duration.map { abs($0 - 3) < 0.3 } == true)
        await engine.stop()
    }

    // MARK: - What AVFoundation reports for streams it cannot play

    /// This decides whether fallback happens for real: an unplayable format has to
    /// come out as `unsupportedFormat` (try another engine), not as something the
    /// coordinator would retry.
    @Test(arguments: ["stream.mp4", "stream.mov", "stream.m4a", "stream.mp3"])
    func `bytes that are not media report an unsupported format`(name: String) async throws {
        let url = try writeGarbage(named: name)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()

        let error = await capturedError { try await engine.load(PlaybackItem(url: url.absoluteString)) }

        #expect(error?.code == .unsupportedFormat, "got \(String(describing: error))")
        #expect(error?.isRetryable == false)
        await engine.stop()
    }

    @Test
    func `a missing file fails to open`() async {
        let engine = AVPlayerEngine()
        let error = await capturedError {
            try await engine.load(PlaybackItem(url: "file:///nonexistent/\(UUID().uuidString).mp4"))
        }
        #expect(error != nil)
        await engine.stop()
    }

    @Test
    func `an address that is not a URL fails without touching the network`() async {
        let engine = AVPlayerEngine()
        let error = await capturedError { try await engine.load(PlaybackItem(url: "not a url")) }
        #expect(error?.code == .openFailed)
        await engine.stop()
    }

    // MARK: - Error translation

    @Test
    func `AVFoundation format errors become unsupportedFormat`() {
        for code in [
            AVError.Code.fileFormatNotRecognized,
            .fileFailedToParse,
            .failedToParse,
            .decoderNotFound,
            .formatUnsupported
        ] {
            let error = NSError(domain: AVFoundationErrorDomain, code: code.rawValue)
            #expect(AVPlayerEngine.map(error).code == .unsupportedFormat, "\(code)")
        }
    }

    /// AVFoundation uses different, sometimes unnamed, codes per container
    /// (measured: -11829 MP4, -11828 MKV, -11849 MP3/TS). A code nobody listed
    /// must still mean "try another engine", not "retry this one".
    @Test(arguments: [-11849, -11800, -11999, -1])
    func `an unlisted AVFoundation code is still not retried`(code: Int) {
        let mapped = AVPlayerEngine.map(NSError(domain: AVFoundationErrorDomain, code: code))
        #expect(mapped.code == .unsupportedFormat)
        #expect(!mapped.isRetryable)
    }

    @Test
    func `undecodable media is a decode failure that is not retried`() {
        let error = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.undecodableMediaData.rawValue)
        let mapped = AVPlayerEngine.map(error)
        #expect(mapped.code == .decodeFailed)
        #expect(!mapped.isRetryable)
    }

    @Test(arguments: [
        NSURLErrorTimedOut,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost
    ])
    func `URL errors are network failures that can be retried`(code: Int) {
        let mapped = AVPlayerEngine.map(NSError(domain: NSURLErrorDomain, code: code))
        #expect(mapped.code == .network)
        #expect(mapped.isRetryable)
    }

    /// AVFoundation wraps the real cause. A dropped connection must still read as
    /// a network failure however deep it is.
    @Test
    func `a network failure nested inside an AVFoundation error is still a network failure`() {
        let inner = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let middle = NSError(domain: "CoreMediaErrorDomain", code: -12889, userInfo: [NSUnderlyingErrorKey: inner])
        let outer = NSError(domain: AVFoundationErrorDomain, code: -11800, userInfo: [NSUnderlyingErrorKey: middle])
        #expect(AVPlayerEngine.map(outer).code == .network)
    }

    @Test
    func `errors from outside AVFoundation are a failure to open, and no error is internal`() {
        #expect(AVPlayerEngine.map(NSError(domain: "Something", code: 1)).code == .openFailed)
        #expect(AVPlayerEngine.map(nil).code == .internalError)
    }

    // MARK: - Through the coordinator, on real AVFoundation

    @Test
    func `the coordinator plays a file through the real engine`() async throws {
        let url = try writeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer],
            makeEngine: { $0 == .avPlayer ? AVPlayerEngine() : nil }
        )
        let states = StatusWatcher(coordinator)

        coordinator.play(PlaybackRequest(PlaybackItem(url: url.absoluteString, mediaKind: .movie)))

        #expect(await states.wait(for: .playing(.avPlayer)))
        await coordinator.stop()
    }

    /// The scenario the whole design exists for, on real AVFoundation: the first
    /// engine cannot read the stream, so the second is used, with the reason kept.
    @Test
    func `an unplayable stream falls through to the next engine with its reason`() async throws {
        let good = try writeWAV(seconds: 3)
        let bad = try writeGarbage(named: "channel.mp4")
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }
        // Both engine slots are AVPlayer here (only one adapter exists yet); the
        // point is the coordinator's response to a real AVFoundation rejection.
        let coordinator = PlaybackCoordinator(
            priority: [.avPlayer, .vlcKit],
            makeEngine: { _ in AVPlayerEngine() }
        )
        let states = StatusWatcher(coordinator)
        let request = PlaybackRequest(mediaKind: .live) { kind in
            PlaybackItem(url: (kind == .avPlayer ? bad : good).absoluteString, mediaKind: .live)
        }

        coordinator.play(request)

        #expect(await states.wait(for: .playing(.vlcKit)))
        let notice = states.notices.first
        guard case let .fellBack(from, to, reason)? = notice else {
            Issue.record("the fallback was silent: \(states.notices)")
            return
        }
        #expect(from == .avPlayer)
        #expect(to == .vlcKit)
        #expect(reason.code == .unsupportedFormat)
        await coordinator.stop()
    }

    /// A malformed HLS playlist does not fail in AVPlayer: it stays "unknown"
    /// indefinitely (measured). Nothing but the coordinator's timeout can rescue
    /// that, which is why silence has to be treated as a failure.
    @Test
    func `a stream that never fails is timed out and the next engine is used`() async throws {
        let good = try writeWAV(seconds: 3)
        let silent = try writeGarbage(named: "channel.m3u8")
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: silent)
        }
        let coordinator = PlaybackCoordinator(
            policy: PlaybackPolicy(openTimeout: .seconds(1), maxOpenRetries: 0),
            priority: [.avPlayer, .vlcKit],
            makeEngine: { _ in AVPlayerEngine() }
        )
        let states = StatusWatcher(coordinator)
        let request = PlaybackRequest(mediaKind: .live) { kind in
            PlaybackItem(url: (kind == .avPlayer ? silent : good).absoluteString, mediaKind: .live)
        }

        coordinator.play(request)

        #expect(await states.wait(for: .playing(.vlcKit), seconds: 15))
        guard case let .fellBack(_, _, reason)? = states.notices.first else {
            Issue.record("the fallback was silent: \(states.notices)")
            return
        }
        #expect(reason.code == .network, "a timeout is reported as a network failure")
        await coordinator.stop()
    }

    // MARK: - Helpers

    private func capturedError(_ body: () async throws -> Void) async -> PlaybackError? {
        do {
            try await body()
            return nil
        } catch let error as PlaybackError {
            return error
        } catch {
            return PlaybackError(code: .internalError, message: "\(error)")
        }
    }
}

@MainActor
private final class StatusWatcher {
    private(set) var statuses: [PlaybackStatus] = []
    private(set) var notices: [PlaybackNotice] = []
    private var task: Task<Void, Never>?

    init(_ coordinator: PlaybackCoordinator) {
        let stream = coordinator.events
        task = Task { [weak self] in
            for await event in stream {
                switch event {
                case let .status(status): self?.statuses.append(status)
                case let .notice(notice): self?.notices.append(notice)
                default: break
                }
            }
        }
    }

    func wait(for status: PlaybackStatus, seconds: Double = 10) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if statuses.contains(status) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
