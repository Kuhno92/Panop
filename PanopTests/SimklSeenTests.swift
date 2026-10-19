@testable import Panop
import PanopCore
import PanopSimkl
import Testing

@Suite("Seen on Simkl")
@MainActor
struct SimklSeenTests {
    @Test
    func `a title the account has finished is seen, and the kind is part of the answer`() {
        let model = DiscoveryModel()
        model.setSimklLists([
            SimklListItem(kind: .movie, tmdbID: 550, status: .completed),
            SimklListItem(kind: .series, tmdbID: 550, status: .watching),
            SimklListItem(kind: .series, tmdbID: 1399, status: .completed),
            SimklListItem(kind: .movie, tmdbID: 603, status: .plantowatch)
        ])

        #expect(model.isSeenOnSimkl(kind: .movie, tmdbID: 550))
        #expect(!model.isSeenOnSimkl(kind: .series, tmdbID: 550), "a show's id is not a film's")
        #expect(model.isSeenOnSimkl(kind: .series, tmdbID: 1399))
        #expect(!model.isSeenOnSimkl(kind: .movie, tmdbID: 603), "planned is not seen")
    }

    @Test
    func `a title with no TMDB id is never seen, and disconnecting clears the badges`() {
        let model = DiscoveryModel()
        model.setSimklLists([SimklListItem(kind: .movie, tmdbID: 550, status: .completed)])

        #expect(!model.isSeenOnSimkl(kind: .movie, tmdbID: nil))
        #expect(model.isSeenOnSimkl(kind: .movie, tmdbID: 550))

        model.setSimklLists([])

        #expect(!model.isSeenOnSimkl(kind: .movie, tmdbID: 550))
    }
}
