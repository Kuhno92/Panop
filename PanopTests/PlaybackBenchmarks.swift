import AVFoundation
import Foundation
@testable import Panop
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
    .serialized
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
}
