import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import PanopDiscover
import PanopSimkl
import SwiftData
import Testing

@Suite("Discovery store", .serialized, .engineGate)
@MainActor
struct DiscoveryStoreTests {
    private let day = 20363 // 2025-10-02, in days since 1970

    private func context(
        seeds: [DiscoverySeed] = [],
        unavailable: Set<String> = [],
        hidden: Set<String> = [],
        hiddenCategories: [MediaKind: Set<String>] = [:],
        trending: [TrendingEntry] = [],
        playCounts: [PlayCount] = []
    ) -> DiscoveryContext {
        DiscoveryContext(
            seeds: seeds, playCounts: playCounts, unavailable: unavailable, hidden: hidden,
            hiddenCategories: hiddenCategories, trending: trending, day: day
        )
    }

    /// A library with something for every rail: well-rated films of every age, new ones, series with
    /// genres, an adult category, and a few that cannot be suggested.
    private func populate(_ catalog: OnDiskCatalog) async throws {
        var entries: [CatalogEntry] = []
        for index in 0 ..< 300 {
            entries.append(CatalogEntry(
                id: "m\(index)", kind: .movie, name: "Film\(index) (\(1960 + index % 66))", groupName: "Films",
                iconURL: "http://img/m\(index).jpg", rating: 6.0 + Double(index % 35) / 10, tmdbID: 1000 + index,
                year: 1960 + index % 66
            ))
        }
        for index in 0 ..< 40 {
            entries.append(CatalogEntry(
                id: "s\(index)", kind: .series, name: "Show\(index)", groupName: "Shows",
                iconURL: "http://img/s\(index).jpg", rating: 6.5 + Double(index % 25) / 10, tmdbID: 5000 + index,
                year: 2010 + index % 16, genre: index % 2 == 0 ? "Drama / Krimi" : "Komödie", cast: "A \(index % 3), B"
            ))
        }
        for index in 0 ..< 30 {
            entries.append(CatalogEntry(
                id: "a\(index)", kind: .movie, name: "Adult\(index)", groupName: "ADULT +18",
                iconURL: "http://img/a\(index).jpg", rating: 9.0, isAdult: true, year: 2025
            ))
        }
        _ = try await catalog.store.upsertEntries(entries, playlist: "p")
    }

    private func store(_ catalog: OnDiskCatalog, cache: URL? = nil) -> DiscoveryStore {
        DiscoveryStore(container: catalog.container, cacheURL: cache)
    }

    @Test
    func `a library builds rails, every title of which is in the library and none adult`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        let result = await store(catalog).build(context())

        #expect(!result.rails.isEmpty)
        let records = try ModelContext(catalog.container).fetch(FetchDescriptor<CatalogEntryRecord>())
        let byKey = Dictionary(
            records.map { (UserStateStore.key(playlist: $0.playlist, entry: $0.id), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for key in result.rails.flatMap(\.keys) {
            let record = try #require(byKey[key], "\(key) is not in the catalog")
            #expect(!record.isAdult, "\(key) is adult")
            #expect(result.rows[key] != nil, "\(key) has nothing to draw it from")
        }
    }

    @Test
    func `trending joins the library by TMDB id, in the list's order`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let trending = [1007, 1003, 99999, 1011, 1001, 1020, 1030].enumerated().map {
            TrendingEntry(kind: .movie, tmdbID: $1, score: Double(100 - $0))
        }

        let result = await store(catalog).build(context(trending: trending))

        let rail = try #require(result.rails.first { $0.kind == .trending(.movie) })
        #expect(rail.keys == ["p|m7", "p|m3", "p|m11", "p|m1", "p|m20", "p|m30"], "99999 is not in the library")
    }

    @Test
    func `the planned list joins the library by TMDB id and what was finished elsewhere is left out`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        var context = context()
        context.planned = [1010, 1020, 1030, 1040, 77777].enumerated().map {
            TrendingEntry(kind: .movie, tmdbID: $1, score: Double(10 - $0))
        }
        context.finishedElsewhere = [1020]

        let result = await store(catalog).build(context)

        let rail = try #require(result.rails.first { $0.kind == .onYourList })
        #expect(rail.keys == ["p|m10", "p|m30", "p|m40"])
        #expect(!result.rails.flatMap(\.keys).contains("p|m20"))
    }

    @Test
    func `followed shows come first, even ones the history marks as started`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        var context = context(unavailable: ["p|s3"])
        context.watching = [5003, 5007, 5001].enumerated().map {
            TrendingEntry(kind: .series, tmdbID: $1, score: Double(10 - $0))
        }

        let result = await store(catalog).build(context)

        #expect(result.rails.first?.kind == .nextUp)
        #expect(result.rails.first?.keys == ["p|s3", "p|s7", "p|s1"])
    }

    @Test
    func `lists made from Simkl's become rails of what the library has, in the list's order`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        var context = context()
        func list(_ id: String, _ kind: MediaKind, _ ids: [Int]) -> CuratedList {
            CuratedList(
                id: id, kind: kind, isHighlight: id == "boxOffice",
                entries: ids.enumerated().map { TrendingEntry(kind: kind, tmdbID: $1, score: Double(ids.count - $0)) }
            )
        }
        context.curated = [
            list("boxOffice", .movie, [1060, 1010, 55555, 1030, 1020, 1050, 1040]),
            list("network.Netflix", .series, [5003, 5001, 5002, 5009, 5004, 5005])
        ]

        let result = await store(catalog).build(context)

        let office = try #require(result.rails.first { $0.kind == .curated(.movie, "boxOffice") })
        #expect(
            office.keys == ["p|m60", "p|m10", "p|m30", "p|m20", "p|m50", "p|m40"],
            "the list's order, the six the library has"
        )
        let netflix = try #require(result.rails.first { $0.kind == .curated(.series, "network.Netflix") })
        #expect(netflix.keys.first == "p|s3")
        #expect(result.rows["p|m60"] != nil, "and what is needed to draw them")
    }

    @Test
    func `hidden entries, hidden categories and what is unavailable are never in a rail`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let everything = await store(catalog).build(context())
        let shown = Set(everything.rails.flatMap(\.keys))
        let someMovie = try #require(shown.first { $0.hasPrefix("p|m") })
        let someShow = try #require(shown.first { $0.hasPrefix("p|s") })

        let narrowed = await store(catalog).build(context(
            unavailable: [someMovie], hidden: [someShow], hiddenCategories: [.series: ["Shows"]]
        ))

        let keys = Set(narrowed.rails.flatMap(\.keys))
        #expect(!keys.contains(someMovie))
        #expect(!keys.contains(someShow))
        #expect(!keys.contains { $0.hasPrefix("p|s") }, "the whole series category is hidden")
    }

    @Test
    func `the result is kept on disk and read back by another instance`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let cache = catalog.directory.appendingPathComponent("rails.json")
        let built = await store(catalog, cache: cache).build(context())

        let read = await store(catalog, cache: cache).cached()

        #expect(read == built)
        #expect(await store(catalog, cache: nil).cached() == nil)
    }

    @Test
    func `an empty library has nothing to suggest`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }

        let result = await store(catalog).build(context())

        #expect(result.rails.isEmpty && result.rows.isEmpty)
    }

    @Test
    func `a seed gets a rail of titles like it, from its own category and beyond the top-rated few hundred`(
    ) async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let seed = DiscoverySeed(key: "p|s0", weight: 1)

        let result = await store(catalog).build(context(seeds: [seed], unavailable: ["p|s0"]))

        let because = try #require(result.rails.first { $0.kind == .becauseYouWatched(seed: "p|s0") })
        #expect(because.subject == "Show0")
        #expect(!because.keys.contains("p|s0"))
        #expect(because.keys.allSatisfy { $0.hasPrefix("p|s") }, "a show's likeness is other shows")
    }
}

@Suite("Rail headings")
struct RailHeadingTests {
    @Test
    func `every rail has words, naming what it is about`() {
        func title(_ kind: RailKind, _ subject: String? = nil) -> String {
            RailHeading.title(for: Rail(kind: kind, keys: [], subject: subject))
        }

        #expect(title(.trending(.movie)) == "Trending movies on Simkl")
        #expect(title(.trending(.series)) == "Trending series on Simkl")
        #expect(title(.becauseYouWatched(seed: "k"), "DE - Reacher (2022) (US)") == "Because you watched Reacher")
        #expect(title(.newReleases(.series)) == "New series")
        #expect(title(.mostWatched) == "Watch again")
        #expect(title(.topRated(.movie)) == "Top rated movies")
        #expect(title(.genre(.series, "krimi"), "krimi") == "Krimi series")
        #expect(title(.franchise("toy story"), "toy story") == "More from Toy Story")
        #expect(title(.classics(.movie)) == "Classics")
        #expect(title(.decade(.movie, 1990)) == "Movies of the 1990s")
        #expect(title(.pickOfTheDay(.series)) == "Series pick of the day")
        #expect(title(.curated(.movie, "boxOffice")) == "Top Box Office Movies on Simkl")
        #expect(title(.curated(.series, "network.Netflix")) == "Best of Netflix on Simkl")
        #expect(title(.curated(.series, "genre.Science Fiction")) == "Best Sci-Fi Series on Simkl")
        #expect(title(.curated(.movie, "genre.Action")) == "Best Action Movies on Simkl")
        #expect(title(.curated(.movie, "decade.1990")) == "Best Movies of the 1990s on Simkl", "no thousands separator")
        #expect(title(.curated(.series, "topRated")) == "Top Rated Series on Simkl")
        #expect(title(.curated(.movie, "justOnDVD")) == "Latest DVD Releases on Simkl")
        #expect(title(.curated(.series, "airing")) == "Currently Airing Series on Simkl")
    }

    @Test
    func `a title with nothing left after cleaning is shown as it is`() {
        #expect(RailHeading.display("(2020)") == "(2020)")
        #expect(RailHeading.display(nil) == "")
    }
}

@Suite("Discovery model switch")
@MainActor
struct DiscoveryModelSwitchTests {
    @Test
    func `turning suggestions off hides the rails and on brings them back`() {
        let model = DiscoveryModel()
        #expect(model.isEnabled)
        #expect(model.rails.isEmpty)

        model.isEnabled = false
        #expect(model.rails.isEmpty)
    }
}

@Suite("Next up from Simkl")
@MainActor
struct NextUpModelTests {
    @Test
    func `the followed shows are ordered by when they were last watched and carry their next episode`() {
        let model = DiscoveryModel()

        model.setSimklLists([
            SimklListItem(
                kind: .series, tmdbID: 1, status: .watching,
                next: SimklNextEpisode(season: 1, number: 2), lastWatchedAt: "2026-09-01T10:00:00Z"
            ),
            SimklListItem(
                kind: .series, tmdbID: 2, status: .watching,
                next: SimklNextEpisode(season: 3, number: 4), lastWatchedAt: "2026-10-01T10:00:00Z"
            ),
            SimklListItem(kind: .series, tmdbID: 3, status: .watching), // nothing to watch next
            SimklListItem(kind: .series, tmdbID: 4, status: .completed)
        ])

        #expect(model.nextEpisodes.count == 2)
        #expect(model.nextEpisodes[DiscoveryModel.linkKey(kind: .series, tmdbID: 2)]?.label == "S3E4")
        #expect(model.nextEpisodes[DiscoveryModel.linkKey(kind: .series, tmdbID: 3)] == nil)
    }
}
