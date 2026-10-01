import Foundation
@testable import Panop
import SwiftData
import Testing

@Suite("Favourites and recents")
@MainActor
struct UserStateStoreTests {
    private func makeContainer() throws -> ModelContainer {
        try PanopContainers.makeCloud(inMemory: true)
    }

    private func key(_ playlist: String, _ entry: String) -> String {
        UserStateStore.key(playlist: playlist, entry: entry)
    }

    private func rowCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>())
    }

    // MARK: - Favourites

    @Test
    func `a channel can be starred and unstarred`() throws {
        let store = try UserStateStore(context: ModelContext(makeContainer()))

        store.toggleFavorite(key("p", "1"))
        #expect(store.isFavorite(key("p", "1")))

        store.toggleFavorite(key("p", "1"))
        #expect(!store.isFavorite(key("p", "1")))
    }

    @Test
    func `favourites survive a new launch`() throws {
        let container = try makeContainer()
        UserStateStore(context: ModelContext(container)).toggleFavorite(key("p", "1"))

        let later = UserStateStore(context: ModelContext(container))

        #expect(later.favorites == [key("p", "1")])
    }

    @Test
    func `unstarring a channel with no history leaves nothing behind`() throws {
        let container = try makeContainer()
        let store = UserStateStore(context: ModelContext(container))
        store.toggleFavorite(key("p", "1"))
        #expect(try rowCount(container) == 1)

        store.toggleFavorite(key("p", "1"))

        #expect(try rowCount(container) == 0, "the store fills with ghosts otherwise")
    }

    @Test
    func `unstarring a channel that was watched keeps its history`() throws {
        let store = try UserStateStore(context: ModelContext(makeContainer()))
        store.markPlayed(key("p", "1"))
        store.toggleFavorite(key("p", "1"))

        store.toggleFavorite(key("p", "1"))

        #expect(!store.isFavorite(key("p", "1")))
        #expect(store.recents == [key("p", "1")])
    }

    @Test
    func `the same channel id in two playlists is two channels`() throws {
        let store = try UserStateStore(context: ModelContext(makeContainer()))

        store.toggleFavorite(key("home", "42"))

        #expect(store.isFavorite(key("home", "42")))
        #expect(!store.isFavorite(key("backup", "42")), "an Xtream stream id repeats across providers")
    }

    // MARK: - Recents

    @Test
    func `recents are newest first, and replaying moves a channel to the front`() throws {
        let store = try UserStateStore(context: ModelContext(makeContainer()))
        let start = Date(timeIntervalSince1970: 1_000_000)

        store.markPlayed(key("p", "a"), at: start)
        store.markPlayed(key("p", "b"), at: start + 10)
        store.markPlayed(key("p", "c"), at: start + 20)
        #expect(store.recents == [key("p", "c"), key("p", "b"), key("p", "a")])

        store.markPlayed(key("p", "a"), at: start + 30)
        #expect(store.recents == [key("p", "a"), key("p", "c"), key("p", "b")])
    }

    @Test
    func `recents survive a new launch in the same order`() throws {
        let container = try makeContainer()
        let first = UserStateStore(context: ModelContext(container))
        let start = Date(timeIntervalSince1970: 1_000_000)
        first.markPlayed(key("p", "a"), at: start)
        first.markPlayed(key("p", "b"), at: start + 10)

        let later = UserStateStore(context: ModelContext(container))

        #expect(later.recents == [key("p", "b"), key("p", "a")])
    }

    @Test
    func `only the most recent are shown, and the oldest plays are not kept forever`() throws {
        let container = try makeContainer()
        let store = UserStateStore(context: ModelContext(container))
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0 ..< (UserStateStore.retainedPlays + 20) {
            store.markPlayed(key("p", "\(index)"), at: start + Double(index))
        }

        #expect(store.recents.count == UserStateStore.recentLimit)
        #expect(store.recents.first == key("p", "\(UserStateStore.retainedPlays + 19)"))
        #expect(try rowCount(container) == UserStateStore.retainedPlays)
    }

    @Test
    func `trimming old plays never removes a favourite`() throws {
        let container = try makeContainer()
        let store = UserStateStore(context: ModelContext(container))
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.markPlayed(key("p", "oldest"), at: start)
        store.toggleFavorite(key("p", "oldest"))

        for index in 1 ... (UserStateStore.retainedPlays + 5) {
            store.markPlayed(key("p", "\(index)"), at: start + Double(index))
        }

        #expect(store.isFavorite(key("p", "oldest")))
    }

    // MARK: - Cleanup

    @Test
    func `forgetting a playlist removes only its own channels`() throws {
        let store = try UserStateStore(context: ModelContext(makeContainer()))
        store.toggleFavorite(key("p1", "a"))
        store.markPlayed(key("p1", "b"))
        store.toggleFavorite(key("p10", "a"))
        store.toggleFavorite(key("other", "a"))

        store.forget(playlist: "p1")

        #expect(store.favorites == [key("p10", "a"), key("other", "a")], "p10 is not p1")
        #expect(store.recents.isEmpty)
    }

    // MARK: - Keys

    @Test
    func `a key splits back into its entry`() {
        #expect(UserStateStore.entryID(in: key("playlist", "live:42")) == "live:42")
        #expect(UserStateStore.entryID(in: "a|b|c") == "b|c")
        #expect(UserStateStore.entryID(in: "bare") == "bare")
    }
}
