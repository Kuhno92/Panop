import SwiftUI

struct RootView: View {
    @Environment(PlaylistLibrary.self) private var library

    var body: some View {
        TabView {
            Tab("Live TV", systemImage: "tv") {
                NavigationStack {
                    LiveTVView()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
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
        .environment(services.syncStatus)
}
