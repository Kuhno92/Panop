import Foundation
@testable import PanopCore
@testable import PanopDiscover
import Testing

/// Rails drawn from lists made elsewhere, such as "Top Box Office".
@Suite("Curated rails")
struct CuratedRailTests {
    /// 2026-10-02 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_942_400)

    private func title(
        _ id: Int,
        rating: Double? = 7.0,
        tmdb: Int? = nil,
        year: Int? = 2010,
        adult: Bool = false
    ) -> DiscoveryTitle {
        DiscoveryTitle(
            key: "p|movie:\(id)", kind: .movie, name: "Film\(id)", category: "Films", year: year,
            rating: rating, genres: [], cast: [], tmdbID: tmdb, isAdult: adult, hasPoster: true
        )
    }

    private func list(_ id: String, highlight: Bool = false, ids: [Int]) -> CuratedList {
        CuratedList(
            id: id, kind: .movie, isHighlight: highlight,
            entries: ids.enumerated().map { TrendingEntry(kind: .movie, tmdbID: $1, score: Double(ids.count - $0)) }
        )
    }

    private func rail(_ kind: RailKind, in rails: [Rail]) -> Rail? {
        rails.first { $0.kind == kind }
    }

    @Test
    func `a curated list keeps its order, only titles the library has, and needs five`() {
        let titles = (1 ... 8).map { title($0, tmdb: 500 + $0) }

        let rails = RailBuilder.build(DiscoveryInput(
            titles: titles,
            curated: [list("boxOffice", ids: [505, 999, 501, 508, 502, 507]), list("tiny", ids: [501, 502, 503])],
            now: now
        ))

        let keys = rail(.curated(.movie, "boxOffice"), in: rails)?.keys
        #expect(keys == ["p|movie:5", "p|movie:1", "p|movie:8", "p|movie:2", "p|movie:7"])
        #expect(rail(.curated(.movie, "tiny"), in: rails) == nil, "three is too few")
    }

    @Test
    func `lists made elsewhere repeat titles other rails have, and take none from them`() {
        let titles = (1 ... 30).map { title($0, rating: 9.0 - Double($0) / 10, tmdb: 600 + $0) }
        let everything = Array(601 ... 630)

        let rails = RailBuilder.build(DiscoveryInput(
            titles: titles,
            curated: [list("hiddenGems", ids: everything), list("topRated", ids: everything)],
            now: now
        ))

        let first = rail(.curated(.movie, "hiddenGems"), in: rails)
        let second = rail(.curated(.movie, "topRated"), in: rails)
        #expect(first != nil && first?.keys == second?.keys, "a second list is not starved by the first")
        #expect(rail(.topRated(.movie), in: rails) != nil, "and the person's own rails still have their titles")
    }

    @Test
    func `the highlighted lists come with the trending ones and the others last`() {
        let titles = (1 ... 40).map { title($0, tmdb: 700 + $0, year: 2024) }
        let ids = Array(701 ... 730)

        let rails = RailBuilder.build(DiscoveryInput(
            titles: titles,
            trending: ids.map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double(1000 - $0)) },
            curated: [list("late", ids: ids), list("early", highlight: true, ids: ids)],
            now: now
        ))

        let order = rails.map(\.id)
        let early = order.firstIndex(of: "curated.movie.early")
        let late = order.firstIndex(of: "curated.movie.late")
        let trending = order.firstIndex(of: "trending.movie")
        #expect(trending != nil && early != nil && late != nil)
        #expect((trending ?? 99) < (early ?? 0), "after trending")
        #expect((early ?? 99) < (late ?? 0))
        #expect(late == order.count - 1, "the plain ones after everything else")
    }

    @Test
    func `adult, hidden and watched titles are left out of a curated list too`() {
        var titles = (1 ... 9).map { title($0, tmdb: 800 + $0) }
        titles[0] = title(1, tmdb: 801, adult: true)

        let rails = RailBuilder.build(DiscoveryInput(
            titles: titles, unavailable: ["p|movie:2"], hidden: ["p|movie:3"],
            curated: [list("boxOffice", ids: Array(801 ... 809))], now: now
        ))

        let keys = rail(.curated(.movie, "boxOffice"), in: rails)?.keys ?? []
        #expect(!keys.contains("p|movie:1") && !keys.contains("p|movie:2") && !keys.contains("p|movie:3"))
        #expect(keys.count == 6)
    }
}
