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

            Section {
                Picker("Engine", selection: selectedEngine) {
                    // `selectable`: only engines with a working adapter. KSPlayer is
                    // GPL-3.0 and not linked (docs/adr/0002), and VLC and LumeEngine
                    // are not built yet, so offering them would select a player that
                    // cannot play anything.
                    ForEach(EngineRegistry.selectable) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text(
                    "Panop falls back through the other players when a stream refuses to start. More players are on the way."
                )
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
