import Foundation
import Observation
import PanopCore
import PanopDiscover
import PanopSimkl
import SwiftData

/// The rails Home shows. Draws the last result at once and rebuilds in the background when what they
/// are made from has changed: the history, what is hidden, the catalog.
@MainActor
@Observable
final class DiscoveryModel {
    private(set) var built: [Rail] = []
    /// The Settings switch for suggestions.
    var isEnabled = true
    /// What the screens draw: nothing when the person turned suggestions off.
    var rails: [Rail] {
        isEnabled ? built : []
    }

    static let enabledKey = "showSuggestions"
    /// The Settings switch for the one rail that asks the network (Simkl's public trending list).
    static let trendingKey = "showTrending"

    /// Where Simkl lists a title, by `linkKey`, for the lists whose terms ask for a link back.
    private(set) var trendingLinks: [String: URL] = [:]
    @ObservationIgnored private var trending: [TrendingEntry] = []
    @ObservationIgnored private var planned: [TrendingEntry] = []
    @ObservationIgnored private var finishedElsewhere: Set<Int> = []
    @ObservationIgnored private var trendingStore: TrendingStore?

    static func linkKey(kind: MediaKind, tmdbID: Int) -> String {
        "\(kind.rawValue)|\(tmdbID)"
    }

    /// Takes the trending lists: the saved ones at once, then fresh ones if the saved are old. With the
    /// switch off nothing is read, asked for or shown.
    func loadTrending(
        enabled: Bool,
        source: SimklTrendingSource?,
        cacheURL: URL? = TrendingStore.defaultCacheURL
    ) async {
        guard enabled, let source else {
            setTrending([])
            return
        }
        let store = trendingStore ?? TrendingStore(source: source, cacheURL: cacheURL)
        trendingStore = store
        if let saved = await store.cached() {
            setTrending(saved.entries)
        }
        if let fresh = await store.refreshIfStale() {
            setTrending(fresh.entries)
        }
    }

    /// What the person's Simkl lists say: the titles they plan to watch, and those they have finished.
    func setSimklLists(_ items: [SimklListItem]) {
        let planned = items.filter { $0.status == .plantowatch }.enumerated().map { index, item in
            TrendingEntry(kind: item.kind, tmdbID: item.tmdbID, score: Double(items.count - index))
        }
        let finished = Set(items.filter { $0.status == .completed }.map(\.tmdbID))
        guard planned != self.planned || finished != finishedElsewhere else { return }
        self.planned = planned
        finishedElsewhere = finished
        if var context = lastContext {
            context.planned = planned
            context.finishedElsewhere = finished
            lastContext = context
            scheduleBuild()
        }
    }

    private func setTrending(_ entries: [TrendingEntry]) {
        guard entries != trending else { return }
        trending = entries
        trendingLinks = Dictionary(
            entries.compactMap { entry in
                entry.link.flatMap(URL.init(string:)).map { (Self.linkKey(kind: entry.kind, tmdbID: entry.tmdbID), $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        if var context = lastContext {
            context.trending = entries
            lastContext = context
            scheduleBuild()
        }
    }

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
            guard let self, let cached, built.isEmpty else { return }
            apply(cached)
        }
    }

    /// Builds for `context` unless it is the one already shown.
    func update(_ context: DiscoveryContext) {
        var context = context
        context.trending = trending
        context.planned = planned
        context.finishedElsewhere = finishedElsewhere
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
        if result.rails != built {
            built = result.rails
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
