import PanopCore
import SwiftData
import SwiftUI

/// What the app does when it opens: the rows of the choice, for the Playing section of Settings.
struct StartupPicker: View {
    @AppStorage(StartupPreference.actionKey) private var actionRaw = StartupAction.home.rawValue
    @AppStorage(StartupPreference.channelKey) private var channelKey = ""
    @AppStorage(StartupPreference.channelNameKey) private var channelName = ""

    @Environment(PlaylistLibrary.self) private var library

    private var action: Binding<StartupAction> {
        Binding(
            get: { StartupAction(rawValue: actionRaw) ?? .home },
            set: { actionRaw = $0.rawValue }
        )
    }

    /// Movies and Series only while some source has them.
    private var choices: [StartupAction] {
        StartupAction.allCases.filter { library.offersVOD || !$0.needsVOD }
    }

    var body: some View {
        Picker(selection: action) {
            ForEach(choices) { Text($0.title).tag($0) }
        } label: {
            SettingsRow("When Panop opens", symbol: "power", tint: .mint)
        }
        if action.wrappedValue == .channel {
            NavigationLink {
                StartupChannelPicker { channel in
                    channelKey = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
                    channelName = channel.name
                }
            } label: {
                SettingsRow(
                    "Channel",
                    symbol: "tv",
                    tint: .mint,
                    value: channelName.isEmpty ? String(localized: "Choose…") : channelName
                )
            }
        }
    }
}

/// A searchable list of live channels, to pick the one to start with.
struct StartupChannelPicker: View {
    let onPick: (CatalogEntryRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        StartupChannelList(search: search) { channel in
            onPick(channel)
            dismiss()
        }
        .navigationTitle("Startup channel")
        .searchable(text: $search, prompt: "Search channels")
    }
}

private struct StartupChannelList: View {
    @Query private var channels: [CatalogEntryRecord]
    let onPick: (CatalogEntryRecord) -> Void

    init(search: String, onPick: @escaping (CatalogEntryRecord) -> Void) {
        self.onPick = onPick
        // Bounded and indexed like the Live TV list: a catalog can hold tens of thousands.
        _channels = Query(LiveChannelQuery.descriptor(
            source: nil,
            search: search,
            limit: LiveChannelQuery.pageSize
        ))
    }

    var body: some View {
        List(channels) { channel in
            Button(channel.name) { onPick(channel) }
        }
        .overlay {
            if channels.isEmpty {
                ContentUnavailableView("No channels", systemImage: "tv")
            }
        }
    }
}
