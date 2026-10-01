import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("M3U channel order")
struct ChannelOrderTests {
    private func playlist(_ names: [String]) -> String {
        "#EXTM3U\n" + names.enumerated().map { index, name in
            "#EXTINF:-1,\(name)\nhttp://h/live/\(index)-\(name.replacingOccurrences(of: " ", with: "")).ts"
        }.joined(separator: "\n") + "\n"
    }

    private func importer(_ store: InMemoryCatalogStore) -> CatalogImporter {
        CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
    }

    private func order(_ store: InMemoryCatalogStore) async -> [String] {
        await store.allEntries(playlist: "p")
            .sorted { ($0.sortNumber ?? .max) < ($1.sortNumber ?? .max) }
            .map(\.name)
    }

    @Test
    func `channels keep the order the provider listed them in, not alphabetical`() async throws {
        let store = InMemoryCatalogStore()
        let file = try writeTemporaryFile(playlist(["Zebra TV", "Alpha TV", "Mango TV", "Beta TV"]))

        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: file))

        #expect(await order(store) == ["Zebra TV", "Alpha TV", "Mango TV", "Beta TV"])
        let numbers = await store.allEntries(playlist: "p").compactMap(\.sortNumber).sorted()
        #expect(numbers == [1, 2, 3, 4])
    }

    @Test
    func `the position counts across kinds, in file order`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,Live One
        http://h/live/1.ts
        #EXTINF:5400,A Film
        http://h/movie/u/p/2.mp4
        #EXTINF:-1,Live Two
        http://h/live/3.ts
        """
        let file = try writeTemporaryFile(text)

        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: file))

        let byName = await Dictionary(
            uniqueKeysWithValues: store.allEntries(playlist: "p").map { ($0.name, $0.sortNumber) }
        )
        #expect(byName["Live One"] == 1)
        #expect(byName["A Film"] == 2)
        #expect(byName["Live Two"] == 3)
    }

    @Test
    func `a provider that reorders its list is followed on the next import`() async throws {
        let store = InMemoryCatalogStore()
        let first = try writeTemporaryFile(playlist(["One", "Two", "Three"]))
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: first))
        #expect(await order(store) == ["One", "Two", "Three"])

        // The same channels at the same addresses, in a new order.
        let reordered = "#EXTM3U\n#EXTINF:-1,Three\nhttp://h/live/2-Three.ts\n#EXTINF:-1,One\nhttp://h/live/0-One.ts\n#EXTINF:-1,Two\nhttp://h/live/1-Two.ts\n"
        let second = try writeTemporaryFile(reordered)
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: second))

        #expect(await order(store) == ["Three", "One", "Two"])
        #expect(await store.allEntries(playlist: "p").count == 3, "reordering must not duplicate anything")
    }

    @Test
    func `an unchanged file changes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let file = try writeTemporaryFile(playlist(["B", "A"]))
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: file))

        let again = try await importer(store).importM3U(playlist: "p", source: .file(path: file))

        #expect(again.outcome == .unchanged)
        #expect(await order(store) == ["B", "A"])
    }

    @Test
    func `skipped entries do not take a position`() async throws {
        let store = InMemoryCatalogStore()
        let text = "#EXTM3U\n#EXTINF:-1,Good One\nhttp://h/live/1.ts\n#EXTINF:-1,Broken\n/relative.ts\n#EXTINF:-1,Good Two\nhttp://h/live/2.ts\n"
        let file = try writeTemporaryFile(text)

        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: file))

        #expect(await order(store) == ["Good One", "Good Two"])
        let numbers = await store.allEntries(playlist: "p").compactMap(\.sortNumber).sorted()
        #expect(numbers == [1, 2], "no gap where the unusable entry was")
    }
}
