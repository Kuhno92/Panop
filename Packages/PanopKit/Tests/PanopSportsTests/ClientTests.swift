import Foundation
import PanopCore
@testable import PanopSports
import Testing

private final class Echo: HTTPTransport, @unchecked Sendable {
    var status: Int
    var body: String
    var headers: [String: String]
    var failure: (any Error)?
    private let lock = NSLock()
    private var seen: [HTTPRequest] = []

    init(status: Int = 200, body: String = "{}", headers: [String: String] = [:], failure: (any Error)? = nil) {
        self.status = status
        self.body = body
        self.headers = headers
        self.failure = failure
    }

    var requests: [HTTPRequest] {
        lock.withLock { seen }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { seen.append(request) }
        if let failure {
            throw failure
        }
        return HTTPResponse(statusCode: status, body: Data(body.utf8), headers: headers)
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

private let quotaHeaders = [
    "x-ratelimit-limit": "2000", "x-ratelimit-remaining": "1975", "x-ratelimit-reset": "1792022400"
]

@Suite("sportapi.ai client")
struct ClientTests {
    private func client(_ transport: Echo, key: String? = "sk_secret_key") -> SportsClient {
        SportsClient(transport: transport) { key }
    }

    @Test
    func `the key goes in the header, and not in the address`() async throws {
        let transport = Echo(body: SampleReplies.day, headers: quotaHeaders)
        _ = try await client(transport).fixtures(on: "2026-10-14")
        let request = try #require(transport.requests.first)
        #expect(request.headers["X-Api-Key"] == "sk_secret_key")
        #expect(request.url.absoluteString == "https://sportapi.ai/api/fixtures/date/2026-10-14")
        #expect(!request.url.absoluteString.contains("sk_secret_key"))
    }

    @Test
    func `what the service says about the day's budget comes back with every reply`() async throws {
        let transport = Echo(body: SampleReplies.day, headers: quotaHeaders)
        let reply = try await client(transport).fixtures(on: "2026-10-14")
        #expect(reply.value.count == 4)
        let quota = try #require(reply.quota)
        #expect(quota.limit == 2000 && quota.remaining == 1975 && quota.used == 25)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_792_022_400))
        #expect(!quota.isReserved)
    }

    @Test
    func `a reply without budget headers has no quota, which is not an error`() async throws {
        let reply = try await client(Echo(body: SampleReplies.day)).fixtures(on: "2026-10-14")
        #expect(reply.quota == nil)
    }

    @Test
    func `with no key nothing is sent`() async {
        let transport = Echo()
        for key in [nil, "", "   "] as [String?] {
            await #expect(throws: SportsError.unauthorized) { try await client(transport, key: key).leagues() }
        }
        #expect(transport.requests.isEmpty)
    }

    @Test
    func `a refused key is unauthorized`() async {
        for status in [401, 403] {
            await #expect(throws: SportsError.unauthorized) {
                try await client(Echo(status: status)).validate()
            }
        }
    }

    @Test
    func `the daily limit says when it ends`() async {
        let transport = Echo(status: 429, headers: ["x-ratelimit-limit": "2000", "x-ratelimit-remaining": "0",
                                                    "x-ratelimit-reset": "1792022400"])
        await #expect(throws: SportsError.dailyLimit(resetsAt: Date(timeIntervalSince1970: 1_792_022_400))) {
            try await client(transport).fixtures(on: "2026-10-14")
        }
        await #expect(throws: SportsError.dailyLimit(resetsAt: nil)) {
            try await client(Echo(status: 429)).fixtures(on: "2026-10-14")
        }
    }

    @Test
    func `other statuses and unreadable replies are told apart`() async {
        await #expect(throws: SportsError.status(500)) { try await client(Echo(status: 500)).leagues() }
        await #expect(throws: SportsError.undecodable) { try await client(Echo(body: "<html>")).leagues() }
        await #expect(throws: SportsError.undecodable) { try await client(Echo(body: "{}")).fixture(id: 1) }
    }

    @Test
    func `a network failure says nothing about the address or the key`() async {
        struct Failing: Error, CustomStringConvertible {
            var description: String {
                "could not connect to https://sportapi.ai/api/leagues with X-Api-Key sk_secret_key"
            }
        }
        let transport = Echo(failure: Failing())
        do {
            _ = try await client(transport).leagues()
            Issue.record("it should have thrown")
        } catch {
            let text = "\(error) \(String(describing: error)) \(error.localizedDescription)"
            #expect(error as? SportsError == .network)
            #expect(!text.contains("sk_secret_key") && !text.contains("sportapi.ai"))
        }
    }

    @Test
    func `errors carry no key and no address`() {
        let errors: [SportsError] = [.unauthorized, .dailyLimit(resetsAt: nil), .status(500), .undecodable, .network]
        for error in errors {
            #expect(!"\(error)".contains("sk_secret_key") && !"\(error)".contains("http"))
        }
    }

    @Test
    func `lineups and statistics that are not there come back as nil`() async throws {
        let none = try await client(Echo(body: SampleReplies.noLineups)).lineups(fixture: 5)
        #expect(none.value == nil)
        let some = try await client(Echo(body: SampleReplies.lineups)).lineups(fixture: 101)
        #expect(some.value?.home.formation == "4-3-3")
        let stats = try await client(Echo(body: SampleReplies.stats)).stats(fixture: 101)
        #expect(stats.value?.home.shots == 20 && stats.value?.away.shots == 25)
        #expect(stats.value?.away.passes == nil)
    }

    @Test
    func `a table comes back ordered by position, and a cup's is empty`() async throws {
        let table = try await client(Echo(body: SampleReplies.standings)).standings(league: 53)
        #expect(table.value.map(\.position) == [1, 2])
        let cup = try await client(Echo(body: "{\"success\": true, \"data\": []}")).standings(league: 123)
        #expect(cup.value.isEmpty)
    }

    @Test
    func `each call asks for the right address`() async throws {
        let transport = Echo(body: "{\"success\": true, \"data\": []}")
        let api = client(transport)
        _ = try await api.leagues()
        _ = try await api.standings(league: 53)
        _ = try await api.events(fixture: 9)
        _ = try await api.lineups(fixture: 9)
        _ = try await api.stats(fixture: 9)
        _ = try await api.validate()
        #expect(transport.requests.map(\.url.path) == [
            "/api/leagues", "/api/standings/53", "/api/fixtures/9/events", "/api/fixtures/9/lineups",
            "/api/fixtures/9/stats", "/api/standings/leagues"
        ])
    }
}

@Suite("sportapi.ai budget")
struct QuotaTests {
    private func quota(remaining: Int) -> SportsQuota {
        SportsQuota(limit: 2000, remaining: remaining, resetsAt: Date(timeIntervalSince1970: 0))
    }

    @Test
    func `a live screen refreshes every minute, and slows down as the day's budget goes`() {
        #expect(quota(remaining: 1900).refreshInterval(isLive: true) == 60)
        #expect(quota(remaining: 380).refreshInterval(isLive: true) == 180)
        #expect(quota(remaining: 1900).refreshInterval(isLive: false) == 600)
    }

    @Test
    func `the last five percent is kept for what the person asks for`() {
        #expect(!quota(remaining: 101).isReserved)
        #expect(quota(remaining: 100).isReserved)
        #expect(quota(remaining: 100).refreshInterval(isLive: true) == .infinity)
        #expect(quota(remaining: 0).fractionUsed == 1)
    }

    @Test
    func `headers that are not numbers give no quota`() {
        #expect(SportsQuota(headers: ["x-ratelimit-limit": "many"]) == nil)
        #expect(SportsQuota(headers: [:]) == nil)
    }
}
