import Foundation
import Observation
import SwiftData

/// The rows of one list, read in pages on a background thread and appended as you scroll.
///
/// The reason it exists: a list built on `@Query` re-reads its whole result each time it grows, on
/// the main thread. Against a real provider that was 18 ms to go from 300 rows to 600 and 31 ms
/// from 600 to 1,200, mid-scroll, in a frame budget of 16 (8 on a ProMotion display). Here the
/// first page is small, every later page is appended rather than re-read, and none of it touches
/// the main thread but the hand-over.
@MainActor
@Observable
final class CatalogListModel {
    enum Phase { case loading, loaded }

    private(set) var rows: [CatalogRow] = []
    /// `loading` until the first page of the current list has arrived, so an empty list is not
    /// mistaken for one still being read.
    private(set) var phase = Phase.loading

    /// Small, so the first rows are on screen at once.
    static let firstPage = 60
    static let nextPage = 120
    /// Rows from the end at which the next page is asked for, so it is there before the end is.
    static let lookahead = 30
    /// Changes arrive in bursts while a provider imports. They are folded into one read.
    static let refreshDelay = Duration.seconds(1)

    @ObservationIgnored private var reader: CatalogReader?
    @ObservationIgnored private var spec: ListSpec?
    @ObservationIgnored private var generation = 0
    /// How many rows have been read from the catalog, which is more than `rows.count` by the
    /// hidden ones left out. The next page starts here, or it would read some twice.
    @ObservationIgnored private var consumed = 0
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var loadingMore = false
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

    /// Shows `spec`. A list already showing it is left alone, so this can run on every update.
    func show(_ spec: ListSpec, in container: ModelContainer) {
        if reader == nil {
            reader = CatalogReader(container: container)
            observe(container)
        }
        guard spec != self.spec, let reader else { return }
        self.spec = spec
        generation += 1
        consumed = 0
        reachedEnd = false
        loadingMore = false
        loadTask?.cancel()
        let current = generation
        loadTask = Task { [weak self] in
            let page = await reader.rows(spec, offset: 0, limit: Self.firstPage)
            guard !Task.isCancelled, let self, current == generation else { return }
            // The old rows stay until these arrive, so a changed filter does not flash empty.
            rows = Self.visible(page, in: spec)
            consumed = page.count
            phase = .loaded
            reachedEnd = spec.restrictedTo != nil || page.count < Self.firstPage
        }
    }

    /// Call as a row appears: near the end, the next page is read.
    func rowAppeared(_ row: CatalogRow) {
        guard !reachedEnd, !loadingMore, rows.count < LiveChannelQuery.maxRows,
              rows.suffix(Self.lookahead).contains(where: { $0.id == row.id }),
              let spec, let reader else { return }
        loadingMore = true
        let current = generation
        let offset = consumed
        Task { [weak self] in
            let page = await reader.rows(spec, offset: offset, limit: Self.nextPage)
            guard let self, current == generation else { return }
            rows.append(contentsOf: Self.visible(page, in: spec))
            consumed += page.count
            reachedEnd = page.count < Self.nextPage
            loadingMore = false
        }
    }

    /// The page without what the person has hidden, an entry at a time or a category at a time.
    private static func visible(_ page: [CatalogRow], in spec: ListSpec) -> [CatalogRow] {
        guard !spec.hidden.isEmpty || !spec.hiddenGroups.isEmpty else { return page }
        return page.filter { row in
            !spec.hidden.contains(row.id) && !(row.groupName.map(spec.hiddenGroups.contains) ?? false)
        }
    }

    // MARK: - Following the catalog

    /// An import saves the catalog in many small batches. Each save is noticed, and the list is
    /// read again once things have been quiet for a moment.
    private func observe(_ container: ModelContainer) {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            // Settled here, before crossing to the main actor: a notification is not `Sendable`.
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

    /// Reads what is shown again, in one go, and swaps it in only if it changed.
    private func refresh() async {
        guard let spec, let reader else { return }
        let current = generation
        let count = Swift.max(consumed, Self.firstPage)
        let raw = await reader.rows(spec, offset: 0, limit: count)
        let fresh = Self.visible(raw, in: spec)
        guard current == generation, fresh != rows else { return }
        rows = fresh
        consumed = raw.count
        reachedEnd = spec.restrictedTo != nil || raw.count < count
    }
}
