import SwiftUI

enum AppTab: Hashable {
    case home, live, movies, series, settings
}

struct RootView: View {
    @Environment(PlaylistLibrary.self) private var library
    @State private var selection: AppTab = UITestMode.startTab ?? .home

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
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        #if os(macOS)
        .modifier(DebugPlayerWindowOpener())
        #endif
        // Playlists the user added keep themselves current without being asked.
        // The work runs on the sync service's actor, not here.
        .task { await library.refreshStale(maxAge: 12 * 3600) }
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
