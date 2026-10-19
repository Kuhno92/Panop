import PanopCore
import SwiftUI

/// Hide categories and put the rest in the order wanted. The provider's order is where it starts, and "Reset" returns
/// to
/// it.
///
/// A provider can have hundreds of categories, so nothing here is one at a time only: a filter narrows the list by
/// words,
/// a selection picks any number of them, and the actions (to the top, up, down, to the bottom, hide, show) act on the
/// selection, or on everything the filter shows when nothing is selected. One category still has its own buttons.
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
    @State private var filter = ""
    @State private var selection: Set<String> = []
    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        let order = userState.arranged(providerOrder, kind: kind)
        let hidden = userState.hiddenCategories(of: kind)
        // Hidden as adult content, by the Settings switch: not the person's choice here.
        let locked = userState.hidesAdult ? userState.adultCategories(of: kind) : []
        let shown = CategoryOrder.matching(order, filter: filter)
        let state = Snapshot(
            order: order,
            shown: shown,
            hidden: hidden,
            locked: locked,
            targets: targets(order: order, shown: shown),
            filtering: !filter.trimmingCharacters(in: .whitespaces).isEmpty
        )
        list(state)
            .pageBackdrop()
            .navigationTitle("Categories")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
        #endif
            .searchable(text: $filter, prompt: "Filter categories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "Stop selecting" : "Select") {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing {
                                selection = []
                            }
                        }
                    }
                #endif
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
                } else if loaded, shown.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
    }

    // MARK: - What the actions act on

    /// The selection if there is one, else everything the filter shows: nothing when there is neither, so a button
    /// never
    /// acts on the whole list by surprise.
    private func targets(order: [String], shown: [String]) -> Set<String> {
        let picked = selection.intersection(order)
        if !picked.isEmpty {
            return picked
        }
        return filter.trimmingCharacters(in: .whitespaces).isEmpty ? [] : Set(shown)
    }

    // MARK: - The list

    /// What one pass of the screen works from, read once.
    private struct Snapshot {
        var order: [String]
        var shown: [String]
        var hidden: Set<String>
        var locked: Set<String>
        var targets: Set<String>
        var filtering: Bool
    }

    @ViewBuilder
    private func list(_ state: Snapshot) -> some View {
        #if os(tvOS)
            List { content(state) }
        #else
            List(selection: $selection) { content(state) }
        #endif
    }

    @ViewBuilder
    private func content(_ state: Snapshot) -> some View {
        if loaded, !state.order.isEmpty {
            actions(state)
        }
        Section {
            ForEach(state.shown, id: \.self) { name in
                row(name, state)
                    .tag(name)
            }
            #if !os(tvOS)
            // Drag to place, where the whole list is showing: in a filtered one the places are not the neighbours.
            .onMove(perform: state.filtering ? nil : { from, to in
                var moved = state.order
                moved.move(fromOffsets: from, toOffset: to)
                userState.placeCategories(moved, kind: kind)
            })
            #endif
        } footer: {
            Text("""
            A hidden category is left out of the lists and of search, along with what is in it. \
            Adult categories stay hidden while Hide adult content is on in Settings.
            """)
        }
        Section {
            Button("Reset to the provider's order", role: .destructive) {
                userState.resetCategories(kind: kind)
                selection = []
            }
        }
    }

    // MARK: - Bulk actions

    private func actions(_ state: Snapshot) -> some View {
        let targets = state.targets
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary(targets: targets, filtering: state.filtering))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Menu {
                        Button("To the top", systemImage: "arrow.up.to.line") { toEdge(targets, atTop: true) }
                        Button("Up", systemImage: "arrow.up") { move(targets, by: -1) }
                        Button("Down", systemImage: "arrow.down") { move(targets, by: 1) }
                        Button("To the bottom", systemImage: "arrow.down.to.line") { toEdge(targets, atTop: false) }
                    } label: {
                        Label("Move", systemImage: "arrow.up.arrow.down").pillLabel()
                    }
                    Button {
                        userState.setCategoriesHidden(targets.subtracting(state.locked), hidden: true, kind: kind)
                    } label: {
                        Label("Hide", systemImage: "eye.slash").pillLabel()
                    }
                    Button {
                        userState.setCategoriesHidden(targets.subtracting(state.locked), hidden: false, kind: kind)
                    } label: {
                        Label("Show", systemImage: "eye").pillLabel()
                    }
                }
                .disabled(targets.isEmpty)
                .buttonStyle(.plain)
                if (state.filtering && !state.shown.isEmpty) || !selection.isEmpty {
                    HStack(spacing: 16) {
                        if state.filtering, !state.shown.isEmpty {
                            Button("Select shown") { selection = Set(state.shown) }
                        }
                        if !selection.isEmpty {
                            Button("Clear") { selection = [] }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func summary(targets: Set<String>, filtering: Bool) -> LocalizedStringKey {
        if !selection.isEmpty {
            return "\(targets.count) selected: the buttons act on them."
        }
        if filtering {
            return "\(targets.count) shown by the filter: the buttons act on them."
        }
        return "Select categories, or type in the filter, to move, hide or show several at once."
    }

    private func move(_ names: Set<String>, by step: Int) {
        userState.moveCategories(names, by: step, among: providerOrder, kind: kind)
    }

    private func toEdge(_ names: Set<String>, atTop: Bool) {
        userState.moveCategoriesToEdge(names, atTop: atTop, among: providerOrder, kind: kind)
    }

    // MARK: - One category

    private func row(_ name: String, _ state: Snapshot) -> some View {
        let isHidden = state.hidden.contains(name)
        let index = state.order.firstIndex(of: name) ?? 0
        return HStack(spacing: 12) {
            Text(name)
                .foregroundStyle(isHidden ? .secondary : .primary)
                .strikethrough(isHidden)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { userState.moveCategory(name, by: -1, among: providerOrder, kind: kind) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .accessibilityLabel("Move \(name) up")
            Button { userState.moveCategory(name, by: 1, among: providerOrder, kind: kind) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == state.order.count - 1)
            .accessibilityLabel("Move \(name) down")
            Button {
                userState.setCategoryHidden(!isHidden, name: name, kind: kind)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
            }
            .disabled(state.locked.contains(name))
            .accessibilityLabel(isHidden ? "Show \(name)" : "Hide \(name)")
        }
        .buttonStyle(.borderless)
    }
}
