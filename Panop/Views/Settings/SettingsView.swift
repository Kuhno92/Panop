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

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PlaylistsView()
                } label: {
                    LabeledContent("Playlists", value: library.playlists.count.formatted())
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
