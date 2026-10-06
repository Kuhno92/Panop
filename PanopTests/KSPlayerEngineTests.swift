import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import Testing

/// KSPlayer through its adapter, on a generated sound file: the path every KSPlayer stream takes (open, ready,
/// playing, position, end), without a network or a provider.
@Suite("KSPlayer engine", .serialized, .engineGate)
@MainActor
struct KSPlayerEngineTests {
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

    @Test
    func `plays a file, reports ready with its duration, then ends`() async throws {
        let url = try writeWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = KSPlayerEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }

        var events: [PlaybackEvent] = []
        let stream = engine.events
        let collector = Task { for await event in stream {
            events.append(event)
        } }
        defer { collector.cancel() }

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()

        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline, !events.contains(.ended) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(events.contains(.stateChanged(.playing)))
        #expect(events.contains {
            if case .ready = $0 {
                true
            } else {
                false
            }
        })
        #expect(events.contains(.ended), "the file runs out, which the engine reports")
        await engine.stop()
    }

    @Test
    func `a file that is not media fails rather than hangs`() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 2048).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = KSPlayerEngine()
        let window = SurfaceWindow(engine.surface)
        defer { window.close() }

        var failed = false
        let stream = engine.events
        let collector = Task {
            for await event in stream {
                if case .failed = event {
                    failed = true
                }
            }
        }
        defer { collector.cancel() }

        try await engine.load(PlaybackItem(url: url.absoluteString, mediaKind: .movie))
        engine.play()
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline, !failed {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(failed)
        await engine.stop()
    }
}
