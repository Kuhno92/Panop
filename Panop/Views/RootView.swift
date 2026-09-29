import SwiftData
import SwiftUI

struct RootView: View {
    @Query(RootView.liveChannels) private var channels: [CatalogEntryRecord]
    @Environment(PlaylistLibrary.self) private var library

    /// Placeholder until the browse screens. It is bounded and unsorted on
    /// purpose: a sort with no index behind it would defeat the limit and read
    /// the whole table, which is exactly what this rule exists to prevent.
    private static var liveChannels: FetchDescriptor<CatalogEntryRecord> {
        var descriptor = FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.kindRaw == "live" }
        )
        descriptor.fetchLimit = 200
        return descriptor
    }

    var body: some View {
        TabView {
            Tab("Live TV", systemImage: "tv") {
                NavigationStack {
                    ChannelListView(channels: channels)
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

struct ChannelListView: View {
    let channels: [CatalogEntryRecord]

    @Environment(SyncStatusCenter.self) private var status
    @State private var showingAdd = false

    var body: some View {
        Group {
            if channels.isEmpty {
                if status.isAnySyncing {
                    ContentUnavailableView {
                        ProgressView()
                    } description: {
                        Text("Getting your channels…")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No playlist yet", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Add an M3U playlist or Xtream provider to get started.")
                    } actions: {
                        Button("Add playlist") { showingAdd = true }
                    }
                }
            } else {
                List(channels) { channel in
                    LabeledContent(channel.name) {
                        Text(channel.groupName ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Live TV")
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
    }
}

#Preview {
    let services = AppServices.preview()
    RootView()
        .modelContainer(services.catalogContainer)
        .environment(services.library)
        .environment(services.syncStatus)
}
