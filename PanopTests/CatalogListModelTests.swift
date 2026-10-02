import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Paged list model", .serialized, .engineGate)
@MainActor
struct CatalogListModelTests {
    private func populate(_ catalog: OnDiskCatalog, count: Int, playlist: String = "p") async throws {
        _ = try await catalog.store.upsertEntries(
            (0 ..< count).map {
                CatalogEntry(id: "c\($0)", kind: .live, name: "Channel \($0)", groupName: "G", sortNumber: $0 + 1)
            },
            playlist: playlist
        )
    }

    private func settle(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test
    func `the first page is small, in the provider's order, and marks the list loaded`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 500)
        let model = CatalogListModel()
        #expect(model.phase == .loading)

        model.show(ListSpec(kind: .live), in: catalog.container)

        #expect(await settle { model.phase == .loaded })
        #expect(model.rows.count == CatalogListModel.firstPage)
        #expect(model.rows.first?.name == "Channel 0")
        #expect(model.rows.last?.name == "Channel \(CatalogListModel.firstPage - 1)")
    }

    @Test
    func `reaching the end of what is loaded reads the next page and appends it`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 500)
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live), in: catalog.container)
        #expect(await settle { model.phase == .loaded })

        // A row far from the end asks for nothing.
        model.rowAppeared(model.rows[0])
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.rows.count == CatalogListModel.firstPage)

        model.rowAppeared(model.rows[model.rows.count - 1])

        let expected = CatalogListModel.firstPage + CatalogListModel.nextPage
        #expect(await settle { model.rows.count == expected })
        #expect(model.rows.map(\.name) == (0 ..< expected).map { "Channel \($0)" }, "appended, none repeated or lost")
    }

    @Test
    func `the end of the catalog is reached once, and nothing more is asked for`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 100)
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live), in: catalog.container)
        #expect(await settle { model.phase == .loaded })

        model.rowAppeared(model.rows[model.rows.count - 1])
        #expect(await settle { model.rows.count == 100 })
        model.rowAppeared(model.rows[model.rows.count - 1])
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.rows.count == 100)
    }

    @Test
    func `showing a different list replaces the rows, and an empty one is loaded, not loading`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 20, playlist: "p")
        try await populate(catalog, count: 5, playlist: "q")
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live, source: "p"), in: catalog.container)
        #expect(await settle { model.rows.count == 20 })

        model.show(ListSpec(kind: .live, source: "q"), in: catalog.container)
        #expect(await settle { model.rows.count == 5 })
        #expect(model.rows.allSatisfy { $0.playlist == "q" })

        model.show(ListSpec(kind: .live, source: "nobody"), in: catalog.container)
        #expect(await settle { model.rows.isEmpty })
        #expect(model.phase == .loaded)
    }

    @Test
    func `a fixed set is read whole, whatever its size`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 300)
        let model = CatalogListModel()
        let ids = (0 ..< 150).map { "c\($0)" }

        model.show(ListSpec(kind: .live, restrictedTo: ids), in: catalog.container)

        #expect(await settle { model.rows.count == 150 })
    }

    @Test
    func `a change to the catalog is picked up without being asked`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 10)
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live), in: catalog.container)
        #expect(await settle { model.rows.count == 10 })

        // What an import does: another context saves.
        _ = try await catalog.store.upsertEntries(
            [CatalogEntry(id: "c0", kind: .live, name: "Renamed", groupName: "G", sortNumber: 1),
             CatalogEntry(id: "new", kind: .live, name: "Brand New", groupName: "G", sortNumber: 11)],
            playlist: "p"
        )

        #expect(await settle { model.rows.count == 11 && model.rows.first?.name == "Renamed" })
    }

    @Test
    func `hidden entries are left out and paging neither repeats nor loses the rest`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog, count: 300)
        // Ten hidden among the first page, and some further down.
        let hidden = Set((0 ..< 10).map { "p|c\($0 * 5)" } + ["p|c100", "p|c200"])
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live, hidden: hidden), in: catalog.container)
        #expect(await settle { model.phase == .loaded })
        #expect(model.rows.count == CatalogListModel.firstPage - 10, "ten of the first page's rows were hidden")

        // Scroll to the end, page after page.
        let deadline = ContinuousClock.now + .seconds(10)
        while model.rows.count < 300 - hidden.count, ContinuousClock.now < deadline {
            if let last = model.rows.last {
                model.rowAppeared(last)
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let names = model.rows.map(\.name)
        #expect(names.count == 300 - hidden.count)
        #expect(Set(names).count == names.count, "no row read twice")
        #expect(!model.rows.contains { hidden.contains($0.id) })
    }

    @Test
    func `the entries of a hidden category are left out, and the rest page through whole`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertEntries(
            (0 ..< 200).map {
                CatalogEntry(
                    id: "c\($0)", kind: .live, name: "Channel \($0)",
                    groupName: $0 % 4 == 0 ? "Adult" : "General", sortNumber: $0 + 1
                )
            },
            playlist: "p"
        )
        let model = CatalogListModel()
        model.show(ListSpec(kind: .live, hiddenGroups: ["Adult"]), in: catalog.container)
        #expect(await settle { model.phase == .loaded })

        let deadline = ContinuousClock.now + .seconds(10)
        while model.rows.count < 150, ContinuousClock.now < deadline {
            if let last = model.rows.last {
                model.rowAppeared(last)
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(model.rows.count == 150, "a quarter were in the hidden category")
        #expect(model.rows.allSatisfy { $0.groupName == "General" })
        #expect(Set(model.rows.map(\.id)).count == 150)
    }
}
