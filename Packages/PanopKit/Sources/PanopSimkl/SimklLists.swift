import Foundation
import PanopCore
import PanopDiscover

/// Turns Simkl's public lists into the rows its own apps show: "Top Box Office", "Best of Netflix",
/// "Hidden Gems" and the rest. Simkl publishes the lists with what is known of each title, and these rows
/// are made from that, here, so none of them needs a login or another request.
///
/// The recipes are ours: Simkl names the rows but not how they are cut. Each takes the titles of one list
/// and keeps the best 100, as a `CuratedList` that the app joins to the library by TMDB id.
public enum SimklLists {
    /// How many titles a list keeps. The app shows far fewer; this is what it has to choose from.
    public static let listSize = 100

    public static let movieGenres = ["Action", "Drama", "Comedy", "Science Fiction", "Thriller", "Horror"]
    public static let seriesGenres = ["Drama", "Comedy", "Crime", "Science Fiction"]
    public static let decades = [2020, 2010, 2000, 1990]
    /// The services, by the name Simkl gives their series.
    public static let networks = ["Netflix", "HBO", "Disney+", "Prime Video", "Apple TV"]

    /// How long a film counts as "in theatres" after it opened, if it is not out on disc yet.
    static let theatreDays = 75.0
    /// How recent a premiere is to be called new.
    static let premiereDays = 30.0

    /// - Parameters:
    ///   - movies: the trending films, in their order.
    ///   - series: the trending series, in their order.
    ///   - dvd: the latest disc releases, in their order.
    public static func build(
        movies: [SimklTitle],
        series: [SimklTitle],
        dvd: [SimklTitle],
        now: Date
    ) -> [CuratedList] {
        var lists: [CuratedList] = []
        func add(_ id: String, _ kind: MediaKind, highlight: Bool = false, _ titles: [SimklTitle]) {
            let entries = entries(of: titles)
            if !entries.isEmpty {
                lists.append(CuratedList(id: id, kind: kind, isHighlight: highlight, entries: entries))
            }
        }

        // Films.
        add(
            "boxOffice",
            .movie,
            highlight: true,
            movies.filter { ($0.boxOffice ?? 0) > 0 }
                .sorted { ($0.boxOffice ?? 0, $1.position) > ($1.boxOffice ?? 0, $0.position) }
        )
        add("inTheatres", .movie, inTheatres(movies, now: now))
        add("justOnDVD", .movie, dvd)
        add("premieres", .movie, premieres(movies, now: now))
        add("hiddenGems", .movie, hiddenGems(movies))
        add("topRated", .movie, byScore(movies))
        add("mostWatchlisted", .movie, movies.sorted { ($0.watchlisted, $1.position) > ($1.watchlisted, $0.position) })
        add("quickWatches", .movie, movies.filter { ($0.runtimeMinutes ?? .max) <= 90 && ($0.score ?? 0) >= 6 })
        for genre in movieGenres {
            add("genre.\(genre)", .movie, byScore(movies.filter { $0.hasGenre(genre) }))
        }
        for decade in decades {
            add("decade.\(decade)", .movie, byScore(movies.filter { ($0.year ?? 0) / 10 * 10 == decade }))
        }

        // Series.
        for network in networks {
            add(
                "network.\(network)",
                .series,
                highlight: network == "Netflix",
                byScore(series.filter { isOn($0, network) }, keepUnrated: true)
            )
        }
        add("airing", .series, series.filter { $0.status == "ongoing" })
        add("premieres", .series, premieres(series, now: now))
        add("hiddenGems", .series, hiddenGems(series))
        add("topRated", .series, byScore(series))
        add("mostWatchlisted", .series, series.sorted { ($0.watchlisted, $1.position) > ($1.watchlisted, $0.position) })
        for genre in seriesGenres {
            add("genre.\(genre)", .series, byScore(series.filter { $0.hasGenre(genre) }))
        }
        return lists
    }

    // MARK: - Recipes

    /// Best rated first. Titles nobody rated enough to count are left out, unless asked to keep them (at the
    /// end), for a list where being on it is the point.
    static func byScore(_ titles: [SimklTitle], keepUnrated: Bool = false) -> [SimklTitle] {
        let ordered = titles.sorted {
            let (left, right) = ($0.score ?? -1, $1.score ?? -1)
            return left == right ? $0.position < $1.position : left > right
        }
        return keepUnrated ? ordered : ordered.filter { $0.score != nil }
    }

    /// Well rated by those who saw it, and seen by fewer than most: below the middle of the list for
    /// audience, at 7.3 or more.
    static func hiddenGems(_ titles: [SimklTitle]) -> [SimklTitle] {
        let audiences = titles.map { $0.watched + $0.watchlisted }.sorted()
        guard !audiences.isEmpty else { return [] }
        let median = audiences[audiences.count / 2]
        return byScore(titles.filter { ($0.score ?? 0) >= 7.3 && $0.watched + $0.watchlisted < median })
    }

    /// Opened lately and not yet on disc, in trending order.
    static func inTheatres(_ titles: [SimklTitle], now: Date) -> [SimklTitle] {
        titles.filter { title in
            guard let opened = title.theatricalDate, opened <= now,
                  now.timeIntervalSince(opened) <= theatreDays * 86400 else { return false }
            return title.dvdDate.map { $0 > now } ?? true
        }
    }

    /// Started in the last month, or marked as a premiere, in trending order.
    static func premieres(_ titles: [SimklTitle], now: Date) -> [SimklTitle] {
        titles.filter { title in
            if let released = title.releaseDate, released <= now,
               now.timeIntervalSince(released) <= premiereDays * 86400
            {
                return true
            }
            return false
        }
    }

    /// Whether a series is on a service: by name, ignoring case, so "HBO Max" is HBO.
    static func isOn(_ title: SimklTitle, _ network: String) -> Bool {
        title.network?.lowercased().contains(network.lowercased()) == true
    }

    static func entries(of titles: [SimklTitle]) -> [TrendingEntry] {
        var seen = Set<Int>()
        let unique = titles.filter { seen.insert($0.tmdbID).inserted }.prefix(listSize)
        return unique.enumerated().map {
            TrendingEntry(
                kind: $1.kind,
                tmdbID: $1.tmdbID,
                score: Double(unique.count - $0),
                link: $1.link,
                fanart: $1.fanart
            )
        }
    }
}
