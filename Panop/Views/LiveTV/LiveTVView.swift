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

    /// The sources on screen: the chosen one, or all of them.
    private var shownSources: [LiveEmptyState.Source] {
        let playlists = selectedSource.map { [$0] } ?? library.playlists
        return playlists.map { LiveEmptyState.Source(id: $0.id, name: $0.name, status: status.status(for: $0.id)) }
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        LiveChannelList(
            descriptor: LiveChannelQuery.descriptor(source: selectedSource?.id, search: search, limit: limit),
            sourceNames: Dictionary(uniqueKeysWithValues: library.playlists.map { ($0.id, $0.name) }),
            showsSource: hasSeveralSources && selectedSource == nil,
            emptyState: LiveEmptyState.resolve(
                isSearching: isSearching,
                sources: shownSources,
                hasPlaylists: !library.playlists.isEmpty
            ),
            problems: LiveEmptyState.problems(in: shownSources),
            limit: $limit,
            onPlay: { playing = PlaybackTarget(entry: $0) },
            onAdd: { showingAdd = true },
            onRetry: { ids in
                Task {
                    for id in ids {
                        await library.refresh(id)
                    }
                }
            }
        )
        .navigationTitle(selectedSource?.name ?? "Live TV")
        .modifier(ChannelSearch(text: $search, isOffered: !library.playlists.isEmpty))
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
    let emptyState: LiveEmptyState
    let problems: [LiveEmptyState.Problem]
    @Binding var limit: Int
    let onPlay: (CatalogEntryRecord) -> Void
    let onAdd: () -> Void
    let onRetry: ([String]) -> Void

    init(
        descriptor: FetchDescriptor<CatalogEntryRecord>,
        sourceNames: [String: String],
        showsSource: Bool,
        emptyState: LiveEmptyState,
        problems: [LiveEmptyState.Problem],
        limit: Binding<Int>,
        onPlay: @escaping (CatalogEntryRecord) -> Void,
        onAdd: @escaping () -> Void,
        onRetry: @escaping ([String]) -> Void
    ) {
        _channels = Query(descriptor)
        self.sourceNames = sourceNames
        self.showsSource = showsSource
        self.emptyState = emptyState
        self.problems = problems
        _limit = limit
        self.onPlay = onPlay
        self.onAdd = onAdd
        self.onRetry = onRetry
    }

    var body: some View {
        List {
            // Channels are showing, but a source behind them could not be updated: say so,
            // and offer the retry, rather than let the list look current.
            if !channels.isEmpty, !problems.isEmpty {
                problemBanner
            }
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
        .overlay {
            if channels.isEmpty {
                emptyContent
            }
        }
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
            HStack(spacing: 12) {
                ChannelLogo(address: channel.iconURL)
                Text(channel.name)
            }
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

    private var problemBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                problems.count == 1
                    ? "\(problems[0].name) couldn't be updated"
                    : "\(problems.count) sources couldn't be updated",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            if problems.count == 1 {
                Text(problems[0].message).font(.footnote).foregroundStyle(.secondary)
            }
            Button("Try again") { onRetry(problems.map(\.id)) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch emptyState {
        case .searchFoundNothing:
            ContentUnavailableView.search
        case .syncing:
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Getting your channels…")
            }
        case let .failed(problems):
            ContentUnavailableView {
                Label("Couldn't load channels", systemImage: "exclamationmark.triangle")
            } description: {
                Text(problems.count == 1
                    ? "\(problems[0].message)"
                    : problems.map { "\($0.name): \($0.message)" }.joined(separator: "\n"))
            } actions: {
                Button("Try again") { onRetry(problems.map(\.id)) }
            }
        case .noLiveChannels:
            ContentUnavailableView(
                "No live channels",
                systemImage: "tv",
                description: Text("This source loaded, but has no live channels. It may only hold movies or series.")
            )
        case .noPlaylists:
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

/// Search, once there is something to search. Before the first playlist it would only put a
/// keyboard, half the screen on Apple TV, above a message about adding one.
private struct ChannelSearch: ViewModifier {
    @Binding var text: String
    let isOffered: Bool

    func body(content: Content) -> some View {
        if isOffered {
            content.searchable(text: $text, prompt: "Search channels")
        } else {
            content
        }
    }
}
