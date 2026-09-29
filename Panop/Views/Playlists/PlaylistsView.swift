import PanopCatalog
import SwiftUI

/// The user's playlists and the state of each one's import.
struct PlaylistsView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var status

    @State private var showingAdd = false
    @State private var pendingDelete: PlaylistSummary?

    var body: some View {
        List {
            ForEach(library.playlists) { playlist in
                PlaylistRow(playlist: playlist, onDelete: { pendingDelete = playlist })
            }
        }
        .overlay {
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
        .navigationTitle("Playlists")
        .toolbar {
            Button("Add", systemImage: "plus") { showingAdd = true }
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
                Task { await library.remove(playlist.id) }
            }
        } message: { _ in
            Text("Its channels, movies, series and guide are removed from this device.")
        }
    }
}

private struct PlaylistRow: View {
    let playlist: PlaylistSummary
    let onDelete: () -> Void

    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var statusCenter
    @State private var removalToReview: DeferredRemoval?

    var body: some View {
        let status = statusCenter.status(for: playlist.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(playlist.name).font(.headline)
                Spacer()
                if case .syncing = status {
                    ProgressView()
                }
            }
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            statusLine(status)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await library.refresh(playlist.id) } }
            Button("Re-import everything", systemImage: "arrow.triangle.2.circlepath") {
                Task { await library.refresh(playlist.id, force: true) }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        #if !os(tvOS)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await library.refresh(playlist.id) } }
                .tint(.blue)
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
            Text(
                "The provider's latest list is missing \(removal.ids.count) items. "
                    + "That can mean the download was cut off. "
                    + "Removing them also removes any favourites and watch progress on them."
            )
        }
    }

    private var subtitle: String {
        switch playlist.kind {
        case .xtream: "Xtream · \(playlist.displayHost)"
        case .remoteM3U: "M3U · \(playlist.displayHost)"
        case .localM3U: "M3U file"
        }
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
        Text(summary
            .unchanged ? "Up to date" :
            "\(summary.entries.formatted()) items · updated \(summary.finishedAt.formatted(.relative(presentation: .named)))")
            .font(.caption).foregroundStyle(.secondary)

        ForEach(summary.failedSections, id: \.self) { failure in
            Label(failure, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
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
}
