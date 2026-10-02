import PanopPlayback
import SwiftUI

struct SettingsView: View {
    @AppStorage("playbackEngine") private var engineRaw = PlaybackEngineKind.avPlayer.rawValue

    private var selectedEngine: Binding<PlaybackEngineKind> {
        Binding(
            get: { PlaybackEngineKind(rawValue: engineRaw) ?? .avPlayer },
            set: { engineRaw = $0.rawValue }
        )
    }

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @AppStorage(DiscoveryModel.enabledKey) private var showsSuggestions = true
    @AppStorage(DiscoveryModel.trendingKey) private var showsTrending = true
    @State private var confirmingForget = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PlaylistsView()
                } label: {
                    LabeledContent("Playlists", value: library.playlists.count.formatted())
                }
                if !userState.hidden.isEmpty {
                    NavigationLink {
                        HiddenEntriesView()
                    } label: {
                        LabeledContent("Hidden", value: userState.hidden.count.formatted())
                    }
                }
            } header: {
                Text("Library")
            }

            StartupSection()

            Section {
                Picker("Engine", selection: selectedEngine) {
                    // `selectable`: only engines with a working adapter. KSPlayer is
                    // GPL-3.0 and not linked (docs/adr/0002), so it is never offered.
                    ForEach(EngineRegistry.selectable) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text(
                    "Panop tries your choice first, and falls back through the other players when a stream will not start."
                )
            }

            Section {
                Toggle("Show suggestions", isOn: $showsSuggestions)
                if SimklConfig.isConfigured {
                    Toggle("Show what's trending on Simkl", isOn: $showsTrending)
                        .disabled(!showsSuggestions)
                }
                Button("Forget what I watched", role: .destructive) { confirmingForget = true }
            } header: {
                Text("Suggestions")
            } footer: {
                Text(
                    "Suggestions are chosen on this device from your own library and what you watch. "
                        + "What is trending is Simkl's public list, fetched the same way for everyone. "
                        + "Nothing about you or what you watch is sent."
                )
            }
            .confirmationDialog(
                "Forget what you watched?", isPresented: $confirmingForget, titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) { userState.forgetViewingHistory() }
            } message: {
                Text(
                    "Recently watched, watched marks and the suggestions based on them go. Favourites and hidden titles stay."
                )
            }

            if SimklConfig.isConfigured {
                SimklSettingsSection()
            }

            Section {
                NavigationLink {
                    PlaybackStatisticsView()
                } label: {
                    Label("Playback Statistics", systemImage: "chart.bar")
                }
            } footer: {
                Text("How fast channels start and how often they stall. Kept on this device only.")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
