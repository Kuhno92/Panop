import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Discovery fields in the store", .serialized)
@MainActor
struct DiscoveryFieldsStoreTests {
    private func entry(_ id: String, adult: Bool = false) -> CatalogEntry {
        CatalogEntry(
            id: id, kind: .movie, name: "Film \(id)", groupName: "Films", rating: 7.5,
            tmdbID: 4242, isAdult: adult, year: 2024, genre: "Drama", cast: "A, B"
        )
    }

    @Test
    func `the fields are stored and read back, as a record and as a row`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([entry("m1"), entry("m2", adult: true)], playlist: "p")

        let records = try ModelContext(catalog.container).fetch(FetchDescriptor<CatalogEntryRecord>())
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        #expect(byID["m1"]?.tmdbID == 4242)
        #expect(byID["m1"]?.year == 2024)
        #expect(byID["m1"]?.genre == "Drama")
        #expect(byID["m1"]?.cast == "A, B")
        #expect(byID["m1"]?.isAdult == false)
        #expect(byID["m2"]?.isAdult == true)

        let row = try #require(byID["m1"].map(CatalogRow.init))
        #expect(row.tmdbID == 4242 && row.year == 2024 && row.genre == "Drama" && !row.isAdult)
        // No id is nil in a row, though the record holds 0.
        let none = try #require(CatalogEntryRecord(
            playlist: "p",
            entry: CatalogEntry(id: "n", kind: .movie, name: "N")
        ))
        #expect(none.tmdbID == 0)
        #expect(CatalogRow(none).tmdbID == nil)
    }

    @Test
    func `an unchanged re-import writes nothing, and a changed field is updated`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries([entry("m1")], playlist: "p")

        let again = try await catalog.store.upsertEntries([entry("m1")], playlist: "p")
        #expect(again.unchanged == 1 && again.updated == 0 && again.inserted == 0)

        var changed = entry("m1")
        changed.isAdult = true
        let updated = try await catalog.store.upsertEntries([changed], playlist: "p")
        #expect(updated.updated == 1)
    }

    @Test
    func `a title is found by its TMDB id through the index`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries(
            [entry("m1"), CatalogEntry(id: "m3", kind: .movie, name: "Other", tmdbID: 7)],
            playlist: "p"
        )
        let context = ModelContext(catalog.container)
        let wanted = [4242, 99]

        let found = try context.fetch(FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.kindRaw == "movie" && wanted.contains($0.tmdbID) }
        ))

        #expect(found.map(\.id) == ["m1"])
    }
}
