import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \Channel.sortIndex) private var channels: [Channel]

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
    let channels: [Channel]

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
                        Text(channel.groupTitle ?? "")
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
        .modelContainer(for: Channel.self, inMemory: true)
}
