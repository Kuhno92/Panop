import Foundation
import Observation
import PanopCore
import PanopDiscover
import SwiftData

/// The rails Home shows. Draws the last result at once and rebuilds in the background when what they
/// are made from has changed: the history, what is hidden, the catalog.
@MainActor
@Observable
final class DiscoveryModel {
    private(set) var rails: [Rail] = []
    private(set) var rows: [String: CatalogRow] = [:]
    /// `loading` until the first result, cached or built, has arrived.
    private(set) var phase = CatalogListModel.Phase.loading

    /// A change is waited out for this long, so a burst of them (an import saving in batches) is one rebuild.
    static let rebuildDelay = Duration.milliseconds(800)

    @ObservationIgnored private var store: DiscoveryStore?
    @ObservationIgnored private var lastContext: DiscoveryContext?
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = 0

    isolated deinit {
        buildTask?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts reading: the cached rails now, and the catalog's changes from here on.
    func start(container: ModelContainer, cacheURL: URL? = DiscoveryModel.defaultCacheURL) {
        guard store == nil else { return }
        let store = DiscoveryStore(container: container, cacheURL: cacheURL)
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.object as? ModelContext)?.container === container else { return }
            MainActor.assumeIsolated { self?.catalogChanged() }
        }
        Task { [weak self] in
            let cached = await store.cached()
            guard let self, let cached, rails.isEmpty else { return }
            apply(cached)
        }
    }

    /// Builds for `context` unless it is the one already shown.
    func update(_ context: DiscoveryContext) {
        guard context != lastContext else { return }
        lastContext = context
        scheduleBuild()
    }

    private func catalogChanged() {
        guard lastContext != nil else { return }
        scheduleBuild()
    }

    private func scheduleBuild() {
        guard let store, let context = lastContext else { return }
        buildTask?.cancel()
        generation += 1
        let current = generation
        // The first result is not waited for: there is nothing on screen to protect from churn yet.
        let delay = phase == .loading ? Duration.zero : Self.rebuildDelay
        buildTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await store.build(context)
            guard !Task.isCancelled, let self, current == generation else { return }
            apply(result)
        }
    }

    private func apply(_ result: DiscoveryResult) {
        if result.rails != rails {
            rails = result.rails
        }
        if result.rows != rows {
            rows = result.rows
        }
        phase = .loaded
    }

    /// Where the last result is kept, so Home has something to draw before the first build finishes.
    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Discovery", isDirectory: true)
            .appendingPathComponent("rails.json")
    }
}

extension DiscoveryContext {
    /// What the rails are built from at this moment, read from the person's own state.
    @MainActor
    static func current(
        _ userState: UserStateStore,
        trending: [TrendingEntry] = [],
        now: Date = .now
    ) -> DiscoveryContext {
        var hiddenCategories: [MediaKind: Set<String>] = [:]
        for kind in [MediaKind.movie, .series] {
            hiddenCategories[kind] = userState.hiddenCategories(of: kind)
        }
        // A show with any episode opened counts as started, and is not suggested.
        let started = Set(userState.plays.values.map(\.parentKey).filter { !$0.isEmpty })
        return DiscoveryContext(
            seeds: userState.tasteSeeds(limit: 5).map { DiscoverySeed(key: $0.key, weight: $0.weight) },
            playCounts: userState.playCounts(limit: 30).map { PlayCount(key: $0.key, times: $0.count) },
            unavailable: userState.watched.union(userState.progress.keys).union(started),
            hidden: userState.hidden,
            hiddenCategories: hiddenCategories,
            trending: trending,
            day: Int(now.timeIntervalSince1970 / 86400)
        )
    }
}
