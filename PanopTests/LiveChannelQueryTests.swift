import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

private func live(_ id: String, _ name: String, group: String? = nil) -> CatalogEntry {
    CatalogEntry(id: id, kind: .live, name: name, groupID: group, groupName: group)
}

@MainActor
private func fetch(
    _ catalog: OnDiskCatalog,
    source: String? = nil,
    search: String = "",
    limit: Int = 10000
) throws -> [CatalogEntryRecord] {
    try ModelContext(catalog.container).fetch(LiveChannelQuery.descriptor(source: source, search: search, limit: limit))
}

/// Two playlists whose channel names interleave, so any list that only reads one
/// of them, or reads them in insertion order, is caught.
private func populate(_ catalog: OnDiskCatalog, first: Int = 400, second: Int = 60) async throws {
    // "Channel 000" is in the first playlist, "Channel 001" in the second, and so
    // on for as long as the second lasts; then the first carries on alone.
    var firstRows: [CatalogEntry] = []
    var secondRows: [CatalogEntry] = []
    var index = 0
    var placedB = 0
    while firstRows.count < first || placedB < second {
        let name = String(format: "Channel %03d", index)
        if index % 2 == 1, placedB < second {
            secondRows.append(live("b:\(index)", name))
            placedB += 1
        } else if firstRows.count < first {
            firstRows.append(live("a:\(index)", name))
        }
        index += 1
    }
    _ = try await catalog.store.upsertEntries(firstRows, playlist: "a")
    _ = try await catalog.store.upsertEntries(secondRows, playlist: "b")
}

@Suite("Live channel query", .serialized)
@MainActor
struct LiveChannelQueryTests {
    // MARK: - The reported bug

    /// A list that took the first 200 rows it found showed only the playlist that
    /// was imported first. Every source has to be reachable.
    @Test
    func `all sources includes the channels of every playlist, however large the first is`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, first: 400, second: 60)

        let all = try fetch(catalog)

        #expect(all.count == 460)
        #expect(Set(all.map(\.playlist)) == ["a", "b"])
        #expect(all.filter { $0.playlist == "b" }.count == 60)
    }

    /// And the first page, which is all a user sees before scrolling, is a mix.
    @Test
    func `the first page is a mix of the sources, not the first playlist's rows`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, first: 400, second: 60)

        let page = try fetch(catalog, limit: LiveChannelQuery.pageSize)

        #expect(page.count == LiveChannelQuery.pageSize)
        #expect(page.contains { $0.playlist == "a" })
        #expect(page.contains { $0.playlist == "b" }, "the second source is missing from the first page")
    }

    // MARK: - Choosing a source

    @Test
    func `one source returns only its own channels`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, first: 400, second: 60)

        let onlyB = try fetch(catalog, source: "b")
        let onlyA = try fetch(catalog, source: "a")

        #expect(onlyB.count == 60)
        #expect(onlyB.allSatisfy { $0.playlist == "b" })
        #expect(onlyA.count == 400)
        #expect(onlyA.allSatisfy { $0.playlist == "a" })
    }

    @Test
    func `an unknown source is empty rather than everything`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, first: 5, second: 5)
        #expect(try fetch(catalog, source: "deleted").isEmpty)
    }

    @Test
    func `movies and series are not channels`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([
            live("live:1", "News"),
            CatalogEntry(id: "movie:1", kind: .movie, name: "A Movie"),
            CatalogEntry(id: "series:1", kind: .series, name: "A Show"),
            CatalogEntry(id: "x:1", kind: .unknown, name: "Mystery")
        ], playlist: "a")

        #expect(try fetch(catalog).map(\.name) == ["News"])
    }

    // MARK: - Order

    /// A person expects "arte" before "Das Erste" and "Österreich" among the Os.
    @Test
    func `names sort without regard to case or accents`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([
            live("1", "zdf"), live("2", "Das Erste"), live("3", "Österreich 1"),
            live("4", "arte"), live("5", "ORF"), live("6", "3sat"), live("7", "Éire")
        ], playlist: "a")

        #expect(try fetch(catalog).map(\.name) == ["3sat", "arte", "Das Erste", "Éire", "ORF", "Österreich 1", "zdf"])
    }

    @Test
    func `sorting spans sources so the list is one alphabet`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([live("1", "Bravo"), live("3", "Delta")], playlist: "a")
        _ = try await catalog.store.upsertEntries([live("2", "Alpha"), live("4", "Charlie")], playlist: "b")

        #expect(try fetch(catalog).map(\.name) == ["Alpha", "Bravo", "Charlie", "Delta"])
    }

    @Test
    func `equal names keep a stable order`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries(
            [live("c", "Same"), live("a", "Same"), live("b", "Same")],
            playlist: "a"
        )

        #expect(try fetch(catalog).map(\.id) == ["a", "b", "c"])
    }

    @Test
    func `renaming a channel moves it in the list`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries(
            [live("1", "Alpha"), live("2", "Bravo"), live("3", "Charlie")],
            playlist: "a"
        )
        #expect(try fetch(catalog).map(\.name) == ["Alpha", "Bravo", "Charlie"])

        _ = try await catalog.store.upsertEntries([live("1", "Zulu")], playlist: "a")

        #expect(try fetch(catalog).map(\.name) == ["Bravo", "Charlie", "Zulu"])
    }

    // MARK: - Search

    @Test
    func `search ignores case and accents and works across or within sources`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([live("1", "Österreich 1"), live("2", "ORF Sport")], playlist: "a")
        _ = try await catalog.store.upsertEntries([live("3", "Sport Plus"), live("4", "News")], playlist: "b")

        #expect(try fetch(catalog, search: "sport").map(\.name) == ["ORF Sport", "Sport Plus"])
        #expect(try fetch(catalog, search: "OSTERREICH").map(\.name) == ["Österreich 1"])
        #expect(try fetch(catalog, source: "b", search: "sport").map(\.name) == ["Sport Plus"])
        #expect(try fetch(catalog, search: "nothing like this").isEmpty)
    }

    @Test(arguments: ["", "   ", "\n"])
    func `a blank search is no search`(text: String) async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([live("1", "One"), live("2", "Two")], playlist: "a")
        #expect(try fetch(catalog, search: text).count == 2)
    }

    // MARK: - Bounds

    @Test
    func `the limit is honoured and clamped`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries(
            (0 ..< 50).map { live("\($0)", String(format: "Ch %02d", $0)) },
            playlist: "a"
        )

        #expect(try fetch(catalog, limit: 10).count == 10)
        #expect(try fetch(catalog, limit: 10).map(\.name).first == "Ch 00")
        #expect(try fetch(catalog, limit: 0).count == 1, "a limit below one must still be a limit")
        #expect(LiveChannelQuery.descriptor(source: nil, search: "", limit: 10_000_000).fetchLimit == LiveChannelQuery
            .maxRows)
    }

    @Test
    func `every shape of the query is bounded`() {
        for source in [nil, "a"] as [String?] {
            for search in ["", "x"] {
                #expect(LiveChannelQuery.descriptor(source: source, search: search, limit: 300).fetchLimit == 300)
            }
        }
    }

    @Test
    func `the page grows by doubling up to the cap`() {
        #expect(LiveChannelQuery.nextLimit(after: 300) == 600)
        #expect(LiveChannelQuery.nextLimit(after: 3000) == LiveChannelQuery.maxRows)
        #expect(LiveChannelQuery.nextLimit(after: LiveChannelQuery.maxRows) == LiveChannelQuery.maxRows)

        var limit = LiveChannelQuery.pageSize
        var steps = 0
        while LiveChannelQuery.nextLimit(after: limit) != limit {
            limit = LiveChannelQuery.nextLimit(after: limit)
            steps += 1
        }
        #expect(steps <= 5, "reaching the cap should take a handful of re-reads")
    }

    // MARK: - The sort key

    @Test
    func `the name key folds case and accents`() {
        #expect(CatalogEntryRecord.nameKey(for: "Österreich 1") == "osterreich 1")
        #expect(CatalogEntryRecord.nameKey(for: "ZDF HD") == "zdf hd")
        #expect(CatalogEntryRecord.nameKey(for: "Café") == CatalogEntryRecord.nameKey(for: "cafe"))
    }

    @Test
    func `an unchanged entry does not dirty the record through its key`() throws {
        let container = try PanopContainers.makeCatalog(inMemory: true)
        let context = ModelContext(container)
        let entry = live("1", "Österreich 1")
        let record = CatalogEntryRecord(playlist: "a", entry: entry)
        context.insert(record)
        try context.save()

        #expect(record.apply(entry) == false)
        #expect(!context.hasChanges, "the derived key made an unchanged row look changed")
    }
}
