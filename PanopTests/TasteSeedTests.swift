import Foundation
@testable import Panop
import PanopCore
import SwiftData
import Testing

@Suite("Viewing history for recommendations")
@MainActor
struct TasteSeedTests {
    private func makeStore(_ container: ModelContainer? = nil) throws -> UserStateStore {
        try UserStateStore(context: ModelContext(container ?? PanopContainers.makeCloud(inMemory: true)))
    }

    private func film(_ id: String) -> String {
        UserStateStore.key(playlist: "p", entry: id)
    }

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// Plays a film and finishes it, `days` after the base date.
    private func finish(_ store: UserStateStore, _ id: String, day days: Double) {
        let key = film(id)
        let when = base.addingTimeInterval(days * 86400)
        store.markPlayed(key, at: when)
        store.saveProgress(key, position: 5000, duration: 5100, at: when)
    }

    @Test
    func `a finished title is a seed, and the most recent is the strongest`() throws {
        let store = try makeStore()
        finish(store, "old", day: 0)
        finish(store, "new", day: 10)

        let seeds = store.tasteSeeds(limit: 5)

        #expect(seeds.map(\.key) == [film("new"), film("old")])
        #expect(seeds[0].weight > seeds[1].weight)
    }

    @Test
    func `a title stopped part-way counts for less than one finished, and below half not at all`() throws {
        let store = try makeStore()
        finish(store, "done", day: 0)
        store.markPlayed(film("half"), at: base.addingTimeInterval(86400))
        store.saveProgress(film("half"), position: 2700, duration: 5100, at: base.addingTimeInterval(86400))
        store.markPlayed(film("barely"), at: base.addingTimeInterval(2 * 86400))
        store.saveProgress(film("barely"), position: 600, duration: 5100, at: base.addingTimeInterval(2 * 86400))

        let seeds = store.tasteSeeds(limit: 5)

        #expect(Set(seeds.map(\.key)) == [film("done"), film("half")])
        #expect(!seeds.contains { $0.key == film("barely") })
    }

    @Test
    func `episodes count toward their series, which is one seed`() throws {
        let store = try makeStore()
        let show = UserStateStore.key(playlist: "p", entry: "series:7")
        for episode in 1 ... 3 {
            let key = film("episode:\(episode)")
            store.markPlayed(key, parent: show, at: base.addingTimeInterval(Double(episode) * 3600))
            store.saveProgress(key, position: 2500, duration: 2600, at: base.addingTimeInterval(Double(episode) * 3600))
        }

        let seeds = store.tasteSeeds(limit: 5)

        #expect(seeds.map(\.key) == [show], "three episodes, one show")
    }

    @Test
    func `a channel that was only opened is never a seed`() throws {
        let store = try makeStore()
        store.markPlayed(film("live:1"), at: base)
        store.markPlayed(film("live:1"), at: base.addingTimeInterval(60))

        #expect(store.tasteSeeds(limit: 5).isEmpty)
    }

    @Test
    func `the limit cuts the list`() throws {
        let store = try makeStore()
        for index in 0 ..< 6 {
            finish(store, "f\(index)", day: Double(index))
        }

        #expect(store.tasteSeeds(limit: 3).count == 3)
        #expect(store.tasteSeeds(limit: 0).isEmpty)
    }

    @Test
    func `how often a title was opened is counted, a series by all its episodes`() throws {
        let store = try makeStore()
        let show = UserStateStore.key(playlist: "p", entry: "series:1")
        store.markPlayed(film("e1"), parent: show, at: base)
        store.markPlayed(film("e2"), parent: show, at: base.addingTimeInterval(60))
        store.markPlayed(film("e1"), parent: show, at: base.addingTimeInterval(120))
        store.markPlayed(film("movie"), at: base.addingTimeInterval(180))

        let counts = store.playCounts(limit: 5)

        #expect(counts.first?.key == show)
        #expect(counts.first?.count == 3)
        #expect(counts.last?.count == 1)
    }

    @Test
    func `the history survives a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        try finish(makeStore(container), "kept", day: 1)

        #expect(try makeStore(container).tasteSeeds(limit: 5).map(\.key) == [film("kept")])
    }

    @Test
    func `forgetting what was watched clears it but keeps favourites, hidden titles and resume points`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = try makeStore(container)
        finish(store, "done", day: 0)
        store.toggleFavorite(film("done"))
        store.markPlayed(film("partway"), at: base)
        store.saveProgress(film("partway"), position: 900, duration: 5100, at: base)
        store.markPlayed(film("hid"), at: base)
        store.setHidden(true, for: film("hid"))

        store.forgetViewingHistory()

        #expect(store.tasteSeeds(limit: 5).isEmpty)
        #expect(store.recents.isEmpty)
        #expect(store.playCounts(limit: 5).isEmpty)
        #expect(!store.isWatched(film("done")))
        #expect(store.isFavorite(film("done")))
        #expect(store.isHidden(film("hid")))
        #expect(store.resumePosition(for: film("partway")) == 900)
    }
}
