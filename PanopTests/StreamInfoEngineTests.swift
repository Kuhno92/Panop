import AVFoundation
import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// A second of silence as a mono 8 kHz WAV: something every engine opens.
private func silentWAV() throws -> URL {
    var data = Data()
    func append(_ value: some FixedWidthInteger) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let count = 8000
    data.append(contentsOf: "RIFF".utf8)
    append(UInt32(36 + count * 2))
    data.append(contentsOf: "WAVEfmt ".utf8)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(8000))
    append(UInt32(16000))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: "data".utf8)
    append(UInt32(count * 2))
    data.append(Data(count: count * 2))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    try data.write(to: url)
    return url
}

@MainActor
private func wait(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return false
}

@Suite("Engines report what they play", .serialized, .engineGate)
@MainActor
struct StreamInfoEngineTests {
    @Test func `the Lume engine reads the container, the picture and the sound of a transport stream`() async throws {
        let server = try await LocalStreamServer(body: TransportStreamFixture.shared())
        let url = try await server.start()
        defer { server.stop() }
        let engine = LumePlaybackEngine()
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .live))
        engine.play()
        let info = try #require(engine.streamInfo)
        #expect(StreamInfoText.container(info.container) == "MPEG-TS")
        #expect((info.width ?? 0) > 0 && (info.height ?? 0) > 0)
        #expect(info.videoCodec != nil)
        await engine.stop()
    }

    @Test func `the AVPlayer engine reads the sound of a file`() async throws {
        let url = try silentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AVPlayerEngine()
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        let appeared = await wait { engine.streamInfo != nil }
        #expect(appeared)
        let info = try #require(engine.streamInfo)
        #expect(StreamInfoText.audioCodec(info.audioCodec) == "PCM")
        #expect(info.audioChannels == 1)
        await engine.stop()
    }

    @Test func `the VLC engine reads the sound of a file`() async throws {
        let url = try silentWAV()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = VLCEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }
        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        let appeared = await wait { engine.streamInfo != nil }
        #expect(appeared)
        let info = try #require(engine.streamInfo)
        #expect(info.audioChannels == 1)
        #expect(info.audioCodec != nil)
        await engine.stop()
    }
}
