import Foundation
import PanopCore

public enum SimklError: Error, Equatable {
    /// No usable token: signed out, or the token was refused.
    case unauthorized
    /// Too many requests; try again after this many seconds.
    case rateLimited(retryAfter: TimeInterval)
    case status(Int)
    case undecodable
}

/// A film or episode the person finished, to be recorded on their Simkl account.
public enum SimklWatched: Sendable, Equatable, Codable {
    case movie(tmdb: Int, at: Date)
    case episode(showTMDB: Int, season: Int, number: Int, at: Date)
}

/// Where a title stands on the person's Simkl lists.
public struct SimklListItem: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable {
        case watching, plantowatch, completed, hold, dropped
    }

    public var kind: MediaKind
    public var tmdbID: Int
    public var status: Status
    /// 1 to 10, when they rated it.
    public var rating: Int?
    /// For a show being watched, the episode they are up to, as `S01E04`.
    public var nextToWatch: String?

    public init(kind: MediaKind, tmdbID: Int, status: Status, rating: Int? = nil, nextToWatch: String? = nil) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.status = status
        self.rating = rating
        self.nextToWatch = nextToWatch
    }
}

/// What changed on the account, by list, as Simkl's own timestamps. Compared as text: they are only
/// ever checked for being different from the ones saved last time.
public struct SimklActivities: Sendable, Equatable, Codable {
    public var all: String

    public init(all: String) {
        self.all = all
    }
}

/// Calls to the person's Simkl account. Each takes the token afresh from `token`, which is where
/// renewal lives, so no call here holds on to one.
public struct SimklClient: Sendable {
    static let host = "https://api.simkl.com"

    private let transport: any HTTPTransport
    private let app: SimklApp
    private let token: @Sendable () async -> String?

    public init(transport: any HTTPTransport, app: SimklApp, token: @escaping @Sendable () async -> String?) {
        self.transport = transport
        self.app = app
        self.token = token
    }

    /// Records finished films and episodes. One call for the whole batch: Simkl allows one write at a
    /// time per person, so a batch is what keeps within it.
    public func addHistory(_ items: [SimklWatched]) async throws {
        guard !items.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: Self.historyBody(items))
        _ = try await call("/sync/history", method: "POST", body: body)
    }

    public func activities() async throws -> SimklActivities {
        let data = try await call("/sync/activities")
        guard let reply = try? JSONDecoder().decode(ActivitiesReply.self, from: data) else {
            throw SimklError.undecodable
        }
        return SimklActivities(all: reply.all ?? "")
    }

    /// Films and shows on the person's lists. `since` limits it to what changed after that timestamp.
    public func library(since: String? = nil) async throws -> [SimklListItem] {
        var query = [
            URLQueryItem(name: "extended", value: "ids_only"),
            URLQueryItem(name: "next_watch_info", value: "yes")
        ]
        if let since {
            query.append(URLQueryItem(name: "date_from", value: since))
        }
        let data = try await call("/sync/all-items", query: query)
        guard let reply = try? JSONDecoder().decode(LibraryReply.self, from: data) else { throw SimklError.undecodable }
        return reply.items
    }

    // MARK: - Wire

    private func call(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        guard let token = await token(), let url = app.url(Self.host + path, query: query) else {
            throw SimklError.unauthorized
        }
        var headers = [
            "User-Agent": app.userAgent, "Accept": "application/json", "Authorization": "Bearer \(token)"
        ]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        let response = try await transport.send(HTTPRequest(
            url: url, headers: headers, timeout: 30, method: method, body: body
        ))
        switch response.statusCode {
        case 200 ..< 300: return response.body
        case 401: throw SimklError.unauthorized
        case 429: throw SimklError.rateLimited(retryAfter: 60)
        default: throw SimklError.status(response.statusCode)
        }
    }

    static func historyBody(_ items: [SimklWatched]) -> [String: Any] {
        let stamp = ISO8601DateFormatter()
        var movies: [[String: Any]] = []
        var shows: [Int: [Int: [[String: Any]]]] = [:]
        for item in items {
            switch item {
            case let .movie(tmdb, date):
                movies.append(["ids": ["tmdb": tmdb], "watched_at": stamp.string(from: date)])
            case let .episode(show, season, number, date):
                shows[show, default: [:]][season, default: []]
                    .append(["number": number, "watched_at": stamp.string(from: date)])
            }
        }
        var body: [String: Any] = [:]
        if !movies.isEmpty {
            body["movies"] = movies
        }
        if !shows.isEmpty {
            body["shows"] = shows.keys.sorted().map { show in
                let seasons = (shows[show] ?? [:]).keys.sorted().map { season in
                    ["number": season, "episodes": shows[show]?[season] ?? []] as [String: Any]
                }
                return ["ids": ["tmdb": show], "seasons": seasons] as [String: Any]
            }
        }
        return body
    }
}

private struct ActivitiesReply: Decodable {
    var all: String?
}

/// Reads the lists leniently: one odd item costs that item, not the whole library.
private struct LibraryReply: Decodable {
    var items: [SimklListItem]

    private enum Keys: String, CodingKey { case shows, movies }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let shows = (try? container.decodeIfPresent([Lenient<Entry>].self, forKey: .shows)) ?? []
        let movies = (try? container.decodeIfPresent([Lenient<Entry>].self, forKey: .movies)) ?? []
        items = shows.compactMap { $0.value?.item(.series) } + movies.compactMap { $0.value?.item(.movie) }
    }
}

private struct Lenient<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct Entry: Decodable {
    var status: String?
    var userRating: Int?
    var nextToWatch: String?
    var show: EntryStub?
    var movie: EntryStub?

    enum CodingKeys: String, CodingKey {
        case status, show, movie
        case userRating = "user_rating"
        case nextToWatch = "next_to_watch"
    }

    func item(_ kind: MediaKind) -> SimklListItem? {
        guard let id = (kind == .movie ? movie : show)?.ids?.tmdb, id > 0,
              let status = status.flatMap(SimklListItem.Status.init) else { return nil }
        return SimklListItem(kind: kind, tmdbID: id, status: status, rating: userRating, nextToWatch: nextToWatch)
    }
}

private struct EntryStub: Decodable {
    var ids: EntryIDs?
}

private struct EntryIDs: Decodable {
    var tmdb: Int?

    private enum Keys: String, CodingKey { case tmdb }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        // A number in one file and a string in another.
        tmdb = (try? container.decodeIfPresent(Int.self, forKey: .tmdb))
            ?? (try? container.decodeIfPresent(String.self, forKey: .tmdb)).flatMap { $0.flatMap(Int.init) }
    }
}
