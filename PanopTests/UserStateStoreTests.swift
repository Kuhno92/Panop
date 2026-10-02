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

@Suite("Resume points")
@MainActor
struct ResumePointTests {
    private func makeStore() throws -> UserStateStore {
        try UserStateStore(context: ModelContext(PanopContainers.makeCloud(inMemory: true)))
    }

    private let film = UserStateStore.key(playlist: "p", entry: "film")

    @Test
    func `how far someone got is remembered`() throws {
        let store = try makeStore()

        store.saveProgress(film, position: 1834, duration: 7200)

        #expect(store.resumePosition(for: film) == 1834)
        #expect(store.progress[film]?.fraction.map { abs($0 - 0.2547) < 0.001 } == true)
    }

    @Test
    func `unfinished titles are listed the one watched last first`() throws {
        let store = try makeStore()
        let other = UserStateStore.key(playlist: "p", entry: "episode")
        let finished = UserStateStore.key(playlist: "p", entry: "done")
        let base = Date(timeIntervalSince1970: 1_000_000)
        store.markPlayed(film, at: base)
        store.saveProgress(film, position: 600, duration: 7200, at: base)
        store.markPlayed(other, at: base.addingTimeInterval(60))
        store.saveProgress(other, position: 300, duration: 2400, at: base.addingTimeInterval(60))
        store.markPlayed(finished, at: base.addingTimeInterval(120))
        store.saveProgress(finished, position: 2390, duration: 2400, at: base.addingTimeInterval(120))

        #expect(store.continueWatching == [other, film], "the finished one is not offered")
    }

    @Test
    func `a point with no recent play still counts, after the others`() throws {
        let store = try makeStore()
        let other = UserStateStore.key(playlist: "p", entry: "episode")
        store.markPlayed(other)
        store.saveProgress(other, position: 300, duration: 2400)
        store.saveProgress(film, position: 600, duration: 7200)
        store.reload()

        #expect(store.continueWatching.first == other)
        #expect(store.continueWatching.contains(film))
    }

    @Test
    func `reaching the end marks it watched, and the mark outlives the cleared point`() throws {
        let store = try makeStore()
        store.saveProgress(film, position: 1000, duration: 7200)

        store.saveProgress(film, position: 7100, duration: 7200)

        #expect(store.isWatched(film))
        #expect(store.resumePosition(for: film) == nil)
    }

    @Test
    func `marking by hand works both ways, and marking seen drops the resume point`() throws {
        let store = try makeStore()
        store.saveProgress(film, position: 1000, duration: 7200)

        store.setWatched(true, for: film)
        #expect(store.isWatched(film))
        #expect(store.resumePosition(for: film) == nil)

        store.setWatched(false, for: film)
        #expect(!store.isWatched(film))
        #expect(store.progress.isEmpty)
    }

    @Test
    func `a watched mark survives a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        UserStateStore(context: ModelContext(container)).setWatched(true, for: film)

        #expect(UserStateStore(context: ModelContext(container)).isWatched(film))
    }

    @Test
    func `it survives a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        UserStateStore(context: ModelContext(container)).saveProgress(film, position: 600, duration: 3600)

        let later = UserStateStore(context: ModelContext(container))

        #expect(later.resumePosition(for: film) == 600)
    }

    @Test
    func `the first moments are not worth coming back to`() throws {
        let store = try makeStore()

        store.saveProgress(film, position: 6, duration: 7200)

        #expect(store.resumePosition(for: film) == nil)
        #expect(store.progress.isEmpty)
    }

    @Test(arguments: [(6900.0, 7200.0), (7190.0, 7200.0), (7200.0, 7200.0)])
    func `reaching the end clears the point, so the next play starts over`(position: Double, duration: Double) throws {
        let store = try makeStore()
        store.saveProgress(film, position: 1000, duration: duration)
        #expect(store.resumePosition(for: film) == 1000)

        store.saveProgress(film, position: position, duration: duration)

        #expect(store.resumePosition(for: film) == nil)
    }

    @Test
    func `a later save replaces an earlier one`() throws {
        let store = try makeStore()
        store.saveProgress(film, position: 100, duration: 7200)

        store.saveProgress(film, position: 2500, duration: 7200)

        #expect(store.resumePosition(for: film) == 2500)
    }

    @Test
    func `with no known length it keeps the position and never calls it finished`() throws {
        let store = try makeStore()

        store.saveProgress(film, position: 5000, duration: nil)

        #expect(store.resumePosition(for: film) == 5000)
        #expect(store.progress[film]?.fraction == nil)
    }

    @Test
    func `a point that is cleared leaves no row behind, unless it was starred or watched`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = UserStateStore(context: ModelContext(container))
        // Too early to keep: nothing to resume and nothing seen.
        store.saveProgress(film, position: 3, duration: 7200)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 0)
        // Seen to the end: the row stays, as the watched mark.
        store.saveProgress(film, position: 1000, duration: 7200)
        store.saveProgress(film, position: 7199, duration: 7200)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 1)
        store.setWatched(false, for: film)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 0)

        store.markPlayed(film)
        store.saveProgress(film, position: 1000, duration: 7200)
        store.saveProgress(film, position: 7199, duration: 7200)
        #expect(store.recents == [film], "history stays when the point goes")
    }

    @Test
    func `a deleted playlist takes its resume points with it`() throws {
        let store = try makeStore()
        store.saveProgress(UserStateStore.key(playlist: "gone", entry: "a"), position: 500, duration: 7200)
        store.saveProgress(UserStateStore.key(playlist: "kept", entry: "a"), position: 500, duration: 7200)

        store.forget(playlist: "gone")

        #expect(store.progress.keys.sorted() == [UserStateStore.key(playlist: "kept", entry: "a")])
    }
}

@Suite("Engine memory store")
@MainActor
struct EngineMemoryStoreTests {
    @Test
    func `a remembered engine survives a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        UserStateStore(context: ModelContext(container)).remember(.vlcKit, for: "p|c")

        let later = UserStateStore(context: ModelContext(container))

        #expect(later.remembered(for: "p|c") == .vlcKit)
        #expect(later.remembered(for: "p|other") == nil)
    }

    @Test
    func `forgetting leaves no row behind`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = UserStateStore(context: ModelContext(container))
        store.remember(.lumeEngine, for: "p|c")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 1)

        store.forget(for: "p|c")

        #expect(store.remembered(for: "p|c") == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 0)
    }

    @Test
    func `a remembered engine keeps its row alive and does not disturb the favourite`() throws {
        let store = try UserStateStore(context: ModelContext(PanopContainers.makeCloud(inMemory: true)))
        store.toggleFavorite("p|c")

        store.remember(.vlcKit, for: "p|c")
        store.forget(for: "p|c")

        #expect(store.isFavorite("p|c"))
    }
}

@Suite("Hidden entries")
@MainActor
struct HiddenEntriesTests {
    private let channel = UserStateStore.key(playlist: "p", entry: "divider")

    private func makeStore(_ container: ModelContainer? = nil) throws -> UserStateStore {
        try UserStateStore(context: ModelContext(container ?? PanopContainers.makeCloud(inMemory: true)))
    }

    @Test
    func `an entry can be hidden and shown again`() throws {
        let store = try makeStore()

        store.setHidden(true, for: channel)
        #expect(store.isHidden(channel))
        #expect(store.hidden == [channel])

        store.setHidden(false, for: channel)
        #expect(!store.isHidden(channel))
        #expect(store.hidden.isEmpty)
    }

    @Test
    func `hiding survives a new launch`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        try makeStore(container).setHidden(true, for: channel)

        #expect(try makeStore(container).isHidden(channel))
    }

    @Test
    func `showing it again leaves no row behind, and keeps a favourite`() throws {
        let container = try PanopContainers.makeCloud(inMemory: true)
        let store = try makeStore(container)
        store.setHidden(true, for: channel)
        store.setHidden(false, for: channel)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<UserContentState>()) == 0)

        store.toggleFavorite(channel)
        store.setHidden(true, for: channel)
        store.setHidden(false, for: channel)
        #expect(store.isFavorite(channel))
    }

    @Test
    func `a hidden entry is not dropped by the limit on kept plays`() throws {
        let store = try makeStore()
        store.markPlayed(channel, at: Date(timeIntervalSince1970: 1))
        store.setHidden(true, for: channel)

        // More plays than are kept: the oldest go, but not what is hidden.
        for index in 0 ..< UserStateStore.retainedPlays + 20 {
            store.markPlayed(
                UserStateStore.key(playlist: "p", entry: "c\(index)"),
                at: Date(timeIntervalSince1970: Double(index + 10))
            )
        }

        #expect(store.isHidden(channel))
    }
}
