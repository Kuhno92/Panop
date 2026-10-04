import PanopCatalog
import PanopCore
import PanopSimkl
import SwiftData
import SwiftUI

/// A main tab shown as its icon alone. The name is still its accessibility label, so VoiceOver and the UI
/// tests find it, and the icon is what is seen.
struct MainTabLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // Icons alone in a bar on a phone, a Mac or a TV. In the sidebar of an iPad there is room, and an icon
        // with no name is a puzzle.
        #if os(macOS)
            // With room either side, so each is a wide, easy target in the bar.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .padding(.horizontal, 18)
        #elseif os(tvOS)
            // Icons alone, with room either side so each is a wide, easy target in the bar.
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .padding(.horizontal, 28)
        #else
            if sizeClass == .compact {
                Label(title, systemImage: systemImage).labelStyle(.iconOnly)
            } else {
                Label(title, systemImage: systemImage)
            }
        #endif
    }
}

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
    @State private var simkl: SimklAccount
    @State private var parental = ParentalControls.live()
    @State private var simklSync: SimklSync
    @State private var simklLibrary: SimklLibrary
    private let simklClient: SimklClient
    @AppStorage(SimklAccountListsStore.customKey) private var showsCustomLists = true
    @AppStorage(SimklSync.enabledKey) private var sendsWatched = true
    @AppStorage(DiscoveryModel.enabledKey) private var showsSuggestions = true
    @State private var profiles = ProfileStore()
    @Environment(CloudSyncStatus.self) private var cloudSync
    @AppStorage(CloudSync.loginsKey) private var syncsLogins = true
    @Environment(SyncStatusCenter.self) private var status
    @AppStorage(DiscoveryModel.trendingKey) private var showsTrending = true

    init() {
        // The screen it opens on is known from the settings alone, so the first frame is the
        // right one. `applyStartupPlan` corrects it if that screen turns out not to be offered.
        _selection = State(initialValue: UITestMode.startTab ?? StartupPreference.current(offersVOD: true).tab)
        let transport = URLSessionTransport()
        let account = SimklAccount(
            auth: SimklAuth(transport: transport, app: SimklConfig.app),
            store: SimklConfig.tokenStore
        )
        let client = SimklClient(transport: transport, app: SimklConfig.app) { await account.accessToken() }
        simklClient = client
        _simkl = State(initialValue: account)
        _simklSync = State(initialValue: SimklSync(send: { try await client.addHistory($0) }))
        _simklLibrary = State(initialValue: SimklLibrary(
            activities: { try await client.activities() },
            library: { try await client.library() }
        ))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.home) {
                NavigationStack {
                    HomeView(onBrowse: { selection = .live })
                }
            } label: {
                MainTabLabel("Home", systemImage: "house")
            }
            Tab(value: AppTab.live) {
                NavigationStack {
                    LiveTVView()
                }
            } label: {
                MainTabLabel("Live TV", systemImage: "tv")
            }
            // Only when some source has films and series to show.
            if library.offersVOD {
                Tab(value: AppTab.movies) {
                    NavigationStack {
                        VODBrowseView(kind: .movie)
                    }
                } label: {
                    MainTabLabel("Movies", systemImage: "film")
                }
                Tab(value: AppTab.series) {
                    NavigationStack {
                        VODBrowseView(kind: .series)
                    }
                } label: {
                    MainTabLabel("Series", systemImage: "rectangle.stack")
                }
            }
            Tab(value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            } label: {
                MainTabLabel("Settings", systemImage: "gearshape")
            }
        }
        #if os(iOS)
        // A tab bar on a phone, and a sidebar the person can open on an iPad. The Mac keeps its bar along the
        // top, as does Apple TV.
        .tabViewStyle(.sidebarAdaptable)
        #endif
        // Everything under it starts again, so no screen shows the last person's lists.
        .id(profiles.currentID)
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
        .environment(profiles)
        // Logins travel with the playlists only when the person wants it and iCloud is on. Run at launch and
        // whenever either changes: it sends what is there, takes what has arrived, or withdraws it.
        .task(id: [syncsLogins, cloudSync.availability == .active]) {
            let allowed = syncsLogins && cloudSync.availability == .active
            library.syncsLogins = { allowed }
            library.reconcileLogins()
        }
        // What another device changes arrives as an import: read it, and drop what was removed there.
        .task(id: cloudSync.availability == .active) {
            guard cloudSync.availability == .active else { return }
            for await _ in CloudChanges.imports() {
                userState.reloadAfterRemoteChange()
                await library.applyRemoteChanges()
            }
        } // Another person's profile: their state replaces this one's, and what was suggested is dropped.
        .onChange(of: profiles.currentID, initial: true) {
            if userState.profile != profiles.currentID {
                userState.switchProfile(profiles.currentID)
                discovery.reset()
            }
            userState.hidesAdult = profiles.current.hidesAdult
        }
        .onChange(of: profiles.current.hidesAdult, initial: true) { userState.hidesAdult = profiles.current.hidesAdult }
        // Which categories a provider calls adult is read from the catalog, again after each sync.
        .task(id: [library.playlists.count, status.isAnySyncing ? 1 : 0]) {
            let reader = CatalogReader(container: catalog.container)
            for kind in [MediaKind.live, .movie, .series] {
                let names = await reader.categoryNames(kind: kind, source: nil)
                userState.adultCategoryNames[kind.rawValue] = Set(names.filter(TitleMetadata.isAdultCategory))
            }
        }
        .environment(simkl)
        .environment(parental)
        .environment(simklSync)
        // What is finished goes to Simkl only while connected and switched on; the queue belongs to the
        // account it was made for, so signing out drops it.
        .task(id: [sendsWatched, simkl.isConnected, showsTrending, showsSuggestions, showsCustomLists]) {
            userState.onFinished = { [simklSync] key, date in simklSync.finished(key, at: date) }
            simklSync.isEnabled = sendsWatched && simkl.isConnected
            if simkl.isConnected {
                simklSync.flushIfNeeded()
                await simklLibrary.refresh()
                // Simkl's real rankings and the person's own lists. A refused login signs them out.
                do {
                    try await discovery.refreshAccountLists(
                        client: simklClient,
                        wantsRanked: showsTrending && showsSuggestions,
                        wantsCustom: showsCustomLists && showsSuggestions
                    )
                } catch SimklError.unauthorized {
                    await simkl.signOut()
                } catch {}
            } else {
                simklSync.discardQueue()
                simklLibrary.clear()
                await discovery.clearAccountLists()
            }
        }
        .onChange(of: simklLibrary.items, initial: true) { discovery.setSimklLists(simklLibrary.items) }
        .task(id: showsTrending && showsSuggestions) {
            await discovery.loadTrending(enabled: showsTrending && showsSuggestions, source: .panop)
        }
        .onChange(of: showsSuggestions, initial: true) { discovery.isEnabled = showsSuggestions }
        // Rebuilt whenever what the rails are made from changes; an unchanged context is ignored. The
        // playlists are part of the key: they may load after the first pass, and nothing else would rerun it.
        .task(id: [userState.revision, library.playlists.count]) {
            guard !library.playlists.isEmpty else { return }
            discovery.start(
                container: catalog.container,
                cacheURL: DiscoveryModel.cacheURL(profile: userState.profile)
            )
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
        .environment(CloudSyncStatus())
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
