import Foundation
import PanopCore
import SwiftData

/// The person's say over a provider's categories: which to hide, and in what order to show them.
///
/// The provider's own order is the starting point, and stays the order for anything the person
/// has not placed. What they have placed comes first, in the order they chose.
extension UserStateStore {
    /// What is left out of the lists: the categories the person hid and, while adult content is
    /// hidden, the ones named as adult. Everything that filters by category reads this.
    func hiddenCategories(of kind: MediaKind) -> Set<String> {
        guard hidesAdult else { return userHiddenCategories(of: kind) }
        return userHiddenCategories(of: kind).union(adultCategories(of: kind))
    }

    /// Only the categories the person chose to hide, for the screen where they manage them.
    func userHiddenCategories(of kind: MediaKind) -> Set<String> {
        hiddenCategoryNames[kind.rawValue] ?? []
    }

    /// The categories a provider names as adult content, once read from the catalog.
    func adultCategories(of kind: MediaKind) -> Set<String> {
        adultCategoryNames[kind.rawValue] ?? []
    }

    /// Every category, the person's order first and then the provider's. Hidden ones included,
    /// for the screen where they are managed.
    func arranged(_ providerOrder: [String], kind: MediaKind) -> [String] {
        let positions = categoryPositions[kind.rawValue] ?? [:]
        let placed = providerOrder.filter { positions[$0] != nil }.sorted {
            (positions[$0] ?? 0, $0) < (positions[$1] ?? 0, $1)
        }
        return placed + providerOrder.filter { positions[$0] == nil }
    }

    /// The categories to show: arranged, without the hidden.
    func visibleCategories(_ providerOrder: [String], kind: MediaKind) -> [String] {
        let hidden = hiddenCategories(of: kind)
        return arranged(providerOrder, kind: kind).filter { !hidden.contains($0) }
    }

    func setCategoryHidden(_ isHidden: Bool, name: String, kind: MediaKind) {
        let row = preference(name: name, kind: kind) ?? insertPreference(name: name, kind: kind)
        row.isHidden = isHidden
        removeIfDefault(row)
        commit()
    }

    /// Moves a category one place earlier (`-1`) or later (`1`) among all of them. Placing one
    /// places them all, in the order now shown, so the result does not depend on how the
    /// provider orders the rest.
    func moveCategory(_ name: String, by step: Int, among providerOrder: [String], kind: MediaKind) {
        moveCategories([name], by: step, among: providerOrder, kind: kind)
    }

    /// Several categories one place earlier or later at once, as a block (see ``CategoryOrder/moved``).
    func moveCategories(_ names: Set<String>, by step: Int, among providerOrder: [String], kind: MediaKind) {
        let order = arranged(providerOrder, kind: kind)
        let moved = CategoryOrder.moved(order, chosen: names, by: step)
        if moved != order {
            placeCategories(moved, kind: kind)
        }
    }

    /// Several categories to the top or the bottom of the list, in the order they already have.
    func moveCategoriesToEdge(_ names: Set<String>, atTop: Bool, among providerOrder: [String], kind: MediaKind) {
        let order = arranged(providerOrder, kind: kind)
        let placed = CategoryOrder.placed(order, chosen: names, atTop: atTop)
        if placed != order {
            placeCategories(placed, kind: kind)
        }
    }

    /// The whole order, as it is now to be: every category gets its place. One read of what is kept and one save, so
    /// that a list of hundreds is as quick to arrange as a list of ten.
    func placeCategories(_ order: [String], kind: MediaKind) {
        var rows = Dictionary(preferences(kind: kind).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for (position, name) in order.enumerated() {
            let row = rows[name] ?? insertPreference(name: name, kind: kind)
            rows[name] = row
            row.position = position
        }
        commit()
    }

    /// Hides or shows several categories at once, in one read and one save.
    func setCategoriesHidden(_ names: some Collection<String>, hidden: Bool, kind: MediaKind) {
        var rows = Dictionary(preferences(kind: kind).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for name in names {
            // Showing what was never hidden or placed has nothing to record.
            guard hidden || rows[name] != nil else { continue }
            let row = rows[name] ?? insertPreference(name: name, kind: kind)
            rows[name] = row
            row.isHidden = hidden
            removeIfDefault(row)
        }
        commit()
    }

    /// Back to the provider's order, with nothing hidden.
    func resetCategories(kind: MediaKind) {
        for row in preferences(kind: kind) {
            context.delete(row)
        }
        commit()
    }

    // MARK: - Rows

    func loadCategoryPreferences() {
        let current = profile
        let rows = (try? context
            .fetch(FetchDescriptor<CategoryPreference>(predicate: #Predicate { $0.profile == current }))) ?? []
        hiddenCategoryNames = Dictionary(grouping: rows.filter(\.isHidden), by: \.kindRaw)
            .mapValues { Set($0.map(\.name)) }
        categoryPositions = Dictionary(grouping: rows.filter { $0.position >= 0 }, by: \.kindRaw)
            .mapValues { Dictionary($0.map { ($0.name, $0.position) }, uniquingKeysWith: { first, _ in first }) }
    }

    private func preferences(kind: MediaKind) -> [CategoryPreference] {
        let raw = kind.rawValue
        let current = profile
        return (try? context.fetch(FetchDescriptor<CategoryPreference>(
            predicate: #Predicate { $0.kindRaw == raw && $0.profile == current }
        ))) ?? []
    }

    private func preference(name: String, kind: MediaKind) -> CategoryPreference? {
        let raw = kind.rawValue
        let current = profile
        var descriptor = FetchDescriptor<CategoryPreference>(
            predicate: #Predicate { $0.kindRaw == raw && $0.name == name && $0.profile == current }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func insertPreference(name: String, kind: MediaKind) -> CategoryPreference {
        let row = CategoryPreference(kindRaw: kind.rawValue, name: name)
        row.profile = profile
        context.insert(row)
        return row
    }

    /// A row that says nothing (not hidden, not placed) is not worth keeping.
    private func removeIfDefault(_ row: CategoryPreference) {
        if !row.isHidden, row.position < 0 {
            context.delete(row)
        }
    }
}
