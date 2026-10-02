import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import SwiftData
import Testing

@Suite("Category sections", .serialized, .engineGate)
@MainActor
struct CategorySectionsModelTests {
    private let day: TimeInterval = 86400

    private func populate(_ catalog: OnDiskCatalog) async throws {
        var entries: [CatalogEntry] = []
        // Action: 150 films, numbered by the provider 1...150, added a day apart, oldest first.
        for index in 0 ..< 150 {
            entries.append(CatalogEntry(
                id: "a\(index)", kind: .movie, name: String(format: "Action %03d", 149 - index), groupName: "Action",
                sortNumber: index + 1, addedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * day),
                rating: Double(index % 10)
            ))
        }
        for index in 0 ..< 30 {
            entries.append(CatalogEntry(
                id: "d\(index)", kind: .movie, name: "Drama \(index)", groupName: "Drama", sortNumber: 200 + index,
                addedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * day)
            ))
        }
        for index in 0 ..< 5 {
            entries.append(CatalogEntry(id: "u\(index)", kind: .movie, name: "Loose \(index)", sortNumber: 300 + index))
        }
        _ = try await catalog.store.upsertEntries(entries, playlist: "p")
    }

    private func settle(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func plan(
        _ categories: [String],
        order: LiveOrder = .provider,
        ungrouped: Bool = true,
        source: String? = nil
    ) -> CategorySectionsModel.Plan {
        .init(
            base: ListSpec(kind: .movie, source: source, order: order),
            categories: categories,
            includesUngrouped: ungrouped
        )
    }

    private func readAll(_ model: CategorySectionsModel) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        var last = -1
        while ContinuousClock.now < deadline {
            let total = model.sections.reduce(0) { $0 + $1.rows.count }
            if total == last, total > 0 {
                break
            }
            last = total
            if let row = model.sections.last?.rows.last {
                model.rowAppeared(row)
            }
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    @Test
    func `categories come one after another in the order given, and the loose entries last`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()

        model.show(plan(["Drama", "Action"]), in: catalog.container)
        #expect(await settle { model.phase == .loaded })
        try await readAll(model)

        #expect(model.sections.map(\.name) == ["Drama", "Action", nil])
        #expect(model.sections.map(\.rows.count) == [30, 150, 5])
    }

    @Test
    func `the first screen is filled across categories when the first is small`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()

        model.show(plan(["Drama", "Action"]), in: catalog.container)

        #expect(await settle { model.phase == .loaded })
        let total = model.sections.reduce(0) { $0 + $1.rows.count }
        #expect(total >= CategorySectionsModel.firstRead, "30 dramas is fewer than the first read, so Action follows")
        #expect(model.sections.first?.name == "Drama")
        #expect(model.sections.first?.rows.count == 30, "every drama before any action")
    }

    @Test
    func `paging through a large category neither repeats nor loses a row`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()
        model.show(plan(["Action"], ungrouped: false), in: catalog.container)
        #expect(await settle { model.phase == .loaded })

        try await readAll(model)

        let ids = model.sections.flatMap(\.rows).map(\.id)
        #expect(ids.count == 150)
        #expect(Set(ids).count == 150)
    }

    @Test
    func `within a category the rows follow the sort`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        func firstNames(_ order: LiveOrder) async throws -> [String] {
            let model = CategorySectionsModel()
            model.show(plan(["Action"], order: order, ungrouped: false), in: catalog.container)
            #expect(await settle { model.phase == .loaded })
            return model.sections.first?.rows.prefix(3).map(\.name) ?? []
        }

        // Provider order: numbered 1, 2, 3, which are Action 149, 148, 147.
        #expect(try await firstNames(.provider) == ["Action 149", "Action 148", "Action 147"])
        // By name: Action 000, 001, 002.
        #expect(try await firstNames(.name) == ["Action 000", "Action 001", "Action 002"])
        // Recently added: the last added is index 149, which is "Action 000".
        #expect(try await firstNames(.recentlyAdded) == ["Action 000", "Action 001", "Action 002"])
    }

    @Test
    func `top rated puts the best first and the unrated last`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()

        model.show(plan(["Action", "Drama"], order: .rating, ungrouped: false), in: catalog.container)
        #expect(await settle { model.phase == .loaded })

        let action = try #require(model.sections.first)
        #expect(action.name == "Action")
        #expect(action.rows.prefix(5).allSatisfy { $0.rating == 9 }, "nine is the best rating given")
    }

    @Test
    func `a category with nothing in it, or that does not exist, leaves no heading`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()

        model.show(plan(["Nothing", "Drama"], ungrouped: false), in: catalog.container)

        #expect(await settle { model.phase == .loaded })
        #expect(model.sections.map(\.name) == ["Drama"])
    }

    @Test
    func `hidden entries are left out of their sections`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        var base = ListSpec(kind: .movie)
        base.hidden = ["p|d0", "p|d1"]
        let model = CategorySectionsModel()

        model.show(.init(base: base, categories: ["Drama"], includesUngrouped: false), in: catalog.container)

        #expect(await settle { model.phase == .loaded })
        #expect(model.sections.first?.rows.count == 28)
    }

    @Test
    func `a source with no categories at all is one list with no heading`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = CategorySectionsModel()

        model.show(plan([], ungrouped: true, source: "p"), in: catalog.container)

        #expect(await settle { model.phase == .loaded })
        #expect(model.sections.map(\.name) == [nil])
        #expect(model.sections.first?.rows.count == 5, "only what has no category")
    }
}
