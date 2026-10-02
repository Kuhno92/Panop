import Foundation
@testable import Panop
import PanopCore
import PanopDiscover
import PanopSimkl
import Testing

@Suite("Trending store", .serialized)
struct TrendingStoreTests {
    private func store(_ transport: StubTransport, cache: URL) -> TrendingStore {
        TrendingStore(source: SimklTrendingSource(transport: transport, userAgent: "Panop/test"), cacheURL: cache)
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
}
