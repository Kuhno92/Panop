import PanopCatalog
import SwiftUI

/// The user's playlists, the state of each one's import, and what can be done to it.
struct PlaylistsView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var status

    @State private var showingAdd = false
    @State private var pendingDelete: PlaylistSummary?
    @State private var deleteError: String?

    var body: some View {
        List {
            ForEach(library.playlists) { playlist in
                PlaylistRow(playlist: playlist, onDelete: { pendingDelete = playlist })
            }
        }
        .pageBackdrop()
        .overlay { emptyState }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh All", systemImage: "arrow.clockwise") {
                    Task { await library.refreshAll() }
                }
                .disabled(library.playlists.isEmpty)
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "playlist")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { playlist in
            Button("Delete", role: .destructive) {
                Task { deleteError = await library.remove(playlist.id) }
            }
        } message: { _ in
            Text("Its channels, movies, series and guide are removed from this device.")
        }
        .alert(
            "Couldn't delete",
            isPresented: Binding(get: { deleteError != nil }, set: {
                if !$0 {
                    deleteError = nil
                }
            })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if library.playlists.isEmpty {
            ContentUnavailableView {
                Label("No playlists", systemImage: "antenna.radiowaves.left.and.right")
            } description: {
                Text("Add an M3U link or file, or an Xtream provider.")
            } actions: {
                Button("Add playlist") { showingAdd = true }
            }
        }
    }
}

/// One playlist: its name, where it comes from, how its last update went, and a
/// menu of what can be done to it.
///
/// The menu is a visible button on purpose. The same actions are on right-click
/// and swipe, but neither can be discovered by looking, and swipe does not exist
/// for a mouse.
struct PlaylistRow: View {
    let playlist: PlaylistSummary
    let onDelete: () -> Void

    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var statusCenter
    @State private var removalToReview: DeferredRemoval?

    private var isRemoving: Bool {
        library.removing.contains(playlist.id)
    }

    private var isSyncing: Bool {
        if case .syncing = statusCenter.status(for: playlist.id) {
            true
        } else {
            false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if isRemoving {
                    Text("Deleting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    statusLine(statusCenter.status(for: playlist.id))
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
        .opacity(isRemoving ? 0.5 : 1)
        .disabled(isRemoving)
        .contextMenu { actions }
        #if !os(tvOS)
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        #endif
            .alert(
                "Remove missing items?",
                isPresented: Binding(get: { removalToReview != nil }, set: {
                    if !$0 {
                        removalToReview = nil
                    }
                }),
                presenting: removalToReview
            ) { removal in
                Button("Remove \(removal.ids.count)", role: .destructive) {
                    Task { try? await library.confirm(removal, playlist: playlist.id) }
                }
                Button("Keep them", role: .cancel) {}
            } message: { removal in
                Text("""
                The provider's latest list is missing \(removal.ids.count) items. \
                That can mean the download was cut off. \
                Removing them also removes any favourites and watch progress on them.
                """)
            }
    }

    // MARK: - Actions

    @ViewBuilder
    private var trailing: some View {
        if isRemoving {
            ProgressView()
        } else {
            HStack(spacing: 8) {
                if isSyncing {
                    ProgressView()
                }
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
                .accessibilityLabel("Actions for \(playlist.name)")
            }
        }
    }

    /// Shared by the menu button and the right-click menu, so they cannot drift.
    @ViewBuilder
    private var actions: some View {
        if isSyncing {
            Button("Stop Updating", systemImage: "stop.circle") {
                Task { await library.stop(playlist.id) }
            }
        } else {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await library.refresh(playlist.id) }
            }
            Button("Re-import Everything", systemImage: "arrow.triangle.2.circlepath") {
                Task { await library.refresh(playlist.id, force: true) }
            }
        }
        Divider()
        if playlist.includesVOD {
            Button("Live TV Only", systemImage: "tv") {
                Task { await library.setIncludesVOD(false, for: playlist.id) }
            }
        } else {
            Button("Include Movies and Series", systemImage: "film") {
                Task { await library.setIncludesVOD(true, for: playlist.id) }
            }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
    }

    // MARK: - Status

    private var subtitle: String {
        let source = switch playlist.kind {
        case .xtream: String(localized: "Xtream · \(playlist.displayHost)")
        case .remoteM3U: String(localized: "M3U · \(playlist.displayHost)")
        case .localM3U: String(localized: "M3U file")
        }
        return playlist.includesVOD ? source : source + String(localized: " · Live TV only")
    }

    @ViewBuilder
    private func statusLine(_ status: SyncStatus) -> some View {
        switch status {
        case .idle:
            Text("Not updated yet").font(.caption).foregroundStyle(.secondary)
        case let .syncing(processed):
            Text(processed == 0 ? "Getting the list…" : "Importing… \(processed.formatted()) items")
                .font(.caption).foregroundStyle(.secondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        case let .finished(summary):
            finishedLines(summary)
        }
    }

    @ViewBuilder
    private func finishedLines(_ summary: SyncSummary) -> some View {
        Text(finishedText(summary)).font(.caption).foregroundStyle(.secondary)

        ForEach(summary.failedSections, id: \.self) { failure in
            Label(failure, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
        if summary.skipped > 0 {
            // Not an error: the rest imported. But a person whose channel count is lower than
            // the file's should be told why.
            Label(
                summary.skipped == 1
                    ? "One entry was left out: no address to play."
                    : "\(summary.skipped.formatted()) entries were left out: no address to play.",
                systemImage: "info.circle"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        if summary.guide == .failed {
            Label("The TV guide could not be loaded.", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        }
        if let removal = summary.heldBack.first {
            Button {
                removalToReview = removal
            } label: {
                Label(
                    "\(summary.heldBackCount) items are missing from the provider. Review",
                    systemImage: "questionmark.circle"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private func finishedText(_ summary: SyncSummary) -> String {
        let when = summary.finishedAt.formatted(.relative(presentation: .named))
        return summary.unchanged
            ? String(localized: "Up to date · checked \(when)")
            : String(localized: "\(summary.entries.formatted()) items · updated \(when)")
    }
}
