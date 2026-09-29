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
    @State private var playing: PlaybackTarget?

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
                    Button {
                        playing = PlaybackTarget(entry: channel)
                    } label: {
                        LabeledContent(channel.name) {
                            Text(channel.groupName ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Live TV")
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .modifier(PlayerPresentation(target: $playing))
    }
}

extension PlaybackTarget {
    /// A snapshot of a catalog row, so the player never holds the live record.
    init(entry: CatalogEntryRecord) {
        self.init(
            playlist: entry.playlist,
            entryID: entry.id,
            kind: entry.kind,
            name: entry.name,
            streamURL: entry.streamURL,
            remoteID: entry.remoteID,
            containerExtension: entry.containerExtension
        )
    }
}

/// Full screen where the platform has it; a sheet on the Mac.
private struct PlayerPresentation: ViewModifier {
    @Binding var target: PlaybackTarget?

    func body(content: Content) -> some View {
        #if os(macOS)
            content.sheet(item: $target) { target in
                PlayerScreen(target: target).frame(minWidth: 880, minHeight: 520)
            }
        #else
            content.fullScreenCover(item: $target) { target in
                PlayerScreen(target: target)
            }
        #endif
    }
}

#Preview {
    let services = AppServices.preview()
    RootView()
        .modelContainer(services.catalogContainer)
        .environment(services.library)
        .environment(services.syncStatus)
}
