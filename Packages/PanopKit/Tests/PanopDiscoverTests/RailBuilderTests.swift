import Foundation
import PanopCore
@testable import PanopDiscover
import Testing

@Suite("Rails")
struct RailBuilderTests {
    /// 2026-10-02 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_942_400)

    private func title(
        _ id: Int,
        _ kind: MediaKind = .movie,
        name: String? = nil,
        category: String? = "Films",
        year: Int? = 2010,
        rating: Double? = 7.0,
        genres: Set<String> = [],
        cast: Set<String> = [],
        tmdb: Int? = nil,
        adult: Bool = false,
        poster: Bool = true
    ) -> DiscoveryTitle {
        DiscoveryTitle(
            key: "p|\(kind.rawValue):\(id)", kind: kind, name: name ?? "Film\(id)", category: category, year: year,
            rating: rating, genres: genres, cast: cast, tmdbID: tmdb, isAdult: adult, hasPoster: poster
        )
    }

    private func build(_ input: DiscoveryInput) -> [Rail] {
        RailBuilder.build(input)
    }

    private func rail(_ kind: RailKind, in rails: [Rail]) -> Rail? {
        rails.first { $0.kind == kind }
    }

    // MARK: - The person's own list

    @Test
    func `the planned list keeps its order, films and shows together, and comes first`() {
        let films = (1 ... 4).map { title($0, tmdb: 100 + $0) }
        let shows = (1 ... 2).map { title($0, .series, tmdb: 200 + $0) }
        let planned = [
            TrendingEntry(kind: .series, tmdbID: 201, score: 6),
            TrendingEntry(kind: .movie, tmdbID: 104, score: 5),
            TrendingEntry(kind: .movie, tmdbID: 999, score: 4), // not in the library
            TrendingEntry(kind: .movie, tmdbID: 102, score: 3),
            TrendingEntry(kind: .series, tmdbID: 202, score: 2)
        ]

        let rails = build(DiscoveryInput(titles: films + shows, planned: planned, now: now))

        #expect(rails.first?.kind == .onYourList)
        #expect(rails.first?.keys == ["p|series:1", "p|movie:4", "p|movie:2", "p|series:2"])
    }

    @Test
    func `a list with fewer than three titles in the library draws no rail`() {
        let films = (1 ... 4).map { title($0, tmdb: 100 + $0) }
        let planned = [101, 102].map { TrendingEntry(kind: .movie, tmdbID: $0, score: 1) }

        #expect(rail(.onYourList, in: build(DiscoveryInput(titles: films, planned: planned, now: now))) == nil)
    }

    @Test
    func `what was finished elsewhere is never suggested, not even from the planned list`() {
        let films = (1 ... 6).map { title($0, tmdb: 100 + $0) }
        let planned = (1 ... 6).map { TrendingEntry(kind: .movie, tmdbID: 100 + $0, score: Double($0)) }

        let rails = build(DiscoveryInput(titles: films, planned: planned, finishedElsewhere: [103, 105], now: now))

        let keys = Set(rails.flatMap(\.keys))
        #expect(!keys.contains("p|movie:3") && !keys.contains("p|movie:5"))
        #expect(rail(.onYourList, in: rails)?.keys.count == 4)
    }

    @Test
    func `next up lists the shows being followed, even ones the history marks as started, and comes first`() {
        let shows = (1 ... 3).map { title($0, .series, tmdb: 300 + $0) }
        let watching = [
            TrendingEntry(kind: .series, tmdbID: 302, score: 3),
            TrendingEntry(kind: .series, tmdbID: 301, score: 2)
        ]

        let rails = build(DiscoveryInput(
            titles: shows, unavailable: ["p|series:1", "p|series:2"], watching: watching, now: now
        ))

        #expect(rails.first?.kind == .nextUp)
        #expect(rails.first?.keys == ["p|series:2", "p|series:1"])
    }

    @Test
    func `a followed show that is hidden or adult is still left out`() {
        let shows = [title(1, .series, tmdb: 301), title(2, .series, tmdb: 302, adult: true)]
        let watching = [301, 302].map { TrendingEntry(kind: .series, tmdbID: $0, score: 1) }

        let rails = build(DiscoveryInput(titles: shows, hidden: ["p|series:1"], watching: watching, now: now))

        #expect(rail(.nextUp, in: rails) == nil)
    }

    // MARK: - Trending

    @Test
    func `trending keeps the source's order and only titles the library has`() {
        let titles = (1 ... 8).map { title($0, tmdb: 1000 + $0) }
        let trending = [
            TrendingEntry(kind: .movie, tmdbID: 1003, score: 90),
            TrendingEntry(kind: .movie, tmdbID: 9999, score: 80), // not in the library
            TrendingEntry(kind: .movie, tmdbID: 1001, score: 70),
            TrendingEntry(kind: .movie, tmdbID: 1008, score: 60),
            TrendingEntry(kind: .movie, tmdbID: 1002, score: 50),
            TrendingEntry(kind: .movie, tmdbID: 1007, score: 40)
        ]

        let rails = build(DiscoveryInput(titles: titles, trending: trending, now: now))

        let keys = rail(.trending(.movie), in: rails)?.keys
        #expect(keys == ["p|movie:3", "p|movie:1", "p|movie:8", "p|movie:2", "p|movie:7"])
    }

    @Test
    func `trending of films and of series are separate`() {
        let films = (1 ... 5).map { title($0, .movie, tmdb: $0) }
        let shows = (1 ... 5).map { title($0, .series, tmdb: $0) }
        let trending = (1 ... 5).flatMap {
            [
                TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)),
                TrendingEntry(kind: .series, tmdbID: $0, score: Double($0))
            ]
        }

        let rails = build(DiscoveryInput(titles: films + shows, trending: trending, now: now))

        #expect(rail(.trending(.movie), in: rails)?.keys.allSatisfy { $0.contains("movie") } == true)
        #expect(rail(.trending(.series), in: rails)?.keys.allSatisfy { $0.contains("series") } == true)
    }

    @Test
    func `a trending list with too few titles in the library draws no rail`() {
        let titles = (1 ... 4).map { title($0, tmdb: $0) }
        let trending = (1 ... 4).map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)) }

        #expect(rail(.trending(.movie), in: build(DiscoveryInput(titles: titles, trending: trending, now: now))) == nil)
    }

    // MARK: - What is never suggested

    @Test
    func `adult, hidden, hidden-category, posterless and watched titles never appear`() {
        var titles = (1 ... 10).map { title($0, rating: 8.0, tmdb: $0) }
        titles[0].isAdult = true
        titles[1].hasPoster = false
        titles[2].category = "Hidden"
        let input = DiscoveryInput(
            titles: titles,
            unavailable: [titles[3].key],
            hidden: [titles[4].key],
            hiddenCategories: [.movie: ["Hidden"]],
            trending: (1 ... 10).map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)) },
            now: now
        )

        let shown = Set(build(input).flatMap(\.keys))

        for index in 0 ... 4 {
            #expect(!shown.contains(titles[index].key), "title \(index + 1) is excluded")
        }
        #expect(shown.contains(titles[5].key))
    }

    @Test
    func `no title is in two rails`() {
        let titles = (1 ... 60).map {
            title($0, year: 2025, rating: 8.0, genres: ["drama"], tmdb: $0)
        }
        let trending = (1 ... 60).map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)) }

        let rails = build(DiscoveryInput(titles: titles, trending: trending, now: now))

        let keys = rails.flatMap(\.keys)
        #expect(!keys.isEmpty)
        #expect(Set(keys).count == keys.count)
    }

    @Test
    func `every title in every rail is a title of the library`() {
        let titles = (1 ... 80).map { title($0, year: 2000 + $0 % 26, rating: 6.0 + Double($0 % 40) / 10, tmdb: $0) }
        let known = Set(titles.map(\.key))

        let rails = build(DiscoveryInput(
            titles: titles,
            trending: (1 ... 200).map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)) },
            now: now
        ))

        #expect(rails.flatMap(\.keys).allSatisfy(known.contains))
    }

    @Test
    func `the same film listed twice is one title, the better rated`() {
        var titles = (1 ... 6).map { title($0, name: "Film \($0)", year: 2025, rating: 8.0) }
        titles.append(title(100, name: "DE - Film 1 (2025)", year: 2025, rating: 6.0))
        titles.append(title(101, name: "Film 1", year: 2025, rating: 9.0))

        let rails = build(DiscoveryInput(titles: titles, now: now))

        let keys = rails.flatMap(\.keys)
        #expect(keys.contains("p|movie:101"))
        #expect(!keys.contains("p|movie:1"))
        #expect(!keys.contains("p|movie:100"))
    }

    // MARK: - New releases and top rated

    @Test
    func `new releases are this year and last, with a rating, newest first`() {
        var titles = (1 ... 6).map { title($0, year: 2026, rating: 7.0 + Double($0) / 10) }
        titles.append(title(20, year: 2025, rating: 8.5))
        titles.append(title(21, year: 2024, rating: 9.0)) // too old
        titles.append(title(22, year: 2026, rating: nil)) // unrated
        titles.append(title(23, year: 2026, rating: 5.0)) // below the floor
        titles.append(title(24, year: 2027, rating: 8.0)) // from the future: a typo

        let keys = rail(.newReleases(.movie), in: build(DiscoveryInput(titles: titles, now: now)))?.keys ?? []

        #expect(keys.count == 7)
        #expect(keys.first == "p|movie:6", "the newest year, best rated first")
        #expect(keys.last == "p|movie:20", "2025 after 2026")
        #expect(!keys.contains("p|movie:21") && !keys.contains("p|movie:22"))
        #expect(!keys.contains("p|movie:23") && !keys.contains("p|movie:24"))
    }

    @Test
    func `top rated ignores unrated titles and ratings too high to be believed`() {
        var titles = (1 ... 6).map { title($0, year: 1990, rating: 7.5 + Double($0) / 10) }
        titles.append(title(30, rating: 10.0))
        titles.append(title(31, rating: 0))
        titles.append(title(32, rating: nil))

        let rails = build(DiscoveryInput(titles: titles, now: now))

        let keys = rail(.topRated(.movie), in: rails)?.keys ?? []
        #expect(keys.first == "p|movie:6")
        #expect(!keys.contains("p|movie:30") && !keys.contains("p|movie:31") && !keys.contains("p|movie:32"))
    }

    // MARK: - Because you watched

    @Test
    func `because you watched draws on likeness to the seed, never the seed, and names it`() {
        let seed = title(
            1,
            .series,
            name: "Reacher",
            category: "Shows",
            year: 2022,
            rating: 8.0,
            genres: ["krimi", "drama"],
            cast: ["alan ritchson"]
        )
        var candidates: [DiscoveryTitle] = []
        for index in 2 ... 9 {
            candidates.append(title(
                index,
                .series,
                category: "Shows",
                year: 2021,
                rating: 8.0,
                genres: ["krimi", "drama"]
            ))
        }
        candidates.append(title(50, .series, category: "Kids", year: 1985, rating: 3.0, genres: ["kids"]))

        let rails = build(DiscoveryInput(
            titles: [seed] + candidates,
            seeds: [DiscoverySeed(key: seed.key, weight: 1)],
            unavailable: [seed.key],
            now: now
        ))

        let because = rail(.becauseYouWatched(seed: seed.key), in: rails)
        #expect(because?.subject == "Reacher")
        #expect(because?.keys.contains(seed.key) == false)
        #expect(because?.keys.contains("p|series:50") == false, "nothing like it")
        #expect(because?.keys.count == 8)
    }

    @Test
    func `the seed's details may come from outside the candidates`() {
        let seed = title(1, .series, name: "Reacher", category: "Shows", genres: ["krimi", "drama"])
        let candidates = (2 ... 8).map { title($0, .series, category: "Shows", genres: ["krimi", "drama"]) }

        let rails = build(DiscoveryInput(
            titles: candidates,
            seeds: [DiscoverySeed(key: seed.key, weight: 1)],
            seedTitles: [seed.key: seed],
            unavailable: [seed.key],
            now: now
        ))

        #expect(rail(.becauseYouWatched(seed: seed.key), in: rails) != nil)
    }

    @Test
    func `a seed nothing is known about gives no rail`() {
        let candidates = (2 ... 9).map { title($0, .series, genres: ["drama"]) }

        let rails = build(DiscoveryInput(
            titles: candidates,
            seeds: [DiscoverySeed(key: "p|series:1", weight: 1)],
            now: now
        ))

        #expect(!rails.contains {
            if case .becauseYouWatched = $0.kind {
                true
            } else {
                false
            }
        })
    }

    @Test
    func `only the strongest seeds get a rail, strongest first`() {
        let seeds = (1 ... 4).map { title($0, .series, name: "Seed \($0)", category: "Shows\($0)", genres: ["g\($0)"]) }
        var pool: [DiscoveryTitle] = []
        for seed in 1 ... 4 {
            for index in 1 ... 6 {
                pool.append(title(seed * 100 + index, .series, category: "Shows\(seed)", genres: ["g\(seed)"]))
            }
        }

        let rails = build(DiscoveryInput(
            titles: seeds + pool,
            seeds: seeds.enumerated().map { DiscoverySeed(key: $1.key, weight: Double(4 - $0)) },
            unavailable: Set(seeds.map(\.key)),
            now: now
        ))

        let becauseRails = rails.filter {
            if case .becauseYouWatched = $0.kind {
                true
            } else {
                false
            }
        }
        #expect(becauseRails.map(\.subject) == ["Seed 1", "Seed 2"])
    }

    @Test
    func `a film from the same series is alike even with nothing else to go on`() {
        let seed = title(1, name: "Toy Story (1995)", category: nil, year: nil, rating: nil)
        let sequels = (2 ... 6).map { title($0, name: "Toy Story \($0)", category: nil, year: nil, rating: nil) }
        let other = title(40, name: "Heat", category: nil, year: nil, rating: nil)

        let rails = build(DiscoveryInput(
            titles: [seed, other] + sequels,
            seeds: [DiscoverySeed(key: seed.key, weight: 1)],
            unavailable: [seed.key],
            now: now
        ))

        let because = rail(.becauseYouWatched(seed: seed.key), in: rails)
        #expect(Set(because?.keys ?? []) == Set(sequels.map(\.key)))
    }

    // MARK: - The rest

    @Test
    func `most watched shows what is watched most, including what is watched`() {
        let titles = (1 ... 8).map { title($0) }
        let counts = [
            PlayCount(key: titles[0].key, times: 5), PlayCount(key: titles[1].key, times: 4),
            PlayCount(key: titles[2].key, times: 3), PlayCount(key: titles[3].key, times: 3),
            PlayCount(key: titles[4].key, times: 2), PlayCount(key: titles[5].key, times: 1)
        ]

        let rails = build(DiscoveryInput(
            titles: titles, unavailable: Set(titles.map(\.key)), playCounts: counts, now: now
        ))

        let keys = rail(.mostWatched, in: rails)?.keys ?? []
        #expect(keys.prefix(2) == [titles[0].key, titles[1].key])
        #expect(keys.count == 5, "the title opened once is not 'most watched'")
    }

    @Test
    func `a genre with enough well-liked titles gets a rail, a small one does not`() {
        // Liked, but under the bar for "top rated", which would otherwise take every one of them.
        let drama = (1 ... 7).map { title($0, .series, rating: 7.0, genres: ["drama"]) }
        let western = (20 ... 22).map { title($0, .series, rating: 7.0, genres: ["western"]) }

        let rails = build(DiscoveryInput(titles: drama + western, now: now))

        #expect(rail(.genre(.series, "drama"), in: rails) != nil)
        #expect(rail(.genre(.series, "western"), in: rails) == nil)
    }

    @Test
    func `three or more films that share a title form a series, in release order`() {
        let sequels = [
            title(1, name: "Toy Story 3 (2010)", year: 2010), title(2, name: "Toy Story (1995)", year: 1995),
            title(3, name: "Toy Story 2 (1999)", year: 1999)
        ]
        let words = ["Harbour", "Lantern", "Meadow", "Orchard", "Quarry", "Ravine", "Summit"]
        let filler = words.enumerated().map { title(10 + $0, name: $1, year: 2000 + $0) }

        let rails = build(DiscoveryInput(titles: sequels + filler, now: now))

        let franchise = rails.first {
            if case .franchise = $0.kind {
                true
            } else {
                false
            }
        }
        #expect(franchise?.subject == "toy story")
        #expect(franchise?.keys == ["p|movie:2", "p|movie:3", "p|movie:1"])
    }

    @Test
    func `classics and decades gather older well-liked films`() throws {
        // Well liked but under the bar for "top rated", which would otherwise take them first.
        let nineties = (1 ... 6).map { title($0, year: 1990 + $0, rating: 7.2) }
        let eighties = (10 ... 15).map { title($0, year: 1980 + $0 % 10, rating: 7.1) }

        let rails = build(DiscoveryInput(titles: nineties + eighties, now: now))

        let classics = try #require(rail(.classics(.movie), in: rails))
        #expect(Set(classics.keys) == Set((nineties + eighties).map(\.key)))
    }

    @Test
    func `the same input gives the same rails`() {
        let titles = (1 ... 90).map { title(
            $0,
            year: 2000 + $0 % 27,
            rating: 6.0 + Double($0 % 40) / 10,
            genres: ["g\($0 % 4)"],
            tmdb: $0
        ) }
        let input = DiscoveryInput(
            titles: titles,
            seeds: [DiscoverySeed(key: titles[3].key, weight: 1)],
            trending: (1 ... 30).map { TrendingEntry(kind: .movie, tmdbID: $0, score: Double($0)) },
            now: now
        )

        #expect(build(input) == build(input))
        #expect(
            build(input) == build(DiscoveryInput(
                titles: titles.reversed(),
                seeds: input.seeds,
                trending: input.trending,
                now: now
            )),
            "and in whatever order the candidates arrive"
        )
    }

    @Test
    func `an empty library has no rails`() {
        #expect(build(DiscoveryInput(titles: [], now: now)).isEmpty)
    }

    @Test
    func `live channels and unknown kinds are never rails' material`() {
        let live = (1 ... 20).map { title($0, .live, rating: 9.0) }

        #expect(build(DiscoveryInput(titles: live, now: now)).isEmpty)
    }
}
