import PanopPlayback
import SwiftUI

/// Settings, in the order a person goes through them: where the content comes from, how it plays, what Home shows,
/// who may see what, the accounts that sync it, and then the odds and ends. Each row says in plain words what it is
/// for.
struct SettingsView: View {
    @AppStorage("playbackEngine") private var engineRaw = PlaybackEngineKind.avPlayer.rawValue

    /// Turning the filter off asks for the PIN when there is one; turning it on never does.
    private var hidesAdultGuarded: Binding<Bool> {
        Binding(
            get: { profiles.current.hidesAdult },
            set: { newValue in
                if newValue {
                    profiles.setHidesAdult(true)
                } else if parental.hasPIN {
                    pinPurpose = .unlock
                } else {
                    profiles.setHidesAdult(false)
                }
            }
        )
    }

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
    @Environment(ProfileStore.self) private var profiles
    @Environment(ParentalControls.self) private var parental
    @State private var pinPurpose: PINPurpose?
    @State private var confirmingForget = false
    #if os(macOS)
        @AppStorage("playsInSeparateWindow") private var separateWindow = false
    #endif

    var body: some View {
        Form {
            sources
            playing
            homeScreen
            familyAndSafety
            accounts
            about
        }
        // Grouped, so each group is its own card with room around it, and the whole form scrolls: on a Mac the
        // plain form style neither separates the groups nor scrolls when the window is shorter than the list.
        .formStyle(.grouped)
        #if !os(tvOS)
            .headerProminence(.increased)
        #endif
            .pageBackdrop()
            .navigationTitle("Settings")
            .sheet(item: $pinPurpose) { purpose in
                PINSheet(purpose: purpose) {
                    // A PIN is for keeping the filter on: setting one turns it on.
                    if purpose == .create {
                        profiles.setHidesAdult(true)
                    }
                    if purpose == .unlock {
                        profiles.setHidesAdult(false)
                    }
                }
            }
    }

    // MARK: - Where the content comes from

    private var sources: some View {
        Section {
            NavigationLink {
                PlaylistsView()
            } label: {
                SettingsRow("Playlists", symbol: "antenna.radiowaves.left.and.right", tint: .blue, value: sourceCount)
            }
        } header: {
            Text("Your content")
        } footer: {
            Text("Where your channels, movies and series come from. Add or update your provider here.")
        }
    }

    private var sourceCount: String {
        library.playlists.isEmpty ? String(localized: "None yet") : String(library.playlists.count)
    }

    // MARK: - How it plays

    private var playing: some View {
        Section {
            Picker(selection: selectedEngine) {
                // `selectable`: only engines with a working adapter. KSPlayer is
                // GPL-3.0 and not linked (docs/adr/0002), so it is never offered.
                ForEach(EngineRegistry.selectable) { kind in
                    Text(kind.displayName).tag(kind)
                }
            } label: {
                SettingsRow("Engine", symbol: "play.rectangle.fill", tint: .indigo)
            }
            #if os(macOS)
                Toggle(isOn: $separateWindow) {
                    SettingsRow("Play in a separate window", symbol: "macwindow.on.rectangle", tint: .cyan)
                }
            #endif
            NavigationLink {
                SubtitleSettingsView()
            } label: {
                SettingsRow("Subtitles", symbol: "captions.bubble.fill", tint: .teal)
            }
            StartupPicker()
        } header: {
            Text("Playing")
        } footer: {
            Text("""
            If a video will not start, change the engine. Panop tries your choice first and then the others by itself. \
            On a Mac a stream plays in the main window, and you can still use the rest of the app over it.
            """)
        }
    }

    // MARK: - What Home shows

    private var homeScreen: some View {
        Section {
            Toggle(isOn: $showsSuggestions) {
                SettingsRow("Show suggestions", symbol: "sparkles", tint: .orange)
            }
            if SimklConfig.isConfigured {
                Toggle(isOn: $showsTrending) {
                    SettingsRow("Show Simkl's trending and best-of lists", symbol: "flame.fill", tint: .red)
                }
                .disabled(!showsSuggestions)
            }
            Button(role: .destructive) {
                confirmingForget = true
            } label: {
                SettingsRow("Forget what I watched", symbol: "clock.arrow.circlepath", tint: .gray)
            }
        } header: {
            Text("Home screen")
        } footer: {
            Text("""
            Suggestions are picked on this device from your own library and what you watch. \
            Nothing about you or what you watch is sent anywhere.
            """)
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
    }

    // MARK: - Who may see what

    private var familyAndSafety: some View {
        Section {
            NavigationLink {
                ProfilesView()
            } label: {
                SettingsRow("Profiles", symbol: "person.2.fill", tint: .green, value: profiles.current.name)
            }
            Toggle(isOn: hidesAdultGuarded) {
                SettingsRow("Hide adult content", symbol: "eye.slash.fill", tint: .pink)
            }
            if parental.hasPIN {
                Button { pinPurpose = .change } label: {
                    SettingsRow("Change PIN…", symbol: "lock.rotation", tint: .gray)
                }
                Button(role: .destructive) { pinPurpose = .remove } label: {
                    SettingsRow("Remove PIN…", symbol: "lock.open.fill", tint: .gray)
                }
            } else {
                Button { pinPurpose = .create } label: {
                    SettingsRow("Set a PIN…", symbol: "lock.fill", tint: .gray)
                }
            }
            if !userState.hidden.isEmpty {
                NavigationLink {
                    HiddenEntriesView()
                } label: {
                    SettingsRow("Hidden", symbol: "eye.slash", tint: .gray, value: String(userState.hidden.count))
                }
            }
        } header: {
            Text("Family and safety")
        } footer: {
            Text("""
            Hiding adult content leaves out what a provider files as adult, from lists, search and suggestions. \
            With a PIN it cannot be turned off, or the PIN changed, without the PIN. It stays on this device.
            """)
        }
    }

    // MARK: - Accounts that sync

    @ViewBuilder
    private var accounts: some View {
        CloudSyncSection()
        if SimklConfig.isConfigured {
            SimklSettingsSection()
        }
    }

    // MARK: - The rest

    private var about: some View {
        Section {
            NavigationLink {
                PlaybackStatisticsView()
            } label: {
                SettingsRow("Playback Statistics", symbol: "chart.bar.fill", tint: .purple)
            }
            NavigationLink {
                AboutView()
            } label: {
                SettingsRow("About Panop", symbol: "info.circle.fill", tint: .blue, value: AboutView.version)
            }
        } header: {
            Text("More")
        } footer: {
            Text("Playback statistics show how fast channels start and how often they stall. They stay on this device.")
        }
    }
}

/// A settings row: a coloured icon tile, the name, and optionally what it is set to. The name is the row's whole
/// accessibility label, with the value after it.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var value: String?

    init(_ title: LocalizedStringKey, symbol: String, tint: Color, value: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(Self.iconFont)
                .foregroundStyle(.white)
                .frame(width: Self.tile, height: Self.tile)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Self.tile * 0.24))
                .accessibilityHidden(true)
            Text(title)
            if let value {
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static var tile: CGFloat {
        #if os(tvOS)
            44
        #else
            28
        #endif
    }

    private static var iconFont: Font {
        #if os(tvOS)
            .callout.weight(.semibold)
        #else
            .footnote.weight(.semibold)
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
