import Foundation
import PanopCore
import SwiftData

/// The person's say over a provider's categories: which to hide, and in what order to show them.
///
/// The provider's own order is the starting point, and stays the order for anything the person
/// has not placed. What they have placed comes first, in the order they chose.
extension UserStateStore {
    func hiddenCategories(of kind: MediaKind) -> Set<String> {
        hiddenCategoryNames[kind.rawValue] ?? []
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
        var order = arranged(providerOrder, kind: kind)
        guard let index = order.firstIndex(of: name), order.indices.contains(index + step) else { return }
        order.swapAt(index, index + step)
        for (position, category) in order.enumerated() {
            let row = preference(name: category, kind: kind) ?? insertPreference(name: category, kind: kind)
            row.position = position
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
        let rows = (try? context.fetch(FetchDescriptor<CategoryPreference>())) ?? []
        hiddenCategoryNames = Dictionary(grouping: rows.filter(\.isHidden), by: \.kindRaw)
            .mapValues { Set($0.map(\.name)) }
        categoryPositions = Dictionary(grouping: rows.filter { $0.position >= 0 }, by: \.kindRaw)
            .mapValues { Dictionary($0.map { ($0.name, $0.position) }, uniquingKeysWith: { first, _ in first }) }
    }

    private func preferences(kind: MediaKind) -> [CategoryPreference] {
        let raw = kind.rawValue
        return (try? context.fetch(FetchDescriptor<CategoryPreference>(predicate: #Predicate { $0.kindRaw == raw }))) ??
            []
    }

    private func preference(name: String, kind: MediaKind) -> CategoryPreference? {
        let raw = kind.rawValue
        var descriptor =
            FetchDescriptor<CategoryPreference>(predicate: #Predicate { $0.kindRaw == raw && $0.name == name })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func insertPreference(name: String, kind: MediaKind) -> CategoryPreference {
        let row = CategoryPreference(kindRaw: kind.rawValue, name: name)
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
