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

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: selectedEngine) {
                    // `available` rather than `allCases`: KSPlayer is GPL-3.0
                    // and is not linked, so offering it would select an engine
                    // that cannot play anything. See docs/adr/0002.
                    ForEach(PlaybackEngineKind.available) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Panop falls back through the other engines when a stream refuses to start.")
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
