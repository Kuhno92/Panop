import Foundation
@testable import Panop
import PanopCore
import PanopDiscover
import PanopSimkl
import Testing

private func rows(_ ids: ClosedRange<Int>) -> String {
    "[" + ids.map { #"{"title":"T\#($0)","ids":{"tmdb":"\#($0)"},"type":"movie"}"# }.joined(separator: ",") + "]"
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}

@Suite("Simkl account lists", .serialized, .engineGate)
@MainActor
struct SimklAccountListsStoreTests {
    private let listIndex = #"{"lists":[{"id":11,"name":"Mine","media_type":"movies","counts":{"items":2}}]}"#

    private func client(plan: String = "pro", status: Int = 200, requests: Counter = Counter()) -> SimklClient {
        let transport = StubTransport { request in
            requests.next()
            let path = request.url.path
            if status != 200 {
                return (status, "{}")
            }
            switch path {
            case "/users/settings": return (200, #"{"account":{"id":7,"type":"\#(plan)"}}"#)
            case "/lists/user/7": return (200, listIndex)
            case "/lists/11": return (
                    200,
                    #"{"items":[{"title":"A","type":"movie","ids":{"tmdb":"21"}},{"title":"B","type":"movie","ids":{"tmdb":"22"}}]}"#
                )
            default: return (200, rows(1 ... 5))
            }
        }
        return SimklClient(transport: transport, app: SimklApp(clientID: "id", version: "test")) { "TOKEN" }
    }

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/account-lists.json")
    }

    @Test
    func `a first refresh fetches the rankings and the person's lists and keeps them`() async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = SimklAccountListsStore(cacheURL: location)

        let fresh = try #require(await store.refresh(client: client(), wantsRanked: true, wantsCustom: true))

        #expect(!fresh.ranked.isEmpty)
        #expect(fresh.custom.map(\.id) == ["custom.11"])
        #expect(fresh.plan == .pro)
        #expect(await SimklAccountListsStore(cacheURL: location).cached() == fresh)
    }

    @Test
    func `nothing is fetched again until each part is out of date, the rankings daily and the lists sooner`(
    ) async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let requests = Counter()
        let store = SimklAccountListsStore(cacheURL: location)
        let start = Date.now
        _ = try await store.refresh(
            client: client(requests: requests),
            wantsRanked: true,
            wantsCustom: true,
            now: start
        )
        let afterFirst = requests.value

        let soon = try await store.refresh(
            client: client(requests: requests), wantsRanked: true, wantsCustom: true,
            now: start.addingTimeInterval(3600)
        )
        #expect(soon == nil)
        #expect(requests.value == afterFirst, "an hour later: no request")

        let sevenHours = try #require(try await store.refresh(
            client: client(requests: requests), wantsRanked: true, wantsCustom: true,
            now: start.addingTimeInterval(7 * 3600)
        ))
        #expect(sevenHours.rankedAt == start, "the lists are older than six hours, the rankings are not")
        #expect(requests.value - afterFirst <= 3, "only the account, its lists and their items")

        let nextDay = try await store.refresh(
            client: client(requests: requests), wantsRanked: true, wantsCustom: true,
            now: start.addingTimeInterval(25 * 3600)
        )
        #expect(nextDay?.rankedAt != nil && nextDay?.rankedAt != start)
    }

    @Test
    func `only what is wanted is fetched`() async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let requests = Counter()

        let snapshot = try #require(await SimklAccountListsStore(cacheURL: location)
            .refresh(client: client(requests: requests), wantsRanked: false, wantsCustom: true))

        #expect(snapshot.ranked.isEmpty && snapshot.rankedAt == nil)
        #expect(snapshot.custom.count == 1)
    }

    @Test
    func `a free account has no lists of its own, and the store knows its plan`() async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }

        let snapshot = try #require(await SimklAccountListsStore(cacheURL: location)
            .refresh(client: client(plan: "free"), wantsRanked: false, wantsCustom: true))

        #expect(snapshot.plan == .free && snapshot.custom.isEmpty)
    }

    @Test
    func `a refused login is passed on and nothing is kept`() async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = SimklAccountListsStore(cacheURL: location)

        await #expect(throws: SimklError.unauthorized) {
            try await store.refresh(client: client(status: 401), wantsRanked: true, wantsCustom: false)
        }
        #expect(await store.cached() == nil)
    }

    @Test
    func `clearing forgets them`() async throws {
        let location = url()
        defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = SimklAccountListsStore(cacheURL: location)
        _ = try await store.refresh(client: client(), wantsRanked: true, wantsCustom: true)

        await store.clear()

        #expect(await store.cached() == nil)
    }
}

@Suite("Account lists in the rails", .serialized, .engineGate)
@MainActor
struct AccountListsInTheRailsTests {
    @Test
    func `the person's lists are highlighted for Home, and the rankings take the place of the lists from the files`(
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let trending = directory.appendingPathComponent("trending.json")
        let account = directory.appendingPathComponent("account-lists.json")
        func list(
            _ id: String,
            _ kind: MediaKind,
            highlight: Bool = false,
            title: String? = nil,
            _ tmdb: Int
        ) -> CuratedList {
            CuratedList(
                id: id, kind: kind, isHighlight: highlight, title: title,
                entries: [TrendingEntry(kind: kind, tmdbID: tmdb, score: 1)]
            )
        }
        try JSONEncoder().encode(TrendingSnapshot(
            fetchedAt: .now, entries: [], lists: [
                list("network.Netflix", .series, highlight: true, 1),
                list("topRated", .movie, 2)
            ]
        )).write(to: trending)
        try JSONEncoder().encode(AccountListsSnapshot(
            rankedAt: .now, customAt: .now, plan: .pro,
            ranked: [list("network.Netflix", .series, highlight: true, 99)],
            custom: [list("custom.11", .movie, highlight: true, title: "Mine", 5)]
        )).write(to: account)
        let model = DiscoveryModel()
        model.accountCacheURL = account
        let source = SimklTrendingSource(
            transport: StubTransport { _ in (200, "[]") },
            app: SimklApp(clientID: "i", version: "t")
        )
        await model.loadTrending(enabled: true, source: source, cacheURL: trending)
        let client = SimklClient(
            transport: StubTransport { _ in (200, "{}") },
            app: SimklApp(clientID: "i", version: "t")
        ) { "T" }

        try await model.refreshAccountLists(client: client, wantsRanked: true, wantsCustom: true)

        #expect(model.highlighted == ["curated.series.network.Netflix", "curated.movie.custom.11"])
        #expect(model.simklPlan == .pro)

        await model.clearAccountLists()
        #expect(model.highlighted == ["curated.series.network.Netflix"], "the person's lists go with the account")
        #expect(model.simklPlan == nil)
    }

    @Test
    func `the switches decide which of the account's lists are used`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let account = directory.appendingPathComponent("account-lists.json")
        let custom = CuratedList(
            id: "custom.1", kind: .movie, isHighlight: true, title: "Mine",
            entries: [TrendingEntry(kind: .movie, tmdbID: 1, score: 1)]
        )
        try JSONEncoder().encode(AccountListsSnapshot(rankedAt: .now, customAt: .now, plan: .vip, custom: [custom]))
            .write(to: account)
        let model = DiscoveryModel()
        model.accountCacheURL = account
        let client = SimklClient(
            transport: StubTransport { _ in (200, "{}") },
            app: SimklApp(clientID: "i", version: "t")
        ) { "T" }

        try await model.refreshAccountLists(client: client, wantsRanked: true, wantsCustom: false)
        #expect(model.highlighted.isEmpty, "their own lists are switched off")

        try await model.refreshAccountLists(client: client, wantsRanked: true, wantsCustom: true)
        #expect(model.highlighted == ["curated.movie.custom.1"])
    }
}
