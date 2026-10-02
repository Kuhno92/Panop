import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Category browse query", .serialized)
@MainActor
struct CategoryQueryTests {
    private func entry(_ id: String, _ name: String, group: String?, kind: MediaKind = .live, sort: Int? = nil)
        -> CatalogEntry
    {
        CatalogEntry(id: id, kind: kind, name: name, groupID: group, groupName: group, sortNumber: sort)
    }

    private func populate(_ catalog: OnDiskCatalog) async throws {
        _ = try await catalog.store.upsertEntries([
            entry("a1", "Alpha", group: "News", sort: 3),
            entry("a2", "Bravo", group: "News", sort: 1),
            entry("a3", "Charlie", group: "Sport", sort: 2),
            entry("a4", "Delta", group: nil),
            entry("m1", "A Film", group: "News", kind: .movie)
        ], playlist: "p")
        _ = try await catalog.store.upsertEntries([
            entry("b1", "Echo", group: "News")
        ], playlist: "q")
        try await catalog.store.upsertCategories([
            CatalogCategory(id: "News", kind: .live, name: "News"),
            CatalogCategory(id: "Sport", kind: .live, name: "Sport"),
            CatalogCategory(id: "Films", kind: .movie, name: "Films")
        ], playlist: "p")
        try await catalog.store.upsertCategories([
            CatalogCategory(id: "n", kind: .live, name: "News"),
            CatalogCategory(id: "w", kind: .live, name: "Weather")
        ], playlist: "q")
    }

    private func names(
        _ catalog: OnDiskCatalog,
        kind: MediaKind = .live,
        source: String? = nil,
        search: String = "",
        order: LiveOrder = .name,
        group: String?
    ) throws -> [String] {
        try ModelContext(catalog.container).fetch(LiveChannelQuery.descriptor(
            kind: kind,
            source: source,
            search: search,
            limit: 100,
            order: order,
            group: group
        )).map(\.name)
    }

    @Test
    func `a category lists only its own channels, of that kind, from every source`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        #expect(try names(catalog, group: "News") == ["Alpha", "Bravo", "Echo"], "the film in News is a movie")
        #expect(try names(catalog, group: "Sport") == ["Charlie"])
        #expect(try names(catalog, group: "Nothing").isEmpty)
    }

    @Test
    func `it narrows by source and search together with the category`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        #expect(try names(catalog, source: "q", group: "News") == ["Echo"])
        #expect(try names(catalog, search: "br", group: "News") == ["Bravo"])
        #expect(try names(catalog, source: "p", search: "o", group: "News") == ["Bravo"])
    }

    @Test
    func `the provider's order applies inside a category`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        #expect(try names(catalog, source: "p", order: .provider, group: "News") == ["Bravo", "Alpha"])
    }

    @Test
    func `a series category lists shows, not the episodes grouped under them`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([
            CatalogEntry(id: "s:dark", kind: .series, name: "Dark", groupName: "Drama"),
            CatalogEntry(
                id: "e1", kind: .series, name: "Dark S01E01", groupName: "Drama", streamURL: "http://h/e1.mkv",
                seriesID: "s:dark", seasonNumber: 1, episodeNumber: 1
            )
        ], playlist: "p")

        #expect(try names(catalog, kind: .series, group: "Drama") == ["Dark"])
    }

    @Test
    func `category names are one choice each across sources, in name order`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)

        #expect(LiveChannelQuery.categoryNames(kind: .live, source: nil, in: context) == ["News", "Sport", "Weather"])
        #expect(LiveChannelQuery.categoryNames(kind: .live, source: "q", in: context) == ["News", "Weather"])
        #expect(LiveChannelQuery.categoryNames(kind: .movie, source: nil, in: context) == ["Films"])
    }
}
