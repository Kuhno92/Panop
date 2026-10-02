import Foundation
import Observation
import SwiftData

/// A list shown category by category: every film of the first category, then of the second, and
/// so on, each under its own heading, read in pages in the background.
///
/// The order of the categories is the one the person set up (or the provider's). Within a
/// category the rows follow the chosen sort. A page is read from one category until it is used
/// up, then the next, so the first screen fills at once however large the first category is.
@MainActor
@Observable
final class CategorySectionsModel {
    private(set) var sections: [CategorySection] = []
    /// `loading` until the first read of the current list has come back.
    private(set) var phase = CatalogListModel.Phase.loading

    /// What a list is: the rows to ask for, and the categories to ask in, in order.
    struct Plan: Hashable, Sendable {
        /// Kind, source, search, sort, and what is hidden. Its category is set per step.
        var base: ListSpec
        var categories: [String]
        /// Whether to end with the entries that have no category.
        var includesUngrouped: Bool
    }

    static let firstRead = 60
    static let nextRead = 120
    static let pageSize = 120
    static let lookahead = 30
    static let refreshDelay = Duration.seconds(1)

    @ObservationIgnored private var plan: Plan?
    @ObservationIgnored private var steps: [ListSpec] = []
    @ObservationIgnored private var reader: CatalogReader?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var step = 0
    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var finished = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?

    isolated deinit {
        loadTask?.cancel()
        refreshTask?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Shows `plan`. A list already showing it is left alone, so this can run on every update.
    func show(_ plan: Plan, in container: ModelContainer) {
        if reader == nil {
            reader = CatalogReader(container: container)
            observe(container)
        }
        guard plan != self.plan, let reader else { return }
        self.plan = plan
        steps = Self.steps(for: plan)
        generation += 1
        step = 0
        offset = 0
        finished = false
        loading = true
        loadTask?.cancel()
        let current = generation
        let steps = steps
        loadTask = Task { [weak self] in
            let batch = await reader.sections(
                steps, step: 0, offset: 0, minimum: Self.firstRead, pageSize: Self.pageSize
            )
            guard !Task.isCancelled, let self, current == generation else { return }
            // The old rows stay until these arrive, so a changed sort does not flash empty.
            sections = batch.sections
            apply(batch)
            phase = .loaded
        }
    }

    /// Call as a row appears: near the end of what is loaded, the next rows are read.
    func rowAppeared(_ row: CatalogRow) {
        guard !finished, !loading, let reader,
              sections.last?.rows.suffix(Self.lookahead).contains(where: { $0.id == row.id }) == true else { return }
        loading = true
        let current = generation
        let (steps, start, offset) = (steps, step, offset)
        Task { [weak self] in
            let batch = await reader.sections(
                steps, step: start, offset: offset, minimum: Self.nextRead, pageSize: Self.pageSize
            )
            guard let self, current == generation else { return }
            merge(batch)
            apply(batch)
        }
    }

    private func apply(_ batch: SectionBatch) {
        step = batch.step
        offset = batch.offset
        finished = batch.finished
        loading = false
    }

    private func merge(_ batch: SectionBatch) {
        for section in batch.sections {
            if let last = sections.last, last.name == section.name {
                sections[sections.count - 1].rows += section.rows
            } else {
                sections.append(section)
            }
        }
    }

    private static func steps(for plan: Plan) -> [ListSpec] {
        var steps = plan.categories.map { name -> ListSpec in
            var spec = plan.base
            spec.group = name
            return spec
        }
        if plan.includesUngrouped {
            var spec = plan.base
            spec.group = nil
            spec.ungrouped = true
            steps.append(spec)
        }
        return steps
    }

    // MARK: - Following the catalog

    private func observe(_ container: ModelContainer) {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.object as? ModelContext)?.container === container else { return }
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Reads as many rows again as are shown, from the start, and swaps them in if they differ.
    private func refresh() async {
        guard let reader, !steps.isEmpty else { return }
        let current = generation
        let shown = sections.reduce(0) { $0 + $1.rows.count }
        let batch = await reader.sections(
            steps, step: 0, offset: 0, minimum: Swift.max(shown, Self.firstRead), pageSize: Self.pageSize
        )
        guard current == generation, batch.sections != sections else { return }
        sections = batch.sections
        apply(batch)
    }
}
