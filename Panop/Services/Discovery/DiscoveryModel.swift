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
    /// Simkl's wide artwork for the titles on its lists, by `linkKey`: the stand-in where the provider has none.
    private(set) var fanart: [String: String] = [:]
    @ObservationIgnored private var trending: [TrendingEntry] = []
    /// The lists made from Simkl's public files, and what a connected account adds to them.
    @ObservationIgnored private var baseCurated: [CuratedList] = []
    @ObservationIgnored private var rankedLists: [CuratedList] = []
    @ObservationIgnored private var customLists: [CuratedList] = []
    @ObservationIgnored private var accountStore: SimklAccountListsStore?
    /// Where the account's lists are kept. A property so a test can keep them out of the real folder.
    @ObservationIgnored var accountCacheURL: URL? = SimklAccountListsStore.defaultCacheURL
    /// The plan of the connected account, once known: custom lists are for PRO and VIP.
    private(set) var simklPlan: SimklPlan?
    /// The ids of the lists worth a place on Home (`Rail.id`), the rest being for the Movies and Series screens.
    private(set) var highlighted: Set<String> = []
    @ObservationIgnored private var planned: [TrendingEntry] = []
    @ObservationIgnored private var watching: [TrendingEntry] = []
    /// The next episode to watch of each followed show, by `linkKey`, for the caption under its poster.
    private(set) var nextEpisodes: [String: SimklNextEpisode] = [:]
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
            setTrending([], lists: [])
            return
        }
        let store = trendingStore ?? TrendingStore(source: source, cacheURL: cacheURL)
        trendingStore = store
        if let saved = await store.cached() {
            setTrending(saved.entries, lists: saved.lists ?? [])
        }
        if let fresh = await store.refreshIfStale() {
            setTrending(fresh.entries, lists: fresh.lists ?? [])
        }
    }

    /// What the person's Simkl lists say: the titles they plan to watch, and those they have finished.
    func setSimklLists(_ items: [SimklListItem]) {
        let planned = items.filter { $0.status == .plantowatch }.enumerated().map { index, item in
            TrendingEntry(kind: item.kind, tmdbID: item.tmdbID, score: Double(items.count - index))
        }
        // Most recently watched first; a show with a new episode out, which Simkl dates later than the
        // last one watched, is as likely to be near the top as any.
        let followed = items.filter { $0.status == .watching && $0.next != nil }
            .sorted { ($0.lastWatchedAt ?? "") > ($1.lastWatchedAt ?? "") }
        let watching = followed.enumerated().map { index, item in
            TrendingEntry(kind: item.kind, tmdbID: item.tmdbID, score: Double(followed.count - index))
        }
        nextEpisodes = Dictionary(
            followed.compactMap { item in
                item.next.map { (Self.linkKey(kind: item.kind, tmdbID: item.tmdbID), $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let finished = Set(items.filter { $0.status == .completed }.map(\.tmdbID))
        guard planned != self.planned || watching != self.watching || finished != finishedElsewhere else { return }
        self.planned = planned
        self.watching = watching
        finishedElsewhere = finished
        if var context = lastContext {
            context.planned = planned
            context.watching = watching
            context.finishedElsewhere = finished
            lastContext = context
            scheduleBuild()
        }
    }

    private func setTrending(_ entries: [TrendingEntry], lists: [CuratedList]) {
        guard entries != trending || lists != baseCurated else { return }
        trending = entries
        baseCurated = lists
        applyCurated()
    }

    /// The lists the rails are made from: Simkl's public ones, with the rankings of a connected account in
    /// place of the same lists made from the files, and the account's own lists after them.
    private func applyCurated() {
        let lists = SimklAccountLists.merging(baseCurated, with: rankedLists) + customLists
        // Every title that came from Simkl links back to its page there, wherever it is shown.
        trendingLinks = Dictionary(
            (trending + lists.flatMap(\.entries)).compactMap { entry in
                entry.link.flatMap(URL.init(string:)).map { (Self.linkKey(kind: entry.kind, tmdbID: entry.tmdbID), $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        fanart = Dictionary(
            (trending + lists.flatMap(\.entries)).compactMap { entry in
                entry.fanart.flatMap(SimklArtwork.fanartURL).map {
                    (Self.linkKey(kind: entry.kind, tmdbID: entry.tmdbID), $0.absoluteString)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        highlighted = Set(lists.filter(\.isHighlight).map { "curated.\($0.kind.rawValue).\($0.id)" })
        if var context = lastContext {
            context.trending = trending
            context.curated = lists
            lastContext = context
            scheduleBuild()
        }
    }

    /// Fetches what the connected account adds, if it is out of date, and uses it. The rankings follow the
    /// same switch as the other Simkl lists; the account's own lists have a switch of their own.
    func refreshAccountLists(client: SimklClient, wantsRanked: Bool, wantsCustom: Bool) async throws {
        let store = accountStore ?? SimklAccountListsStore(cacheURL: accountCacheURL)
        accountStore = store
        if let saved = await store.cached() {
            use(saved, wantsRanked: wantsRanked, wantsCustom: wantsCustom)
        }
        if let fresh = try await store.refresh(client: client, wantsRanked: wantsRanked, wantsCustom: wantsCustom) {
            use(fresh, wantsRanked: wantsRanked, wantsCustom: wantsCustom)
        }
    }

    /// Drops what an account added, for when it is disconnected.
    func clearAccountLists() async {
        await (accountStore ?? SimklAccountListsStore(cacheURL: accountCacheURL)).clear()
        rankedLists = []
        customLists = []
        simklPlan = nil
        applyCurated()
    }

    private func use(_ snapshot: AccountListsSnapshot, wantsRanked: Bool, wantsCustom: Bool) {
        rankedLists = wantsRanked ? snapshot.ranked : []
        customLists = wantsCustom ? snapshot.custom : []
        simklPlan = snapshot.plan
        applyCurated()
    }

    private(set) var rows: [String: CatalogRow] = [:]

    /// Wide artwork for a title: the provider's own where its list gave one (series), otherwise Simkl's for a
    /// title on one of its lists, otherwise nil and the screen softens the poster instead.
    func backdrop(for row: CatalogRow) -> String? {
        backdrop(kind: row.kind, tmdbID: row.tmdbID, provider: row.backdropURL)
    }

    func backdrop(kind: MediaKind, tmdbID: Int?, provider: String?) -> String? {
        if let provider, !provider.isEmpty {
            return provider
        }
        return tmdbID.flatMap { fanart[Self.linkKey(kind: kind, tmdbID: $0)] }
    }

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

    /// Forgets everything shown, for when another person's profile takes over: their rails are not these.
    func reset() {
        buildTask?.cancel()
        buildTask = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        store = nil
        lastContext = nil
        generation += 1
        built = []
        rows = [:]
        phase = .loading
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
        context.curated = SimklAccountLists.merging(baseCurated, with: rankedLists) + customLists
        context.planned = planned
        context.watching = watching
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
        cacheURL(profile: "")
    }

    /// One file per profile: what is suggested depends on what that person has watched.
    nonisolated static func cacheURL(profile: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Discovery", isDirectory: true)
            .appendingPathComponent(profile.isEmpty ? "rails.json" : "rails-\(profile).json")
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
