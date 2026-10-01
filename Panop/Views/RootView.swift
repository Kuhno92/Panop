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
