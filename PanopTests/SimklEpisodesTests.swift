import Foundation
@testable import Panop
import PanopSimkl
import Testing

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    private var stamp: String

    init(stamp: String) {
        self.stamp = stamp
    }

    func change(_ new: String) {
        lock.withLock { stamp = new }
    }

    func activities() -> SimklActivities {
        lock.withLock { SimklActivities(all: stamp) }
    }

    func shows() -> [SimklWatchedShow] {
        lock.withLock { fetches += 1 }
        return [SimklWatchedShow(tmdbID: 1399, seasons: [
            SimklWatchedSeason(number: 1, episodes: [1, 2]),
            SimklWatchedSeason(number: 2, episodes: [5])
        ])]
    }

    var fetchCount: Int {
        lock.withLock { fetches }
    }
}

@Suite("Episodes watched on Simkl", .serialized, .engineGate)
@MainActor
struct SimklEpisodesTests {
    private func make(_ calls: Calls, at url: URL?) -> SimklEpisodes {
        SimklEpisodes(cacheURL: url, activities: { calls.activities() }, fetch: { calls.shows() })
    }

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/episodes.json")
    }

    @Test
    func `an episode is watched by show, season and number`() async {
        let episodes = make(Calls(stamp: "A"), at: nil)
        await episodes.refresh()

        #expect(episodes.isWatched(show: 1399, season: 1, episode: 2))
        #expect(episodes.isWatched(show: 1399, season: 2, episode: 5))
        #expect(!episodes.isWatched(show: 1399, season: 1, episode: 3))
        #expect(!episodes.isWatched(show: 1399, season: 3, episode: 1))
        #expect(!episodes.isWatched(show: 1400, season: 1, episode: 1))
    }

    @Test
    func `they are fetched only when Simkl says something changed, and kept over a restart`() async {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let calls = Calls(stamp: "A")
        let episodes = make(calls, at: location)

        await episodes.refresh()
        await episodes.refresh()
        #expect(calls.fetchCount == 1, "the second check saw the same stamp")

        let restarted = make(calls, at: location)
        #expect(restarted.isWatched(show: 1399, season: 1, episode: 1), "kept on disk")
        await restarted.refresh()
        #expect(calls.fetchCount == 1)

        calls.change("B")
        await restarted.refresh()
        #expect(calls.fetchCount == 2)
    }

    @Test
    func `disconnecting forgets them and the file`() async {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let episodes = make(Calls(stamp: "A"), at: location)
        await episodes.refresh()

        episodes.clear()

        #expect(!episodes.isWatched(show: 1399, season: 1, episode: 1))
        #expect(!FileManager.default.fileExists(atPath: location.path))
    }
}
