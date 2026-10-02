import SwiftData
import SwiftUI

nonisolated enum AppTab: Hashable {
    case home, live, movies, series, settings
}

struct RootView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog
    @State private var selection: AppTab
    @State private var autoplay: PlaybackTarget?
    /// One set of rails for Home, Movies and Series, built off the main thread (see `DiscoveryModel`).
    @State private var discovery = DiscoveryModel()
    @AppStorage(DiscoveryModel.enabledKey) private var showsSuggestions = true
    @AppStorage(DiscoveryModel.trendingKey) private var showsTrending = true

    init() {
        // The screen it opens on is known from the settings alone, so the first frame is the
        // right one. `applyStartupPlan` corrects it if that screen turns out not to be offered.
        _selection = State(initialValue: UITestMode.startTab ?? StartupPreference.current(offersVOD: true).tab)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack {
                    HomeView(onBrowse: { selection = .live })
                }
            }
            Tab("Live TV", systemImage: "tv", value: AppTab.live) {
                NavigationStack {
                    LiveTVView()
                }
            }
            // Only when some source has films and series to show.
            if library.offersVOD {
                Tab("Movies", systemImage: "film", value: AppTab.movies) {
                    NavigationStack {
                        VODBrowseView(kind: .movie)
                    }
                }
                Tab("Series", systemImage: "rectangle.stack", value: AppTab.series) {
                    NavigationStack {
                        VODBrowseView(kind: .series)
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .onChange(of: library.offersVOD) { _, offered in
            // A screen that went away cannot stay selected.
            if !offered, selection == .movies || selection == .series {
                selection = .home
            }
        }
        #if os(macOS)
        .modifier(DebugPlayerWindowOpener())
        #endif
        // Playlists the user added keep themselves current without being asked.
        // The work runs on the sync service's actor, not here.
        .task { await library.refreshStale(maxAge: 12 * 3600) }
        .environment(discovery)
        .task(id: showsTrending && showsSuggestions) {
            await discovery.loadTrending(enabled: showsTrending && showsSuggestions, source: .panop)
        }
        .onChange(of: showsSuggestions, initial: true) { discovery.isEnabled = showsSuggestions }
        // Rebuilt whenever what the rails are made from changes; an unchanged context is ignored. The
        // playlists are part of the key: they may load after the first pass, and nothing else would rerun it.
        .task(id: [userState.revision, library.playlists.count]) {
            guard !library.playlists.isEmpty else { return }
            discovery.start(container: catalog.container)
            discovery.update(DiscoveryContext.current(userState))
        }
        .modifier(PlayerPresentation(target: $autoplay))
        .task { applyStartupPlan() }
    }
}

private extension RootView {
    /// Carries out the launch plan once the library is known: a screen that is not offered
    /// becomes Home, and a chosen channel starts playing.
    ///
    /// The channel comes from the catalog already on disk, so nothing waits for a sync. One
    /// that has gone since is simply not found, and Live TV shows instead.
    @MainActor
    func applyStartupPlan() {
        // UI tests choose their own screen, and a stream would only get in their way.
        guard !UITestMode.isActive else { return }
        let plan = StartupPreference.current(offersVOD: library.offersVOD)
        selection = plan.tab
        guard let key = plan.channel else { return }
        guard let channel = StartupPreference.channel(for: key, in: catalog) else { return }
        userState.markPlayed(key)
        autoplay = PlaybackTarget(entry: channel)
    }
}

#Preview {
    let services = AppServices.preview()
    RootView()
        .modelContainer(services.catalogContainer)
        .environment(services.library)
        .environment(services.userState)
        .environment(services.syncStatus)
}

#if os(macOS)
    import SwiftData

    /// Debug only, and only when asked: opens the player window on the first seeded channel, so
    /// a person (or a screenshot) can see it work on a Mac, where nothing here can be clicked.
    private struct DebugPlayerWindowOpener: ViewModifier {
        @Environment(\.openWindow) private var openWindow
        @Environment(\.modelContext) private var catalog

        func body(content: Content) -> some View {
            #if DEBUG
                content.task {
                    guard UITestMode.opensPlayerWindow else { return }
                    for _ in 0 ..< 40 {
                        try? await Task.sleep(for: .milliseconds(250))
                        var descriptor = FetchDescriptor<CatalogEntryRecord>(
                            predicate: #Predicate { $0.kindRaw == "live" },
                            sortBy: [SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical)]
                        )
                        descriptor.fetchLimit = 1
                        if let first = (try? catalog.fetch(descriptor))?.first {
                            openWindow(id: PlayerWindow.id, value: PlayerWindowRequest(PlaybackTarget(entry: first)))
                            return
                        }
                    }
                }
            #else
                content
            #endif
        }
    }
#endif
