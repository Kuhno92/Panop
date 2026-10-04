import Foundation
@testable import Panop
import PanopCore
import PanopDiscover
import PanopSimkl
import Testing

@MainActor
@Suite("Backdrops", .serialized)
struct BackdropTests {
    private func model(entries: [TrendingEntry]) async throws -> DiscoveryModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("trending.json")
        try JSONEncoder().encode(TrendingSnapshot(fetchedAt: .now, entries: entries, lists: [])).write(to: url)
        let model = DiscoveryModel()
        let source = SimklTrendingSource(
            transport: StubTransport { _ in (200, "[]") }, app: SimklApp(clientID: "id", version: "test")
        )
        await model.loadTrending(enabled: true, source: source, cacheURL: url)
        return model
    }

    @Test
    func `the provider's backdrop wins over Simkl's`() async throws {
        let model = try await model(entries: [TrendingEntry(kind: .series, tmdbID: 5, score: 1, fanart: "1/abc")])
        #expect(model.backdrop(kind: .series, tmdbID: 5, provider: "http://img/b.jpg") == "http://img/b.jpg")
    }

    @Test
    func `fanart from Simkl stands in where the provider has none`() async throws {
        let model = try await model(entries: [TrendingEntry(kind: .movie, tmdbID: 7, score: 1, fanart: "1/abc")])
        #expect(model.backdrop(kind: .movie, tmdbID: 7, provider: nil) == "https://simkl.in/fanart/1/abc_w.webp")
        #expect(model.backdrop(kind: .movie, tmdbID: 7, provider: "") == "https://simkl.in/fanart/1/abc_w.webp")
    }

    @Test
    func `a title nobody has artwork for gets none`() async throws {
        let model = try await model(entries: [TrendingEntry(kind: .movie, tmdbID: 7, score: 1)])
        #expect(model.backdrop(kind: .movie, tmdbID: 7, provider: nil) == nil)
        #expect(model.backdrop(kind: .movie, tmdbID: nil, provider: nil) == nil)
        #expect(model.backdrop(kind: .series, tmdbID: 7, provider: nil) == nil, "a film's id is not a series'")
    }
}
