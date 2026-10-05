import PanopCore
import SwiftUI

/// What the person has hidden, with a way to show each again.
struct HiddenEntriesView: View {
    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog
    @State private var model = CatalogListModel()

    /// The catalog is asked for these entry ids; an id can repeat across playlists, so the rows
    /// are then narrowed to the keys that are really hidden.
    private var spec: ListSpec {
        ListSpec(kind: nil, restrictedTo: Array(Set(userState.hidden.map(UserStateStore.entryID(in:)))))
    }

    private var shown: [CatalogRow] {
        model.rows.filter { userState.isHidden($0.id) }
    }

    var body: some View {
        List(shown) { row in
            HStack(spacing: 12) {
                ChannelLogo(address: row.iconURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                    Text(Self.kind(row.kind)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Show") { userState.setHidden(false, for: row.id) }
            }
        }
        .pageBackdrop()
        .overlay {
            if shown.isEmpty, model.phase == .loaded {
                ContentUnavailableView(
                    "Nothing hidden",
                    systemImage: "eye",
                    description: Text("Hide a channel or film from its menu, and it is listed here.")
                )
            }
        }
        .navigationTitle("Hidden")
        .task(id: spec) { model.show(spec, in: catalog.container) }
    }

    private static func kind(_ kind: MediaKind) -> String {
        switch kind {
        case .live: String(localized: "Channel")
        case .movie: String(localized: "Movie")
        case .series: String(localized: "Series")
        case .unknown: ""
        }
    }
}
