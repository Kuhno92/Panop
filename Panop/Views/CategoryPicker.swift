import PanopCore
import SwiftData
import SwiftUI

/// The button that narrows a list to one category, and the searchable list it opens.
///
/// A sheet rather than a menu: a provider can have hundreds of categories, and a menu of that
/// size neither scrolls well nor can be searched.
struct CategoryButton: View {
    let kind: MediaKind
    /// One source's categories, or nil for every source's.
    let source: String?
    @Binding var group: String?

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(group ?? "All categories", systemImage: "square.grid.2x2")
        }
        .accessibilityLabel("Category")
        .accessibilityValue(group ?? "All categories")
        .sheet(isPresented: $showing) {
            NavigationStack {
                CategoryPickerList(kind: kind, source: source, selection: $group)
            }
        }
    }
}

private struct CategoryPickerList: View {
    let kind: MediaKind
    let source: String?
    @Binding var selection: String?

    @Environment(\.modelContext) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String] = []
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
            .task { names = LiveChannelQuery.categoryNames(kind: kind, source: source, in: catalog) }
            .overlay {
                if names.isEmpty {
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
