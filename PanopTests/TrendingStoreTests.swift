import Foundation
@testable import Panop
import PanopCore
import PanopDiscover
import PanopSimkl
import Testing

@Suite("Trending store", .serialized)
struct TrendingStoreTests {
    private func store(_ transport: StubTransport, cache: URL) -> TrendingStore {
        TrendingStore(
            source: SimklTrendingSource(transport: transport, app: SimklApp(clientID: "id", version: "test")),
            cacheURL: cache
        )
    }

    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("trending.json")
    }

    private let body = #"[{"title":"A","url":"/tv/1/a","ids":{"tmdb":"11"}},{"title":"B","ids":{"tmdb":12}}]"#

    @Test
    func `a first refresh fetches both lists and keeps them for the next launch`() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = StubTransport { _ in (200, body) }

        let fresh = try #require(await store(transport, cache: url).refreshIfStale())

        #expect(fresh.entries.count == 4, "two titles from each of the two lists")
        #expect(await store(transport, cache: url).cached() == fresh)
    }

    @Test
    func `lists that are still fresh are not fetched again`() async {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = StubTransport { _ in (200, body) }
        let first = store(transport, cache: url)
        _ = await first.refreshIfStale()

        #expect(await first.refreshIfStale(now: .now.addingTimeInterval(3600)) == nil)
        #expect(await first.refreshIfStale(now: .now.addingTimeInterval(TrendingStore.maxAge + 60)) != nil)
    }

    @Test
    func `a failed fetch leaves the saved lists as they were`() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let good = store(StubTransport { _ in (200, body) }, cache: url)
        let saved = try #require(await good.refreshIfStale())

        let down = store(StubTransport { _ in (503, "") }, cache: url)
        let result = await down.refreshIfStale(now: .now.addingTimeInterval(TrendingStore.maxAge + 60))

        #expect(result == nil)
        #expect(await down.cached() == saved)
    }

    @Test
    func `the lists come with the trending entries, from the same files`() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = StubTransport { _ in (200, body) }

        let fresh = try #require(await store(transport, cache: url).refreshIfStale())

        #expect(fresh.lists != nil)
        #expect(await store(transport, cache: url).cached()?.lists == fresh.lists)
    }

    @Test
    func `lists saved before there were lists make a snapshot out of date, so they are fetched`() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = #"{"fetchedAt":\#(Date.now.timeIntervalSinceReferenceDate),"entries":[]}"#
        try Data(old.utf8).write(to: url)
        let transport = StubTransport { _ in (200, body) }

        let refreshed = await store(transport, cache: url).refreshIfStale()

        #expect(refreshed != nil, "an hour-old snapshot with no lists is still fetched again")
        #expect(refreshed?.lists != nil)
    }
}

@Suite("Simkl lists on Home", .serialized, .engineGate)
@MainActor
struct SimklListsOnHomeTests {
    @Test
    func `only the highlighted lists are marked for Home`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let url = directory.appendingPathComponent("trending.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lists = [
            CuratedList(id: "boxOffice", kind: .movie, isHighlight: true, entries: []),
            CuratedList(id: "topRated", kind: .movie, entries: [])
        ]
        let snapshot = TrendingSnapshot(fetchedAt: .now, entries: [], lists: lists)
        try JSONEncoder().encode(snapshot).write(to: url)
        let model = DiscoveryModel()
        let source = SimklTrendingSource(
            transport: StubTransport { _ in (200, "[]") }, app: SimklApp(clientID: "id", version: "test")
        )

        await model.loadTrending(enabled: true, source: source, cacheURL: url)

        #expect(model.highlighted == ["curated.movie.boxOffice"])
    }
}
