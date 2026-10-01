import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("Grouping M3U episodes into series")
struct SeriesGroupingTests {
    private func episode(_ name: String, _ number: Int, icon: String? = nil) -> String {
        let logo = icon.map { " tvg-logo=\"\($0)\"" } ?? ""
        return "#EXTINF:2700\(logo) group-title=\"Shows\",\(name)\nhttp://h/series/u/p/\(number).mkv"
    }

    private func file(_ lines: [String]) throws -> String {
        try writeTemporaryFile("#EXTM3U\n" + lines.joined(separator: "\n") + "\n")
    }

    private func importer(_ store: InMemoryCatalogStore) -> CatalogImporter {
        CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
    }

    private func run(_ store: InMemoryCatalogStore, _ lines: [String]) async throws -> ImportReport {
        try await importer(store).importM3U(playlist: "p", source: .file(path: file(lines)))
    }

    private func entries(_ store: InMemoryCatalogStore) async -> [CatalogEntry] {
        await store.allEntries(playlist: "p")
    }

    @Test
    func `episodes are grouped under one series entry per show`() async throws {
        let store = InMemoryCatalogStore()

        _ = try await run(store, [
            episode("Dark S01E01", 1), episode("Dark S01E02", 2), episode("Dark S02E01", 3),
            episode("Severance S01E01", 4)
        ])

        let all = await entries(store)
        let shells = all.filter { $0.kind == .series && $0.seriesID == nil }
        let episodes = all.filter { $0.seriesID != nil }
        #expect(shells.map(\.name).sorted() == ["Dark", "Severance"])
        #expect(episodes.count == 4)
        let dark = try #require(shells.first { $0.name == "Dark" })
        #expect(episodes.filter { $0.seriesID == dark.id }.count == 3)
    }

    @Test
    func `an episode keeps its address and carries its season and episode`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await run(store, [episode("Dark S02E07", 9)])

        let episode = try #require(await entries(store).first { $0.seriesID != nil })

        #expect(episode.streamURL == "http://h/series/u/p/9.mkv")
        #expect(episode.seasonNumber == 2)
        #expect(episode.episodeNumber == 7)
        #expect(episode.name == "Dark S02E07")
    }

    @Test
    func `a series entry that is not an episode stays on its own`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await run(store, [
            "#EXTINF:2700,A Documentary\nhttp://h/series/u/p/1.mkv", episode("Dark S01E01", 2)
        ])

        let doc = try #require(await entries(store).first { $0.name == "A Documentary" })

        #expect(doc.seriesID == nil)
        #expect(doc.streamURL != nil, "it is still playable by itself")
    }

    @Test
    func `different spellings of a show are one series`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await run(store, [episode("Dark S01E01", 1), episode("DARK  s01e02", 2), episode("dark 1x03", 3)])

        let shells = await entries(store).filter { $0.kind == .series && $0.seriesID == nil }

        #expect(shells.count == 1)
    }

    @Test
    func `the series takes its first episode's logo and position`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await run(store, [
            episode("Zeta S01E01", 1, icon: "http://i/zeta.png"),
            episode("Dark S01E01", 2, icon: "http://i/dark.png"),
            episode("Zeta S01E02", 3, icon: "http://i/other.png")
        ])

        let zeta = try #require(await entries(store).first { $0.name == "Zeta" })
        let dark = try #require(await entries(store).first { $0.name == "Dark" })

        #expect(zeta.iconURL == "http://i/zeta.png")
        #expect(zeta.sortNumber == 1)
        #expect(dark.sortNumber == 2)
    }

    @Test
    func `importing again changes nothing, and a new episode joins its show`() async throws {
        let store = InMemoryCatalogStore()
        let lines = [episode("Dark S01E01", 1), episode("Dark S01E02", 2)]
        _ = try await run(store, lines)
        let first = await entries(store).count

        let again = try await run(store, lines)
        #expect(again.outcome == .unchanged)

        _ = try await run(store, lines + [episode("Dark S01E03", 3)])
        let after = await entries(store)
        #expect(first == 3, "two episodes and one series")
        #expect(after.count == 4, "one more episode, and no second series")
        #expect(after.filter { $0.kind == .series && $0.seriesID == nil }.count == 1)
    }

    @Test
    func `a show whose episodes all go from the list goes too`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await run(store, [episode("Dark S01E01", 1), episode("Severance S01E01", 2), episode("Lost S01E01", 3)])

        _ = try await run(store, [episode("Dark S01E01", 1), episode("Lost S01E01", 3)])

        let names = await entries(store).filter { $0.seriesID == nil }.map(\.name).sorted()
        #expect(names == ["Dark", "Lost"], "Severance and its only episode were removed")
    }

    @Test
    func `movies and channels are not touched`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,Das Erste
        http://h/live/1.ts
        #EXTINF:5400,Alien S01E01
        http://h/movie/u/p/2.mp4
        """
        let path = try writeTemporaryFile(text)

        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: path))

        #expect(await entries(store).allSatisfy { $0.seriesID == nil }, "only series entries are grouped")
        #expect(await entries(store).count == 2)
    }
}
