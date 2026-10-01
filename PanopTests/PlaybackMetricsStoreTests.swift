import Foundation
@testable import Panop
import PanopPlayback
import Testing

@Suite("Playback metrics store")
struct PlaybackMetricsStoreTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("metrics-\(UUID().uuidString).json")
    }

    private func record(_ join: Double = 0.3) -> PlaybackSessionRecord {
        PlaybackSessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            mediaKind: .live,
            engine: .avPlayer,
            joinSeconds: join,
            playedSeconds: 60,
            outcome: .watched
        )
    }

    @Test
    func `sessions survive a new launch`() async {
        let url = file()
        let first = PlaybackMetricsStore(file: url)
        await first.append(record(0.2))
        await first.append(record(0.4))

        let later = PlaybackMetricsStore(file: url)

        #expect(await later.all().count == 2)
        #expect(await later.statistics().medianJoinSeconds == 0.2)
    }

    @Test
    func `only the most recent are kept`() async {
        let store = PlaybackMetricsStore(file: file())
        for index in 0 ..< (PlaybackMetricsStore.capacity + 25) {
            await store.append(record(Double(index)))
        }

        let all = await store.all()

        #expect(all.count == PlaybackMetricsStore.capacity)
        #expect(all.first?.joinSeconds == 25, "the oldest were dropped")
    }

    @Test
    func `clearing empties it and removes the file`() async {
        let url = file()
        let store = PlaybackMetricsStore(file: url)
        await store.append(record())

        await store.clear()

        #expect(await store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `a damaged file starts it empty and does not stop the app`() async throws {
        let url = file()
        try Data("not json at all".utf8).write(to: url)

        let store = PlaybackMetricsStore(file: url)

        #expect(await store.all().isEmpty)
        await store.append(record())
        #expect(await store.all().count == 1)
    }
}
