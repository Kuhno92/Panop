import PanopCore
import SwiftData
import SwiftUI

/// Live channels from every playlist, or from one chosen source.
struct LiveTVView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var status

    /// Remembered between launches. Anything that is not a current playlist id,
    /// such as a playlist that was since deleted, reads as "all sources".
    @AppStorage("liveSourceFilter") private var storedSource = LiveSourceFilter.allID
    @State private var search = ""
    @State private var limit = LiveChannelQuery.pageSize
    @State private var showingAdd = false
    @State private var playing: PlaybackTarget?

    private var selectedSource: PlaylistSummary? {
        library.playlists.first { $0.id == storedSource }
    }

    private var hasSeveralSources: Bool {
        library.playlists.count > 1
    }

    var body: some View {
        LiveChannelList(
            descriptor: LiveChannelQuery.descriptor(source: selectedSource?.id, search: search, limit: limit),
            sourceNames: Dictionary(uniqueKeysWithValues: library.playlists.map { ($0.id, $0.name) }),
            showsSource: hasSeveralSources && selectedSource == nil,
            isSearching: !search.trimmingCharacters(in: .whitespaces).isEmpty,
            hasPlaylists: !library.playlists.isEmpty,
            isSyncing: status.isAnySyncing,
            limit: $limit,
            onPlay: { playing = PlaybackTarget(entry: $0) },
            onAdd: { showingAdd = true }
        )
        .navigationTitle(selectedSource?.name ?? "Live TV")
        .searchable(text: $search, prompt: "Search channels")
        .toolbar {
            if hasSeveralSources {
                ToolbarItem { sourceMenu }
            }
        }
        // A new filter or search starts from the top, not from wherever the last
        // list had been scrolled and grown to.
        .onChange(of: storedSource) { limit = LiveChannelQuery.pageSize }
        .onChange(of: search) { limit = LiveChannelQuery.pageSize }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .modifier(PlayerPresentation(target: $playing))
    }

    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $storedSource) {
                Text("All sources").tag(LiveSourceFilter.allID)
                ForEach(library.playlists) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
        } label: {
            Label(selectedSource?.name ?? "All sources", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

/// The list itself. Its `@Query` is rebuilt whenever the descriptor changes, which
/// is how the source, the search and the growing page reach the database.
private struct LiveChannelList: View {
    @Query private var channels: [CatalogEntryRecord]

    let sourceNames: [String: String]
    let showsSource: Bool
    let isSearching: Bool
    let hasPlaylists: Bool
    let isSyncing: Bool
    @Binding var limit: Int
    let onPlay: (CatalogEntryRecord) -> Void
    let onAdd: () -> Void

    init(
        descriptor: FetchDescriptor<CatalogEntryRecord>,
        sourceNames: [String: String],
        showsSource: Bool,
        isSearching: Bool,
        hasPlaylists: Bool,
        isSyncing: Bool,
        limit: Binding<Int>,
        onPlay: @escaping (CatalogEntryRecord) -> Void,
        onAdd: @escaping () -> Void
    ) {
        _channels = Query(descriptor)
        self.sourceNames = sourceNames
        self.showsSource = showsSource
        self.isSearching = isSearching
        self.hasPlaylists = hasPlaylists
        self.isSyncing = isSyncing
        _limit = limit
        self.onPlay = onPlay
        self.onAdd = onAdd
    }

    var body: some View {
        List {
            ForEach(channels) { channel in
                Button { onPlay(channel) } label: { row(channel) }
                    .buttonStyle(.plain)
                    .onAppear { growIfNeeded(at: channel) }
            }
            if channels.count >= LiveChannelQuery.maxRows {
                Text("Showing the first \(LiveChannelQuery.maxRows.formatted()). Search to narrow it down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay { emptyState }
    }

    private func row(_ channel: CatalogEntryRecord) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                if let group = channel.groupName {
                    Text(group)
                }
                if showsSource, let source = sourceNames[channel.playlist] {
                    Text(source).font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        } label: {
            Text(channel.name)
        }
    }

    /// Reaching the last loaded row loads more, until the cap.
    private func growIfNeeded(at channel: CatalogEntryRecord) {
        guard channel.id == channels.last?.id, channels.count >= limit else { return }
        let next = LiveChannelQuery.nextLimit(after: limit)
        if next != limit {
            limit = next
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if channels.isEmpty {
            if isSearching {
                ContentUnavailableView.search
            } else if isSyncing {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("Getting your channels…")
                }
            } else if hasPlaylists {
                ContentUnavailableView(
                    "No channels",
                    systemImage: "tv",
                    description: Text("This source has no live channels yet.")
                )
            } else {
                ContentUnavailableView {
                    Label("No playlist yet", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Add an M3U playlist or Xtream provider to get started.")
                } actions: {
                    Button("Add playlist", action: onAdd)
                }
            }
        }
    }
}

extension PlaybackTarget {
    /// A snapshot of a catalog row, so the player never holds the live record.
    init(entry: CatalogEntryRecord) {
        self.init(
            playlist: entry.playlist,
            entryID: entry.id,
            kind: entry.kind,
            name: entry.name,
            streamURL: entry.streamURL,
            remoteID: entry.remoteID,
            containerExtension: entry.containerExtension
        )
    }
}

/// Full screen where the platform has it; a sheet on the Mac.
private struct PlayerPresentation: ViewModifier {
    @Binding var target: PlaybackTarget?

    func body(content: Content) -> some View {
        #if os(macOS)
            content.sheet(item: $target) { target in
                PlayerScreen(target: target).frame(minWidth: 880, minHeight: 520)
            }
        #else
            content.fullScreenCover(item: $target) { target in
                PlayerScreen(target: target)
            }
        #endif
    }
}
