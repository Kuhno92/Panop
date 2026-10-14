import Foundation
@testable import Panop
import PanopCore
import PanopSports
import SwiftData
import Testing

/// Answers like the service: a body, a status, the budget in the headers. Counts what was asked.
private final class FakeService: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HTTPRequest] = []
    var status = 200
    var body = "{\"success\": true, \"data\": []}"
    var remaining = 1990
    var delay: Duration = .zero
    var failure: (any Error)?

    var requests: [HTTPRequest] {
        lock.withLock { seen }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { seen.append(request) }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let failure {
            throw failure
        }
        return HTTPResponse(statusCode: status, body: Data(body.utf8), headers: [
            "x-ratelimit-limit": "2000", "x-ratelimit-remaining": String(remaining),
            "x-ratelimit-reset": "1792022400"
        ])
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStreamResponse {
        let response = try await send(request)
        return HTTPStreamResponse(statusCode: response.statusCode, chunks: HTTPChunks([response.body]))
    }
}

private let day = """
{"success": true, "data": [{"id": 1, "kickoff_utc": "2026-10-14T18:45:00Z", "status": "LIVE", "minute": "10'",
 "league_id": 53, "league_name": "Second Division", "home_team": "A", "away_team": "B", "home_score": 0, "away_score": 0}]}
"""

private let leagueList = """
{"success": true, "data": [{"country": "England", "leagues": [{"id": 53, "name": "Second Division"}]}]}
"""

@MainActor
private struct Harness {
    let service = FakeService()
    let keys: InMemorySportsKeyStore
    let sync: SportsSyncStore
    let account: SportsAccount
    let cache: SportsCacheStore
    let feed: SportsFeed
    let directory: URL
    let clock: Clock
    let defaults: UserDefaults

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_792_000_000)

        var now: Date {
            lock.withLock { value }
        }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { value = value.addingTimeInterval(seconds) }
        }
    }

    init(
        key: String? = "sk_test_key_abcd",
        sync existing: SportsSyncStore? = nil,
        keys existingKeys: InMemorySportsKeyStore? = nil
    ) throws {
        keys = existingKeys ?? InMemorySportsKeyStore(key)
        sync = try existing ?? SportsSyncStore(context: ModelContext(PanopContainers.makeCloud(inMemory: true)))
        clock = Clock()
        let suite = "sports-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sports-\(UUID().uuidString)")
        let clock = clock
        account = SportsAccount(
            keyStore: keys, sync: sync, transport: service, memory: SportsKeyMemory(defaults: defaults),
            now: { clock.now }
        )
        cache = SportsCacheStore(directory: directory, now: { clock.now })
        feed = SportsFeed(account: account, cache: cache, now: { clock.now })
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
@Suite("Sports feed: what is asked, and what is not")
struct SportsFeedTests {
    @Test
    func `the first ask goes to the service and what comes back is kept`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        let result = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(result.value?.count == 1 && result.isFresh && result.error == nil)
        #expect(env.service.requests.count == 1)
        #expect(env.service.requests.first?.headers["X-Api-Key"] == "sk_test_key_abcd")
        // The budget the service reported is what the account knows.
        #expect(env.account.quota?.remaining == 1990)
        #expect(await env.cache.read("fixtures-2026-10-14") != nil)
    }

    @Test
    func `an answer that is fresh enough is not asked for again`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        env.clock.advance(300)
        let again = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(again.value?.count == 1 && again.isFresh)
        #expect(env.service.requests.count == 1)
        env.clock.advance(400)
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(env.service.requests.count == 2)
    }

    @Test
    func `pulling to refresh asks even when the answer is fresh`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600, force: true)
        #expect(env.service.requests.count == 2)
    }

    @Test
    func `a screen that must not spend the budget reads only what is kept`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        let nothing = await env.feed.fixtures(day: "2026-10-14", maxAge: 0)
        #expect(nothing.value == nil && env.service.requests.isEmpty)
        env.service.body = day
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        env.clock.advance(5000)
        let kept = await env.feed.fixtures(day: "2026-10-14", maxAge: 0)
        #expect(kept.value?.count == 1 && kept.isStale)
        #expect(env.service.requests.count == 1)
    }

    @Test
    func `when the service cannot be reached the last answer is still shown, marked old`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        env.clock.advance(900)
        env.service.failure = URLError(.notConnectedToInternet)
        let result = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(result.value?.count == 1)
        #expect(result.isStale && result.error == .network)
        // An outage is not a refused key: nothing about the account changes.
        #expect(env.account.state == .ready)
    }

    @Test
    func `without a key nothing is asked`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        let result = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(result.value == nil && result.error == .unauthorized)
        #expect(env.service.requests.isEmpty)
    }

    @Test
    func `a key the service refuses stops the asking until it is replaced`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.status = 401
        let first = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(first.error == .unauthorized && env.account.state == .invalid)
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600, force: true)
        #expect(env.service.requests.count == 1)
    }

    @Test
    func `a spent day stops the asking until the reset, then it goes on`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.status = 429
        let limited = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        guard case .dailyLimit = limited.error else {
            Issue.record("expected the daily limit, got \(String(describing: limited.error))")
            return
        }
        guard case .limitReached = env.account.state else {
            Issue.record("expected limitReached, got \(env.account.state)")
            return
        }
        env.clock.advance(60)
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600, force: true)
        #expect(env.service.requests.count == 1, "no request while the day is spent")
        // After the reset (the headers said 1792022400).
        env.clock.advance(30000)
        #expect(env.account.effectiveState == .ready)
        env.service.status = 200
        env.service.body = day
        let after = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(after.value?.count == 1)
    }

    @Test
    func `the last of the day's requests are kept for what the person asks for`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        env.service.remaining = 60
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(env.account.quota?.isReserved == true)
        env.clock.advance(1000)
        let background = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        #expect(background.isStale && env.service.requests.count == 1)
        let asked = await env.feed.fixtures(day: "2026-10-14", maxAge: 600, force: true)
        #expect(asked.isFresh && env.service.requests.count == 2)
    }

    @Test
    func `three screens asking for the same thing make one request`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        env.service.delay = .milliseconds(80)
        async let first = env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        async let second = env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        async let third = env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        let results = await [first, second, third]
        #expect(results.allSatisfy { $0.value?.count == 1 })
        #expect(env.service.requests.count == 1)
    }

    @Test
    func `leagues are kept for two weeks`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = leagueList
        _ = await env.feed.leagues()
        env.clock.advance(13 * 24 * 3600)
        let kept = await env.feed.leagues()
        #expect(kept.isFresh && kept.value?.first?.country == "England" && env.service.requests.count == 1)
        env.clock.advance(2 * 24 * 3600)
        _ = await env.feed.leagues()
        #expect(env.service.requests.count == 2)
    }

    @Test
    func `taking the key out takes what was fetched with it`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        env.service.body = day
        _ = await env.feed.fixtures(day: "2026-10-14", maxAge: 600)
        await env.feed.clear()
        #expect(await env.cache.read("fixtures-2026-10-14") == nil)
    }

    @Test
    func `a cache entry written long ago is pruned, a recent one stays`() async throws {
        let env = try Harness()
        defer { env.cleanUp() }
        await env.cache.write("old", data: Data("x".utf8))
        env.clock.advance(8 * 24 * 3600)
        await env.cache.write("recent", data: Data("y".utf8))
        await env.feed.prune()
        #expect(await env.cache.read("old") == nil)
        #expect(await env.cache.read("recent") != nil)
    }
}

@MainActor
@Suite("Sports account: the key, here and in iCloud")
struct SportsAccountTests {
    @Test
    func `a key the service accepts is kept, and a key it refuses is not`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        env.service.status = 401
        #expect(await env.account.setKey("sk_bad") == .rejected)
        #expect(env.keys.load() == nil && env.account.state == .noKey)
        env.service.status = 200
        #expect(await env.account.setKey("  sk_good_key  \n") == .accepted)
        #expect(env.keys.load() == "sk_good_key" && env.account.state == .ready)
        #expect(env.account.maskedKey == "••••_key")
        #expect(env.account.quota?.limit == 2000)
    }

    @Test
    func `a key cannot be checked when the service cannot be reached, and is not kept either`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        env.service.failure = URLError(.notConnectedToInternet)
        #expect(await env.account.setKey("sk_good_key") == .unreachable)
        #expect(env.keys.load() == nil && env.account.state == .noKey)
    }

    @Test
    func `a key entered while the day is spent is still a good key`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        env.service.status = 429
        #expect(await env.account.setKey("sk_good_key") == .accepted)
        #expect(env.keys.load() == "sk_good_key")
        guard case .limitReached = env.account.state else {
            Issue.record("expected limitReached")
            return
        }
    }

    @Test
    func `a key that is accepted goes to the record, so another device has it`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        #expect(await env.account.setKey("sk_good_key") == .accepted)
        #expect(env.sync.keyRecord.blob == SportsKeySync.encode("sk_good_key"))
    }

    @Test
    func `a key that arrives from another device is taken, and works at once`() async throws {
        let first = try Harness(key: nil)
        defer { first.cleanUp() }
        _ = await first.account.setKey("sk_good_key")
        // A second device has the same record (the same cloud store here) and no key.
        let second = try Harness(key: nil, sync: first.sync)
        defer { second.cleanUp() }
        second.account.reconcile()
        #expect(second.keys.load() == "sk_good_key" && second.account.state == .ready)
    }

    @Test
    func `taking the key out here takes it out of the other device`() async throws {
        let first = try Harness(key: nil)
        defer { first.cleanUp() }
        _ = await first.account.setKey("sk_good_key")
        let second = try Harness(key: nil, sync: first.sync)
        defer { second.cleanUp() }
        second.account.reconcile()
        #expect(second.keys.load() != nil)

        first.account.removeKey()
        #expect(first.keys.load() == nil && first.account.state == .noKey)
        #expect(first.sync.keyRecord.blob == nil && first.sync.keyRecord.removed)
        // Not read as a key that has not arrived: the other device lets go of it.
        second.account.reconcile()
        #expect(second.keys.load() == nil && second.account.state == .noKey)
    }

    @Test
    func `a key typed in again after it was taken out goes to the record and the other device takes it`() async throws {
        let first = try Harness(key: nil)
        defer { first.cleanUp() }
        _ = await first.account.setKey("sk_good_key")
        let second = try Harness(key: nil, sync: first.sync)
        defer { second.cleanUp() }
        second.account.reconcile()
        first.account.removeKey()
        second.account.reconcile()
        #expect(await first.account.setKey("sk_new_key") == .accepted)
        second.account.reconcile()
        #expect(second.keys.load() == "sk_new_key")
    }

    @Test
    func `with the sync off the key stays on this device and is not on the record`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        env.account.syncsKey = { false }
        #expect(await env.account.setKey("sk_good_key") == .accepted)
        #expect(env.sync.keyRecord.blob == nil)
        #expect(env.keys.load() == "sk_good_key")
    }

    @Test
    func `turning the sync off empties the record`() async throws {
        let env = try Harness(key: nil)
        defer { env.cleanUp() }
        _ = await env.account.setKey("sk_good_key")
        #expect(env.sync.keyRecord.blob != nil)
        env.account.syncsKey = { false }
        env.account.reconcile()
        #expect(env.sync.keyRecord.blob == nil && env.keys.load() == "sk_good_key")
    }

    @Test
    func `removing the key tells what was fetched with it to go`() throws {
        let env = try Harness()
        defer { env.cleanUp() }
        var told = false
        env.account.onKeyRemoved = { told = true }
        env.account.removeKey()
        #expect(told)
    }
}
