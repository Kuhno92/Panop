import Foundation
import PanopCore
import PanopDiscover
@testable import PanopSimkl
import Testing

private final class Router: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (String, [String: String]) -> (Int, String)
    private let lock = NSLock()
    private var seen: [URL] = []
    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var paths: [String] {
        lock.withLock { seen.map(\.path) }
    }

    var urls: [URL] {
        lock.withLock { seen }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { seen.append(request.url) }
        let query = Dictionary(
            (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { (
                $0.name,
                $0.value ?? ""
            ) },
            uniquingKeysWith: { first, _ in first }
        )
        let (status, body) = handler(request.url.path, query)
        return HTTPResponse(statusCode: status, body: Data(body.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

private func items(_ ids: ClosedRange<Int>, type: String? = nil) -> String {
    let rows = ids.map { id in
        #"{"title":"T\#(id)","ids":{"simkl_id":\#(id),"tmdb":"\#(id)"}\#(type.map { #","type":"\#($0)""# } ?? "")}"#
    }
    return "[" + rows.joined(separator: ",") + "]"
}

private func client(_ router: Router, token: String? = "TOKEN") -> SimklClient {
    SimklClient(transport: router, app: SimklApp(clientID: "cid", version: "1.0")) { token }
}

@Suite("Simkl account lists")
struct SimklAccountListsTests {
    @Test
    func `the account is read for its id and its plan`() async throws {
        let router = Router { _, _ in (200, #"{"user":{"name":"x"},"account":{"id":12345,"type":"pro"}}"#) }

        let account = try await client(router).account()

        #expect(account == SimklAccountInfo(id: 12345, plan: .pro))
        #expect(router.paths == ["/users/settings"])
    }

    @Test
    func `a ranking is read page by page, the order carried on, and stops at a short page`() async throws {
        let router = Router { _, query in
            switch query["page"] {
            case "1": (200, items(1 ... 60))
            case "2": (200, items(61 ... 70))
            default: (200, "[]")
            }
        }

        let titles = try await client(router).ranked("tv/genres/all/all/all/netflix/all/rank", kind: .series, pages: 5)

        #expect(titles.count == 70)
        #expect(titles.map(\.position) == Array(0 ..< 70))
        #expect(router.paths.count == 2, "the second page was short, so there is no third")
        #expect(router.urls.allSatisfy { $0.query?.contains("limit=60") == true })
    }

    @Test
    func `a ranking that does not exist is null, which is empty`() async throws {
        let router = Router { _, _ in (200, "null") }

        #expect(try await client(router).ranked("tv/genres/zzz/all/all/all/all/rank", kind: .series, pages: 3).isEmpty)
    }

    @Test
    func `the rankings replace the lists made from the public files, and only for the services Simkl names`(
    ) async throws {
        let router = Router { path, _ in
            path.contains("/netflix/") ? (200, items(100 ... 119)) : (200, "null")
        }

        let ranked = try await SimklAccountLists.ranked(client: client(router))

        #expect(ranked.map(\.id) == ["network.Netflix"], "the others returned nothing")
        #expect(ranked.first?.isHighlight == true)
        let slugs = router.paths.filter { $0.hasPrefix("/tv/genres/all/all/all/") }
        #expect(slugs.contains { $0.contains("/hbo/") } && slugs.contains { $0.contains("/apple-tv/") } && slugs
            .contains { $0.contains("/prime-video/") })
        #expect(!router.paths.contains { $0.contains("disney") }, "a name Simkl does not document is not guessed")
    }

    @Test
    func `a refused login stops the whole refresh`() async {
        let router = Router { _, _ in (401, "{}") }

        await #expect(throws: SimklError.unauthorized) { try await SimklAccountLists.ranked(client: client(router)) }
        #expect(router.paths.count == 1)
    }

    @Test
    func `one list failing leaves the others`() async throws {
        let router = Router { path, _ in
            path.contains("/hbo/") ? (500, "") : (200, items(1 ... 12))
        }

        let ranked = try await SimklAccountLists.ranked(client: client(router))

        #expect(!ranked.contains { $0.id == "network.HBO" })
        #expect(ranked.contains { $0.id == "network.Netflix" })
    }

    @Test
    func `merging puts the ranking where the list from the files was, and adds what was not there`() {
        func list(_ id: String, _ kind: MediaKind, _ tmdb: Int) -> CuratedList {
            CuratedList(id: id, kind: kind, entries: [TrendingEntry(kind: kind, tmdbID: tmdb, score: 1)])
        }
        let base = [list("topRated", .movie, 1), list("network.Netflix", .series, 2), list("genre.Drama", .movie, 3)]
        let better = [list("network.Netflix", .series, 99), list("genre.Drama", .series, 77)]

        let merged = SimklAccountLists.merging(base, with: better)

        #expect(merged.map(\.id) == ["topRated", "network.Netflix", "genre.Drama", "genre.Drama"])
        #expect(merged[1].entries.first?.tmdbID == 99)
        #expect(merged[2].entries.first?.tmdbID == 3, "a series ranking does not replace a film list of the same name")
        #expect(merged[3].kind == .series)
    }
}

@Suite("Simkl custom lists")
struct SimklCustomListTests {
    private let listIndex = """
    {"pagination":{"page":1,"limit":50,"total_items":3,"total_pages":1},
     "lists":[{"id":11,"name":"Best 90s sci-fi","media_type":"movies","counts":{"items":3}},
              {"id":12,"name":"Comfort shows","media_type":"tv","counts":{"items":2}},
              {"id":13,"name":"Empty","media_type":"movies","counts":{"items":0}}]}
    """

    private func router(plan: String = "pro", premiumOnly: Bool = false) -> Router {
        Router { path, _ in
            if path == "/users/settings" {
                return (200, #"{"account":{"id":7,"type":"\#(plan)"}}"#)
            }
            if premiumOnly {
                return (200, #"{"error":"premium_only","message":"x","item":{"title":"Upgrade"}}"#)
            }
            return path == "/lists/user/7" ? (200, listIndex) : (200, "{}")
        }
    }

    @Test
    func `a free account is told apart by its plan, at the cost of one request`() async throws {
        let transport = router(plan: "free")

        let result = try await SimklAccountLists.custom(client: client(transport))

        #expect(result.plan == .free && result.lists.isEmpty)
        #expect(transport.paths == ["/users/settings"])
    }

    @Test
    func `a placeholder in place of lists is read as a free account`() async throws {
        let transport = router(plan: "pro", premiumOnly: true)

        let result = try await SimklAccountLists.custom(client: client(transport))

        #expect(result.plan == .free && result.lists.isEmpty)
    }

    @Test
    func `a PRO account's lists become lists of their own, named, with their items in order`() async throws {
        let sample = Router { path, _ in
            switch path {
            case "/users/settings": (200, #"{"account":{"id":7,"type":"vip"}}"#)
            case "/lists/user/7": (200, listIndex)
            case "/lists/11":
                (
                    200,
                    #"{"items":[{"title":"A","type":"movie","ids":{"tmdb":"21"}},{"title":"B","type":"movie","ids":{"tmdb":"22"}},"# +
                        #"{"title":"Anime","type":"anime","ids":{"tmdb":"23"}}]}"#
                )
            case "/lists/12": (200, #"{"items":[{"title":"S","type":"tv","ids":{"tmdb":"31"}}]}"#)
            default: (404, "")
            }
        }

        let result = try await SimklAccountLists.custom(client: client(sample))

        #expect(result.plan == .vip)
        #expect(result.lists.map(\.id) == ["custom.11", "custom.12"], "the empty list is not asked for")
        #expect(result.lists.map(\.title) == ["Best 90s sci-fi", "Comfort shows"])
        #expect(result.lists[0].kind == .movie && result.lists[1].kind == .series)
        #expect(result.lists[0].entries.map(\.tmdbID) == [21, 22], "anime is left out, the order is the owner's")
        let highlighted = result.lists.allSatisfy(\.isHighlight)
        #expect(highlighted)
        #expect(!sample.paths.contains("/lists/13"))
    }

    @Test
    func `a list that cannot be read is left out and the others stay`() async throws {
        let sample = Router { path, _ in
            switch path {
            case "/users/settings": (200, #"{"account":{"id":7,"type":"pro"}}"#)
            case "/lists/user/7": (200, listIndex)
            case "/lists/12": (200, #"{"items":[{"title":"S","type":"tv","ids":{"tmdb":"31"}}]}"#)
            default: (500, "")
            }
        }

        let result = try await SimklAccountLists.custom(client: client(sample))

        #expect(result.lists.map(\.id) == ["custom.12"])
    }
}
