import PanopCore
import SwiftData
import SwiftUI

/// The searchable list of categories, for a provider with too many for a row of chips.
struct CategoryPickerList: View {
    let kind: MediaKind
    let source: String?
    @Binding var selection: String?

    @Environment(\.modelContext) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
    @State private var loaded = false
    @State private var search = ""

    /// Filtered here, not in `body` on every render: the names change only with the search.
    private var shown: [String] {
        let term = CatalogEntryRecord.nameKey(for: search.trimmingCharacters(in: .whitespaces))
        return term.isEmpty ? names : names.filter { CatalogEntryRecord.nameKey(for: $0).contains(term) }
    }

    var body: some View {
        List {
            if search.isEmpty {
                row("All categories", value: nil)
            }
            ForEach(shown, id: \.self) { row($0, value: $0) }
        }
        .navigationTitle("Category")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .searchable(text: $search, prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                names = await CatalogReader(container: catalog.container).categoryNames(kind: kind, source: source)
                loaded = true
            }
            .overlay {
                if loaded, names.isEmpty {
                    ContentUnavailableView(
                        "No categories",
                        systemImage: "square.grid.2x2",
                        description: Text("This source does not group its content.")
                    )
                }
            }
    }

    private func row(_ title: String, value: String?) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The provider's categories as a row of chips, in the order the provider lists them, so a
/// list can be narrowed with one tap and the grouping the provider chose is in plain sight.
///
/// Nothing is drawn for a source with one category or none. A provider with many gets the
/// searchable list as well, at the end of the row.
struct CategoryChips: View {
    let kind: MediaKind
    /// One source's categories, or nil for every source's.
    let source: String?
    @Binding var group: String?

    @Environment(\.modelContext) private var catalog
    @Environment(SyncStatusCenter.self) private var status
    @Environment(UserStateStore.self) private var userState
    /// Every category, in the provider's order. What is shown is these, arranged and narrowed
    /// by what the person chose.
    @State private var names: [String] = []
    @State private var sheet: Sheet?

    /// The two ways into the categories beyond the chips themselves.
    private enum Sheet: String, Identifiable {
        case editor, list

        var id: String {
            rawValue
        }
    }

    private var shown: [String] {
        userState.visibleCategories(names, kind: kind)
    }

    /// Past this many the row is a long scroll, and the searchable list is the better way in.
    private static let listThreshold = 12

    private struct Load: Hashable {
        var kind: MediaKind
        var source: String?
        /// Re-read when an import finishes, which is when categories arrive or change.
        var syncing: Bool
    }

    var body: some View {
        // The `ZStack` and its zero-height spacer are what the modifiers below attach to. On a
        // view that is empty until the categories arrive, `task` never runs, so they never would.
        ZStack {
            Color.clear.frame(height: 0)
            if names.count > 1 {
                HStack(spacing: Self.spacing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.spacing) {
                            chip("All", value: nil)
                            ForEach(shown, id: \.self) { chip($0, value: $0) }
                        }
                        .padding(.leading)
                        .padding(.vertical, Self.verticalRoom)
                    }
                    // Outside the scrolling row, so they are in view however far it is scrolled.
                    HStack(spacing: Self.spacing) {
                        if shown.count > Self.listThreshold {
                            Button { sheet = .list } label: {
                                Image(systemName: "list.bullet")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("All categories")
                        }
                        Button { sheet = .editor } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Edit categories")
                    }
                    .padding(.trailing)
                    .padding(.vertical, Self.verticalRoom)
                }
            }
        }
        .task(id: Load(kind: kind, source: source, syncing: status.isAnySyncing)) {
            names = await CatalogReader(container: catalog.container).categoryNames(kind: kind, source: source)
            // A category chosen earlier may not exist here.
            if let group, !names.contains(group) {
                self.group = nil
            }
        }
        // A category that was just hidden cannot stay chosen.
        .onChange(of: userState.hiddenCategories(of: kind)) {
            if let group, userState.hiddenCategories(of: kind).contains(group) {
                self.group = nil
            }
        }
        // One sheet for both, so which is shown is never in doubt. Each reads the categories
        // itself rather than being handed what this view had when it was drawn.
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .editor: CategoryEditor(kind: kind, source: source)
                case .list: CategoryPickerList(kind: kind, source: source, selection: $group)
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 520)
            #endif
        }
    }

    @ViewBuilder
    private func chip(_ title: String, value: String?) -> some View {
        let selected = group == value
        if selected {
            Button { group = value } label: { Text(title).lineLimit(1) }
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button { group = value } label: { Text(title).lineLimit(1) }
                .buttonStyle(.bordered)
        }
    }

    private static var spacing: CGFloat {
        #if os(tvOS)
            24
        #else
            8
        #endif
    }

    /// A focused chip on Apple TV grows, and the row would clip it.
    private static var verticalRoom: CGFloat {
        #if os(tvOS)
            16
        #else
            6
        #endif
    }
}

/// Hide categories and put the rest in the order wanted. The provider's order is where it starts,
/// and "Reset" returns to it.
struct CategoryEditor: View {
    let kind: MediaKind
    /// One source's categories, or nil for every source's.
    let source: String?

    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog
    @Environment(\.dismiss) private var dismiss
    /// Every category, in the provider's order.
    @State private var providerOrder: [String] = []
    @State private var loaded = false

    var body: some View {
        let order = userState.arranged(providerOrder, kind: kind)
        let hidden = userState.hiddenCategories(of: kind)
        List {
            Section {
                ForEach(Array(order.enumerated()), id: \.element) { index, name in
                    HStack(spacing: 12) {
                        Text(name)
                            .foregroundStyle(hidden.contains(name) ? .secondary : .primary)
                            .strikethrough(hidden.contains(name))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { userState.moveCategory(name, by: -1, among: providerOrder, kind: kind) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(name) up")
                        Button { userState.moveCategory(name, by: 1, among: providerOrder, kind: kind) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == order.count - 1)
                        .accessibilityLabel("Move \(name) down")
                        Button {
                            userState.setCategoryHidden(!hidden.contains(name), name: name, kind: kind)
                        } label: {
                            Image(systemName: hidden.contains(name) ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(hidden.contains(name) ? "Show \(name)" : "Hide \(name)")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("A hidden category is left out of the lists and of search, along with what is in it.")
            }
            Section {
                Button("Reset to the provider's order", role: .destructive) {
                    userState.resetCategories(kind: kind)
                }
            }
        }
        .navigationTitle("Categories")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                providerOrder = await CatalogReader(container: catalog.container)
                    .categoryNames(kind: kind, source: source)
                loaded = true
            }
            .overlay {
                if loaded, order.isEmpty {
                    ContentUnavailableView(
                        "No categories",
                        systemImage: "square.grid.2x2",
                        description: Text("This source does not group its content.")
                    )
                }
            }
    }
}
