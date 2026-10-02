import Foundation
import PanopCore
@testable import PanopSimkl
import Testing

private final class Canned: HTTPTransport, @unchecked Sendable {
    let status: Int
    let body: String
    private let lock = NSLock()
    private var seen: [HTTPRequest] = []

    init(status: Int = 200, body: String) {
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

@Suite("Simkl trending")
struct SimklTrendingTests {
    private let list = """
    [{"title":"A","url":"/tv/1/a","ids":{"simkl_id":1,"tmdb":"95350"}},
     {"title":"B","url":"/tv/2/b","ids":{"simkl_id":2}},
     {"title":"C","url":"/tv/3/c","ids":{"simkl_id":3,"tmdb":1399}},
     {"title":"D","ids":{"tmdb":"7"}},
     {"nonsense":true}]
    """

    private func source(_ transport: Canned) -> SimklTrendingSource {
        SimklTrendingSource(transport: transport, userAgent: "Panop/1.0")
    }

    @Test
    func `entries keep Simkl's order, drop those with no TMDB id and link to Simkl`() async throws {
        let entries = try await source(Canned(body: list)).trending(.series)

        #expect(entries.map(\.tmdbID) == [95350, 1399, 7])
        #expect(entries.map(\.score) == [3, 2, 1])
        #expect(entries.first?.link == "https://simkl.com/tv/1/a")
        #expect(entries.last?.link == nil)
        #expect(entries.allSatisfy { $0.kind == .series })
    }

    @Test
    func `films and series come from their own file, named by the app`() async throws {
        let transport = Canned(body: "[]")

        _ = try await source(transport).trending(.movie, period: .month)
        _ = try await source(transport).trending(.series)

        let urls = transport.requests.map(\.url.absoluteString)
        #expect(urls == [
            "https://data.simkl.in/discover/trending/movies/month_100.json",
            "https://data.simkl.in/discover/trending/tv/week_100.json"
        ])
        #expect(transport.requests.allSatisfy { $0.headers["User-Agent"] == "Panop/1.0" })
    }

    @Test
    func `a bad status or an unreadable body is a failure, not an empty list`() async {
        await #expect(throws: SimklTrendingSource.Failure.status(503)) {
            try await source(Canned(status: 503, body: "")).trending(.movie)
        }
        await #expect(throws: SimklTrendingSource.Failure.undecodable) {
            try await source(Canned(body: "<html>")).trending(.movie)
        }
    }

    @Test
    func `live channels have no trending list`() async throws {
        let transport = Canned(body: list)
        #expect(try await source(transport).trending(.live).isEmpty)
        #expect(transport.requests.isEmpty)
    }
}
