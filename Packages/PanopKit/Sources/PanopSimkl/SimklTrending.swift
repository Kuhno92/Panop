import Foundation
import PanopCore
import PanopDiscover

/// Simkl's public trending lists: one JSON file per kind and period, served from a static host and
/// free of any key or per-user quota. Their terms ask that the list be named as Simkl's and that each
/// title link back to its Simkl page, which is why every entry carries `link`.
public struct SimklTrendingSource: Sendable {
    public enum Period: String, Sendable {
        case today, week, month
    }

    public enum Failure: Error, Equatable {
        case status(Int)
        case undecodable
    }

    static let host = "https://data.simkl.in"
    static let site = "https://simkl.com"

    private let transport: any HTTPTransport
    private let app: SimklApp

    public init(transport: any HTTPTransport, app: SimklApp) {
        self.transport = transport
        self.app = app
    }

    /// What the three public files give: the trending rail and the lists made from them.
    public struct Snapshot: Sendable, Equatable, Codable {
        public var trending: [TrendingEntry]
        public var lists: [CuratedList]

        public init(trending: [TrendingEntry], lists: [CuratedList]) {
            self.trending = trending
            self.lists = lists
        }
    }

    /// Fetches this week's trending films and series (500 of each) and the latest disc releases, and makes
    /// the trending rail and every list from them: 1 to 3 MB in all, so it is asked for rarely. A failure of
    /// the films or the series is a failure; the disc releases alone may be missing.
    public func snapshot(now: Date = .now) async throws -> Snapshot {
        let movies = try await titles("trending/movies/week_500", kind: .movie)
        let series = try await titles("trending/tv/week_500", kind: .series)
        let dvd = await (try? titles("dvd/releases_500", kind: .movie)) ?? []
        // The first hundred of each are what is trending; the rest are there for the lists to choose from.
        let trending = SimklLists.entries(of: Array(movies.prefix(100))) + SimklLists
            .entries(of: Array(series.prefix(100)))
        return Snapshot(trending: trending, lists: SimklLists.build(movies: movies, series: series, dvd: dvd, now: now))
    }

    private func titles(_ path: String, kind: MediaKind) async throws -> [SimklTitle] {
        guard let url = app.url("\(Self.host)/discover/\(path).json") else { throw Failure.undecodable }
        // No Authorization: these are cached files, the same for everyone.
        let response = try await transport.send(HTTPRequest(
            url: url,
            headers: ["User-Agent": app.userAgent, "Accept": "application/json"],
            timeout: 30
        ))
        guard response.statusCode == 200 else { throw Failure.status(response.statusCode) }
        guard let titles = SimklFile.titles(from: response.body, kind: kind) else { throw Failure.undecodable }
        return titles
    }

    /// The most popular titles of one kind, most popular first. Entries without a TMDB id are left out,
    /// since there is nothing to match them to a library by.
    public func trending(_ kind: MediaKind, period: Period = .week) async throws -> [TrendingEntry] {
        guard kind == .movie || kind == .series else { return [] }
        let path = kind == .movie ? "movies" : "tv"
        guard let url = app.url("\(Self.host)/discover/trending/\(path)/\(period.rawValue)_100.json") else {
            throw Failure.undecodable
        }
        // No Authorization: these are cached files, the same for everyone.
        let response = try await transport.send(HTTPRequest(
            url: url,
            headers: ["User-Agent": app.userAgent, "Accept": "application/json"],
            timeout: 20
        ))
        guard response.statusCode == 200 else { throw Failure.status(response.statusCode) }
        guard let items = try? JSONDecoder().decode([Item].self, from: response.body) else {
            throw Failure.undecodable
        }
        let usable = items.compactMap { item -> (Int, String?)? in
            guard let id = item.tmdbID else { return nil }
            return (id, item.url.map { Self.site + $0 })
        }
        // Simkl lists them best first; the score only has to keep that order.
        return usable.enumerated().map { index, found in
            TrendingEntry(kind: kind, tmdbID: found.0, score: Double(usable.count - index), link: found.1)
        }
    }

    private struct Item: Decodable {
        var url: String?
        var tmdbID: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: ItemKeys.self)
            url = try? container.decodeIfPresent(String.self, forKey: .url)
            // The id is a string in one file and a number in another.
            if let ids = try? container.nestedContainer(keyedBy: IDKeys.self, forKey: .ids) {
                if let number = try? ids.decodeIfPresent(Int.self, forKey: .tmdb) {
                    tmdbID = number
                } else if let text = try? ids.decodeIfPresent(String.self, forKey: .tmdb) {
                    tmdbID = Int(text)
                }
            }
        }
    }
}

private enum ItemKeys: String, CodingKey { case url, ids }
private enum IDKeys: String, CodingKey { case tmdb }
