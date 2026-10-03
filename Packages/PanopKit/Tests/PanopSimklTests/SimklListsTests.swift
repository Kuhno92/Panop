import Foundation
import PanopCore
import PanopDiscover
@testable import PanopSimkl
import Testing

@Suite("Simkl lists")
struct SimklListsTests {
    /// 2026-10-03.
    private let now = Date(timeIntervalSince1970: 1_790_985_600)

    private func date(_ daysAgo: Double) -> Date {
        now.addingTimeInterval(-daysAgo * 86400)
    }

    private func film(
        _ id: Int, position: Int = 0, rating: Double? = 7, votes: Int = 5000, box: Double? = nil,
        genres: [String] = [], runtime: Int? = 110, theatres: Double? = nil, dvd: Double? = nil,
        released: Double? = nil, watchlisted: Int = 100, watched: Int = 100
    ) -> SimklTitle {
        SimklTitle(
            kind: .movie, tmdbID: id, link: "https://simkl.com/movies/\(id)", position: position, genres: genres,
            simklRating: rating, simklVotes: votes, imdbRating: rating, imdbVotes: votes,
            releaseDate: released.map(date), theatricalDate: theatres.map(date), dvdDate: dvd.map(date),
            runtimeMinutes: runtime, boxOffice: box, status: nil, watchlisted: watchlisted, watched: watched
        )
    }

    private func show(
        _ id: Int,
        position: Int = 0,
        network: String?,
        rating: Double? = 7,
        status: String = "ongoing"
    ) -> SimklTitle {
        SimklTitle(
            kind: .series, tmdbID: id, position: position, network: network, simklRating: rating, simklVotes: 500,
            imdbRating: rating, imdbVotes: 9000, status: status
        )
    }

    private func ids(_ id: String, _ kind: MediaKind, in lists: [CuratedList]) -> [Int]? {
        lists.first { $0.id == id && $0.kind == kind }?.entries.map(\.tmdbID)
    }

    @Test
    func `top box office is by takings, biggest first, and leaves out films with none`() {
        let lists = SimklLists.build(
            movies: [film(1, box: 100_000_000), film(2, box: 2_500_000_000), film(3), film(4, box: 300_000_000)],
            series: [], dvd: [], now: now
        )

        #expect(ids("boxOffice", .movie, in: lists) == [2, 4, 1])
        #expect(lists.first { $0.id == "boxOffice" }?.isHighlight == true)
    }

    @Test
    func `a service's list is its own series, best rated first, whatever the case or the suffix`() {
        let lists = SimklLists.build(
            movies: [],
            series: [
                show(1, network: "Netflix", rating: 7.0), show(2, network: "HBO Max", rating: 9.0),
                show(3, network: "netflix", rating: 8.5), show(4, network: "CBS", rating: 9.5), show(5, network: nil)
            ],
            dvd: [], now: now
        )

        #expect(ids("network.Netflix", .series, in: lists) == [3, 1])
        #expect(ids("network.HBO", .series, in: lists) == [2])
        #expect(ids("network.Disney+", .series, in: lists) == nil, "no series, no list")
        #expect(lists.first { $0.id == "network.Netflix" }?.isHighlight == true)
    }

    @Test
    func `a title with too few votes does not rank as best rated`() {
        let lists = SimklLists.build(
            movies: [film(1, rating: 9.8, votes: 3), film(2, rating: 7.5), film(3, rating: 8.2)],
            series: [], dvd: [], now: now
        )

        #expect(ids("topRated", .movie, in: lists) == [3, 2])
    }

    @Test
    func `a genre list holds only that genre, whichever way it is spelled, once per title`() {
        let lists = SimklLists.build(
            movies: [
                film(1, rating: 7, genres: ["Science Fiction", "Science Fiction", "Action"]),
                film(2, rating: 8, genres: ["Science-Fiction"]), film(3, genres: ["Drama"])
            ],
            series: [], dvd: [], now: now
        )

        #expect(ids("genre.Science Fiction", .movie, in: lists) == [2, 1])
        #expect(ids("genre.Action", .movie, in: lists) == [1])
    }

    @Test
    func `a decade list is by release year`() {
        let calendar = Calendar.simkl
        let ninety = calendar.date(from: DateComponents(year: 1994, month: 5, day: 1))
        let twenty = calendar.date(from: DateComponents(year: 2023, month: 5, day: 1))
        var old = film(1)
        old.releaseDate = ninety
        var new = film(2)
        new.releaseDate = twenty

        let lists = SimklLists.build(movies: [old, new], series: [], dvd: [], now: now)

        #expect(ids("decade.1990", .movie, in: lists) == [1])
        #expect(ids("decade.2020", .movie, in: lists) == [2])
    }

    @Test
    func `in theatres is opened lately and not on disc yet`() {
        let lists = SimklLists.build(
            movies: [
                film(1, theatres: 10), film(2, theatres: 120), film(3, theatres: 20, dvd: 2),
                film(4, theatres: 20, dvd: -5), film(5)
            ],
            series: [], dvd: [], now: now
        )

        #expect(ids("inTheatres", .movie, in: lists) == [1, 4])
    }

    @Test
    func `quick watches are 90 minutes or less and decently rated`() {
        let lists = SimklLists.build(
            movies: [
                film(1, runtime: 85),
                film(2, runtime: 120),
                film(3, rating: 4.0, runtime: 80),
                film(4, runtime: nil)
            ],
            series: [], dvd: [], now: now
        )

        #expect(ids("quickWatches", .movie, in: lists) == [1])
    }

    @Test
    func `hidden gems are well rated and watched by fewer than most`() {
        let crowd = (10 ... 19).map { film($0, rating: 6.0, watchlisted: 5000, watched: 5000) }
        let lists = SimklLists.build(
            movies: crowd + [
                film(1, rating: 8.4, watchlisted: 10, watched: 20),
                film(2, rating: 8.9, watchlisted: 9000, watched: 9000)
            ],
            series: [], dvd: [], now: now
        )

        #expect(ids("hiddenGems", .movie, in: lists) == [1], "a favourite everyone has seen is not a gem")
    }

    @Test
    func `currently airing and premieres are series, and the disc releases keep their order`() {
        let lists = SimklLists.build(
            movies: [],
            series: [show(1, network: "A", status: "ongoing"), show(2, network: "B", status: "ended")],
            dvd: [film(7), film(8), film(9)], now: now
        )

        #expect(ids("airing", .series, in: lists) == [1])
        #expect(ids("justOnDVD", .movie, in: lists) == [7, 8, 9])
    }

    @Test
    func `a list is cut to a hundred, with no title twice, and carries Simkl's link`() {
        let many = (1 ... 150).map { film($0, position: $0, box: Double($0) * 1_000_000) }
        let doubled = many + [film(1, box: 9_000_000_000)]

        let lists = SimklLists.build(movies: doubled, series: [], dvd: [], now: now)

        let box = lists.first { $0.id == "boxOffice" }
        #expect(box?.entries.count == 100)
        #expect(Set(box?.entries.map(\.tmdbID) ?? []).count == 100)
        #expect(box?.entries.first?.link == "https://simkl.com/movies/1")
        #expect(box?.entries.first?.score ?? 0 > box?.entries.last?.score ?? 1, "the scores keep the order")
    }
}

@Suite("Simkl list files")
struct SimklFileTests {
    private let sample = """
    [{"title":"Flowervale","url":"/movies/2123791/flowervale","ids":{"simkl_id":1,"tmdb":"1101383"},
      "release_date":"08/12/2026","theater":"08/12/2026","dvd_date":"09/15/2026","runtime":"1h 40m",
      "genres":["Action","Action","Mystery"],"status":"ended","plan_to_watch":2964,"watched":977,
      "ratings":{"simkl":{"rating":6.18,"votes":899},"imdb":{"rating":6.2,"votes":70585}},
      "metadata":"August 12, 2026 • Budget $85M • Box office $2,496M"},
     {"title":"No id","ids":{"simkl_id":2}},
     {"title":"Series","url":"/tv/5/s","ids":{"tmdb":1399},"network":"HBO","runtime":"45m","genres":["Drama"]}]
    """

    @Test
    func `a title is read with its ratings, dates, runtime, genres and takings`() throws {
        let titles = try #require(SimklFile.titles(from: Data(sample.utf8), kind: .movie))

        let first = try #require(titles.first)
        #expect(titles.count == 2, "a title with no TMDB id is left out")
        #expect(first.tmdbID == 1_101_383)
        #expect(first.link == "https://simkl.com/movies/2123791/flowervale")
        #expect(first.genres == ["Action", "Mystery"])
        #expect(first.runtimeMinutes == 100)
        #expect(first.boxOffice == 2_496_000_000)
        #expect(first.imdbVotes == 70585 && first.simklVotes == 899)
        #expect(first.watchlisted == 2964 && first.watched == 977)
        #expect(first.position == 0)
        #expect(first.score != nil)
        let released = try #require(first.releaseDate)
        #expect(Calendar.simkl.dateComponents([.year, .month, .day], from: released) == DateComponents(
            year: 2026,
            month: 8,
            day: 12
        ))
        #expect(first.theatricalDate == released)
        #expect(first.dvdDate != nil)
    }

    @Test
    func `a series carries its network and a runtime in minutes`() throws {
        let titles = try #require(SimklFile.titles(from: Data(sample.utf8), kind: .series))

        #expect(titles.last?.network == "HBO")
        #expect(titles.last?.runtimeMinutes == 45)
        #expect(titles.last?.position == 2, "its place in the file, counting the one left out")
    }

    @Test
    func `runtimes, dates and takings in odd forms read as far as they can`() {
        #expect(SimklFile.minutes("2h") == 120)
        #expect(SimklFile.minutes("1h 5m") == 65)
        #expect(SimklFile.minutes("soon") == nil)
        #expect(SimklFile.date("13/45/2026") == nil)
        #expect(SimklFile.date("nonsense") == nil)
        #expect(SimklFile.boxOffice("Box office $1.5B") == 1_500_000_000)
        #expect(SimklFile.boxOffice("Box office $850K") == 850_000)
        #expect(SimklFile.boxOffice("Budget $85M") == nil)
    }

    @Test
    func `something that is not a list is not read`() {
        #expect(SimklFile.titles(from: Data("<html>".utf8), kind: .movie) == nil)
        #expect(SimklFile.titles(from: Data(#"{"error":"x"}"#.utf8), kind: .movie) == nil)
    }
}
