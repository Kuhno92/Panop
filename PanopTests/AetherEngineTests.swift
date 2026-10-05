import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

@MainActor
private final class Recorder {
    private(set) var events: [PlaybackEvent] = []
    private var task: Task<Void, Never>?

    init(_ engine: AetherPlaybackEngine) {
        let stream = engine.events
        task = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    func wait(seconds: Double = 30, for matches: (PlaybackEvent) -> Bool) async -> Bool {
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

@Suite("AetherEngine adapter", .serialized, .engineGate)
@MainActor
struct AetherEngineTests {
    @Test
    func `plays a raw transport stream over HTTP`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream, holdOpen: true)
        let url = try await server.start()
        defer { server.stop() }
        let engine = try #require(AetherPlaybackEngine())
        let recorder = Recorder(engine)

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()

        #expect(await recorder.wait { $0 == .stateChanged(.playing) }, "events: \(recorder.events)")
        #expect(await recorder.wait(for: isReady))
        #expect(engine.duration == nil, "a live stream has no duration")
        await engine.stop()
        #expect(engine.state == .idle)
    }

    @Test
    func `play then pause is applied in that order`() async throws {
        let stream = try await TransportStreamFixture.shared()
        let server = try LocalStreamServer(body: stream, holdOpen: true)
        let url = try await server.start()
        defer { server.stop() }
        let engine = try #require(AetherPlaybackEngine())
        let recorder = Recorder(engine)
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))

        engine.play()
        #expect(await recorder.wait { $0 == .stateChanged(.playing) }, "events: \(recorder.events)")
        engine.pause()

        #expect(await recorder.wait { _ in
            guard let playing = recorder.events.firstIndex(of: .stateChanged(.playing)) else { return false }
            return recorder.events[playing...].contains(.stateChanged(.paused))
        }, "events: \(recorder.events)")
        await engine.stop()
    }

    @Test
    func `an address with no scheme is refused without touching the network`() async throws {
        let engine = try #require(AetherPlaybackEngine())
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
    func `a stream that cannot be reached fails the load`() async throws {
        let engine = try #require(AetherPlaybackEngine())
        var error: PlaybackError?
        do {
            // Nothing listens on port 1.
            try await engine.load(PlaybackItem(url: "http://127.0.0.1:1/live.ts", mediaKind: .live))
        } catch let thrown as PlaybackError {
            error = thrown
        } catch {}
        #expect(error != nil, "the load must report the failure and not hang")
        await engine.stop()
    }

    @Test
    func `bytes that are not media fail the load`() async throws {
        let server = try LocalStreamServer(body: Data(repeating: 0x41, count: 64 * 1024), contentType: "video/mp2t")
        let url = try await server.start()
        defer { server.stop() }
        let engine = try #require(AetherPlaybackEngine())
        var error: PlaybackError?
        do {
            try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        } catch let thrown as PlaybackError {
            error = thrown
        } catch {}
        #expect(error != nil)
        await engine.stop()
    }

    @Test
    func `the registry offers it, and the settings picker lists it`() {
        #expect(EngineRegistry.isImplemented(.aetherEngine))
        #expect(EngineRegistry.selectable.contains(.aetherEngine))
    }
}
