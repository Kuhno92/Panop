import SwiftData
import SwiftUI

struct RootView: View {
    @Query(RootView.liveChannels) private var channels: [CatalogEntryRecord]

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
    }
}

struct ChannelListView: View {
    let channels: [CatalogEntryRecord]

    var body: some View {
        Group {
            if channels.isEmpty {
                ContentUnavailableView(
                    "No playlist yet",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Add an M3U playlist or Xtream provider to get started.")
                )
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
    }
}

#Preview {
    RootView()
        .modelContainer(for: CatalogEntryRecord.self, inMemory: true)
}
