import Foundation
@testable import Panop
import Testing

@Suite("Live TV empty state")
struct LiveEmptyStateTests {
    private func source(_ name: String, _ status: SyncStatus) -> LiveEmptyState.Source {
        LiveEmptyState.Source(id: name.lowercased(), name: name, status: status)
    }

    private let finished = SyncStatus.idle

    @Test
    func `nothing added yet invites adding a playlist`() {
        #expect(LiveEmptyState.resolve(isSearching: false, sources: [], hasPlaylists: false) == .noPlaylists)
    }

    @Test
    func `a search with no match says so, whatever else is going on`() {
        let sources = [source("Home", .failed("down"))]
        #expect(LiveEmptyState.resolve(isSearching: true, sources: sources, hasPlaylists: true) == .searchFoundNothing)
    }

    @Test
    func `a source still loading reads as loading, not as empty`() {
        let sources = [source("Home", .syncing(processed: 120))]
        #expect(LiveEmptyState.resolve(isSearching: false, sources: sources, hasPlaylists: true) == .syncing)
    }

    /// The case this exists for: a provider that could not be reached used to show "no
    /// channels", which sends a person looking in the wrong place.
    @Test
    func `a source that failed is a failure with its reason, not no channels`() {
        let sources = [source("Home", .failed("The provider rejected the username or password."))]

        let state = LiveEmptyState.resolve(isSearching: false, sources: sources, hasPlaylists: true)

        #expect(state == .failed([
            LiveEmptyState.Problem(id: "home", name: "Home", message: "The provider rejected the username or password.")
        ]))
    }

    @Test
    func `still loading wins over an earlier failure, since a retry is under way`() {
        let sources = [source("Home", .syncing(processed: 0)), source("Backup", .failed("down"))]
        #expect(LiveEmptyState.resolve(isSearching: false, sources: sources, hasPlaylists: true) == .syncing)
    }

    @Test
    func `a source that loaded and has no live channels says that`() {
        let sources = [source("Movies only", .idle)]
        #expect(LiveEmptyState.resolve(isSearching: false, sources: sources, hasPlaylists: true) == .noLiveChannels)
    }

    @Test
    func `every failing source is listed`() {
        let sources = [source("A", .failed("one")), source("B", .idle), source("C", .failed("three"))]

        let problems = LiveEmptyState.problems(in: sources)

        #expect(problems.map(\.name) == ["A", "C"])
        #expect(problems.map(\.message) == ["one", "three"])
    }

    @Test
    func `no problems when nothing failed`() {
        #expect(LiveEmptyState.problems(in: [source("A", .idle), source("B", .syncing(processed: 5))]).isEmpty)
    }

    @Test
    func `a chosen source that is not the broken one shows no problem`() {
        // The screen passes only the sources on show: choosing a healthy one hides the other's.
        #expect(LiveEmptyState.problems(in: [source("Healthy", .idle)]).isEmpty)
    }

    @Test
    func `an empty favourites list says so, whatever state the sources are in`() {
        let sources = [source("Home", .failed("down"))]
        #expect(LiveEmptyState
            .resolve(isSearching: false, sources: sources, hasPlaylists: true, mode: .favourites) == .noFavourites)
    }

    @Test
    func `an empty history says nothing has been watched`() {
        let sources = [source("Home", .idle)]
        #expect(LiveEmptyState
            .resolve(isSearching: false, sources: sources, hasPlaylists: true, mode: .recents) == .noRecents)
    }

    @Test
    func `a search that finds nothing is still a search, in any mode`() {
        let sources = [source("Home", .idle)]
        #expect(LiveEmptyState
            .resolve(isSearching: true, sources: sources, hasPlaylists: true, mode: .favourites) == .searchFoundNothing)
    }

    @Test
    func `with no playlist there is nothing to favourite either`() {
        #expect(LiveEmptyState
            .resolve(isSearching: false, sources: [], hasPlaylists: false, mode: .favourites) == .noPlaylists)
    }
}
