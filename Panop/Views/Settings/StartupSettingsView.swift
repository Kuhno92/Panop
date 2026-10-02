import PanopCore
import SwiftData
import SwiftUI

/// Settings for what the app does when it opens.
struct StartupSection: View {
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
        Section {
            Picker("When Panop opens", selection: action) {
                ForEach(choices) { Text($0.title).tag($0) }
            }
            if action.wrappedValue == .channel {
                NavigationLink {
                    StartupChannelPicker { channel in
                        channelKey = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
                        channelName = channel.name
                    }
                } label: {
                    LabeledContent("Channel", value: channelName.isEmpty ? "Choose…" : channelName)
                }
            }
        } header: {
            Text("Startup")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch action.wrappedValue {
        case .channel:
            "The channel starts playing as soon as Panop opens, from what is already on this device."
        default:
            "The screen Panop opens on."
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
