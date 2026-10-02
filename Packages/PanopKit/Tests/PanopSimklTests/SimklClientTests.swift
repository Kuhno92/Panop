import Foundation
import PanopCore
@testable import PanopSimkl
import Testing

private final class Echo: HTTPTransport, @unchecked Sendable {
    let status: Int
    let body: String
    private let lock = NSLock()
    private var seen: [HTTPRequest] = []

    init(status: Int = 200, body: String = "{}") {
        self.status = status
        self.body = body
    }

    var requests: [HTTPRequest] {
        lock.withLock { seen }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { seen.append(request) }
        return HTTPResponse(statusCode: status, body: Data(body.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

@Suite("Simkl account calls")
struct SimklClientTests {
    private let app = SimklApp(clientID: "cid", version: "1.0")
    private let day = Date(timeIntervalSince1970: 1_780_000_000)

    private func client(_ transport: Echo, token: String? = "TOKEN") -> SimklClient {
        SimklClient(transport: transport, app: app) { token }
    }

    @Test
    func `a batch is one call, grouping episodes by show and season`() async throws {
        let transport = Echo()

        try await client(transport).addHistory([
            .movie(tmdb: 603, at: day),
            .episode(showTMDB: 1399, season: 1, number: 2, at: day),
            .episode(showTMDB: 1399, season: 1, number: 1, at: day),
            .episode(showTMDB: 1399, season: 2, number: 1, at: day)
        ])

        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path == "/sync/history")
        #expect(request.headers["Authorization"] == "Bearer TOKEN")
        let payload = try #require(request.body)
        let json = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let movies = try #require(json["movies"] as? [[String: Any]])
        #expect((movies.first?["ids"] as? [String: Int])?["tmdb"] == 603)
        let shows = try #require(json["shows"] as? [[String: Any]])
        #expect(shows.count == 1)
        let seasons = try #require(shows.first?["seasons"] as? [[String: Any]])
        #expect(seasons.map { $0["number"] as? Int } == [1, 2])
        #expect((seasons.first?["episodes"] as? [[String: Any]])?.count == 2)
    }

    @Test
    func `nothing to record is no call`() async throws {
        let transport = Echo()
        try await client(transport).addHistory([])
        #expect(transport.requests.isEmpty)
    }

    @Test
    func `no token means no call and an unauthorized error`() async {
        let transport = Echo()
        await #expect(throws: SimklError.unauthorized) { try await client(transport, token: nil).activities() }
        #expect(transport.requests.isEmpty)
    }

    @Test
    func `status codes become the errors a caller acts on`() async {
        await #expect(throws: SimklError.unauthorized) { try await client(Echo(status: 401)).activities() }
        await #expect(throws: SimklError.rateLimited(retryAfter: 60)) {
            try await client(Echo(status: 429)).activities()
        }
        await #expect(throws: SimklError.status(500)) { try await client(Echo(status: 500)).activities() }
    }

    @Test
    func `the lists are read leniently, films and shows, skipping what has no TMDB id`() async throws {
        let body = """
        {"shows":[
          {"status":"watching","user_rating":9,"next_to_watch":"S01E04","last_watched_at":"2026-09-01T10:00:00Z",
           "show":{"title":"A","ids":{"simkl":1,"tmdb":"1399"}}},
          {"status":"watching","next_to_watch_info":{"title":"x","season":2,"episode":5,"date":"2026-10-01T00:00:00Z"},
           "show":{"ids":{"tmdb":77}}},
          {"status":"completed","show":{"title":"B","ids":{"simkl":2}}},
          {"status":"nonsense","show":{"ids":{"tmdb":5}}},
          {"broken":true}],
         "movies":[{"status":"plantowatch","movie":{"ids":{"tmdb":603}}}],
         "anime":null}
        """

        let items = try await client(Echo(body: body)).library()

        #expect(items == [
            SimklListItem(
                kind: .series, tmdbID: 1399, status: .watching, rating: 9,
                next: SimklNextEpisode(season: 1, number: 4), lastWatchedAt: "2026-09-01T10:00:00Z"
            ),
            SimklListItem(
                kind: .series, tmdbID: 77, status: .watching,
                next: SimklNextEpisode(season: 2, number: 5, airDate: "2026-10-01T00:00:00Z")
            ),
            SimklListItem(kind: .movie, tmdbID: 603, status: .plantowatch, rating: nil)
        ])
    }

    @Test
    func `activities and a delta ask for only what changed`() async throws {
        let transport = Echo(body: #"{"all":"2026-05-01T10:00:00Z"}"#)
        let simkl = client(transport)

        #expect(try await simkl.activities().all == "2026-05-01T10:00:00Z")
        _ = try await simkl.library(since: "2026-05-01T10:00:00Z")

        let query = transport.requests.last
            .flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems }
        #expect(query?.contains { $0.name == "date_from" && $0.value == "2026-05-01T10:00:00Z" } == true)
        #expect(query?.contains { $0.name == "client_id" && $0.value == "cid" } == true)
        #expect(query?.contains { $0.name == "extended" } == false, "ids_only would drop the status")
        #expect(query?.contains { $0.name == "next_watch_info" && $0.value == "yes" } == true)
    }
}
