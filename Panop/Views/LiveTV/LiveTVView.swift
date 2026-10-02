import PanopCore
import SwiftData
import SwiftUI

/// Live channels from every playlist, or from one chosen source.
struct LiveTVView: View {
    @Environment(PlaylistLibrary.self) private var library
    @Environment(SyncStatusCenter.self) private var status
    @Environment(UserStateStore.self) private var userState

    /// Remembered between launches. Anything that is not a current playlist id,
    /// such as a playlist that was since deleted, reads as "all sources".
    @AppStorage("liveSourceFilter") private var storedSource = LiveSourceFilter.allID
    @AppStorage("liveListMode") private var storedMode = LiveListMode.all.rawValue
    @AppStorage("liveSortOrder") private var storedOrder = LiveOrder.name.rawValue
    @State private var search = ""
    @State private var group: String?
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

    private var order: LiveOrder {
        LiveOrder(rawValue: storedOrder) ?? .name
    }

    private var mode: LiveListMode {
        LiveListMode(rawValue: storedMode) ?? .all
    }

    /// What to ask the catalog for. Favourites and recents are not in the catalog, so those
    /// ask for their entry ids; the list then narrows by source and search in memory, which is
    /// cheap for a set that small.
    private var descriptor: FetchDescriptor<CatalogEntryRecord> {
        switch mode {
        case .all:
            LiveChannelQuery.descriptor(
                source: selectedSource?.id,
                search: search,
                limit: limit,
                order: order,
                group: group
            )
        case .favourites:
            LiveChannelQuery.descriptor(restrictedTo: entryIDs(of: Array(userState.favorites)))
        case .recents:
            LiveChannelQuery.descriptor(restrictedTo: entryIDs(of: userState.recents))
        }
    }

    private func entryIDs(of keys: [String]) -> [String] {
        Array(Set(keys.map(UserStateStore.entryID(in:))))
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        LiveChannelList(
            descriptor: descriptor,
            mode: mode,
            modeRaw: $storedMode,
            orderRaw: $storedOrder,
            sourceID: selectedSource?.id,
            search: search,
            sourceNames: Dictionary(uniqueKeysWithValues: library.playlists.map { ($0.id, $0.name) }),
            showsSource: hasSeveralSources && selectedSource == nil,
            emptyState: LiveEmptyState.resolve(
                isSearching: isSearching,
                sources: shownSources,
                hasPlaylists: !library.playlists.isEmpty,
                mode: mode
            ),
            problems: LiveEmptyState.problems(in: shownSources),
            limit: $limit,
            onPlay: {
                userState.markPlayed(UserStateStore.key(playlist: $0.playlist, entry: $0.id))
                playing = PlaybackTarget(entry: $0)
            },
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
            if !library.playlists.isEmpty {
                ToolbarItem { modeMenu }
                ToolbarItem { orderMenu }
                if mode == .all {
                    ToolbarItem { CategoryButton(kind: .live, source: selectedSource?.id, group: $group) }
                }
            }
            if hasSeveralSources {
                ToolbarItem { sourceMenu }
            }
        }
        // A new filter or search starts from the top, not from wherever the last
        // list had been scrolled and grown to.
        .onChange(of: storedSource) {
            limit = LiveChannelQuery.pageSize
            // The category may not exist in the other source.
            group = nil
        }
        .onChange(of: group) { limit = LiveChannelQuery.pageSize }
        .onChange(of: storedMode) { limit = LiveChannelQuery.pageSize }
        .onChange(of: storedOrder) { limit = LiveChannelQuery.pageSize }
        .onChange(of: search) { limit = LiveChannelQuery.pageSize }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .modifier(PlayerPresentation(target: $playing))
    }

    private var modeMenu: some View {
        Menu {
            Picker("Show", selection: $storedMode) {
                ForEach(LiveListMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                }
            }
        } label: {
            Label(mode.title, systemImage: mode.symbol)
        }
        .accessibilityLabel("Show")
    }

    private var orderMenu: some View {
        Menu {
            Picker("Sort", selection: $storedOrder) {
                ForEach(LiveOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } label: {
            Label(order.title, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
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
    @Environment(UserStateStore.self) private var userState

    let mode: LiveListMode
    @Binding var modeRaw: String
    @Binding var orderRaw: String
    let sourceID: String?
    let search: String
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
        mode: LiveListMode,
        modeRaw: Binding<String>,
        orderRaw: Binding<String>,
        sourceID: String?,
        search: String,
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
        self.mode = mode
        _modeRaw = modeRaw
        _orderRaw = orderRaw
        self.sourceID = sourceID
        self.search = search
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
            #if os(tvOS)
                // Apple TV shows no toolbar here, so the filter is the first row instead.
                if emptyState != .noPlaylists {
                    Picker("Show", selection: $modeRaw) {
                        ForEach(LiveListMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Sort", selection: $orderRaw) {
                        ForEach(LiveOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            #endif
            // Channels are showing, but a source behind them could not be updated: say so,
            // and offer the retry, rather than let the list look current.
            if !shown.isEmpty, !problems.isEmpty {
                problemBanner
            }
            ForEach(shown) { channel in
                let key = UserStateStore.key(playlist: channel.playlist, entry: channel.id)
                Button { onPlay(channel) } label: {
                    // A plain button answers only where something is drawn, so the empty
                    // middle of a row would swallow a tap. The whole row is the target, which
                    // is also what Apple TV focus needs.
                    row(channel, isFavorite: userState.isFavorite(key)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { growIfNeeded(at: channel) }
                // Touch and hold (or the remote's long press) on every platform; a swipe too
                // where there is one.
                .contextMenu { favoriteButton(key) }
                #if !os(tvOS)
                    .swipeActions(edge: .leading) { favoriteButton(key).tint(.yellow) }
                #endif
            }
            if channels.count >= LiveChannelQuery.maxRows {
                Text("Showing the first \(LiveChannelQuery.maxRows.formatted()). Search to narrow it down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if shown.isEmpty {
                emptyContent
            }
        }
    }

    /// What the list shows. All channels is the query as it stands. Favourites and recents
    /// were fetched by entry id alone, so they are narrowed here by playlist, the chosen
    /// source and the search, and recents are put in the order they were watched.
    private var shown: [CatalogEntryRecord] {
        switch mode {
        case .all:
            return channels
        case .favourites:
            return channels.filter { matches($0) && userState.isFavorite(key(of: $0)) }
        case .recents:
            let byKey = Dictionary(channels.map { (key(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
            return userState.recents.compactMap { byKey[$0] }.filter { matches($0) }
        }
    }

    private func key(of channel: CatalogEntryRecord) -> String {
        UserStateStore.key(playlist: channel.playlist, entry: channel.id)
    }

    private func matches(_ channel: CatalogEntryRecord) -> Bool {
        if let sourceID, channel.playlist != sourceID {
            return false
        }
        let term = CatalogEntryRecord.nameKey(for: search.trimmingCharacters(in: .whitespacesAndNewlines))
        return term.isEmpty || channel.nameKey.contains(term)
    }

    private func favoriteButton(_ key: String) -> some View {
        let isFavorite = userState.isFavorite(key)
        return Button {
            userState.toggleFavorite(key)
        } label: {
            Label(
                isFavorite ? "Remove from Favourites" : "Add to Favourites",
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
    }

    private func row(_ channel: CatalogEntryRecord, isFavorite: Bool) -> some View {
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
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favourite")
                }
            }
        }
    }

    /// Reaching the last loaded row loads more, until the cap.
    private func growIfNeeded(at channel: CatalogEntryRecord) {
        // Paging belongs to the full list; favourites and recents arrive whole.
        guard mode == .all, channel.id == channels.last?.id, channels.count >= limit else { return }
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
        case .noFavourites:
            ContentUnavailableView(
                "No favourites yet",
                systemImage: "star",
                description: Text("Touch and hold a channel, or swipe it, to add it here.")
            )
        case .noRecents:
            ContentUnavailableView(
                "Nothing watched yet",
                systemImage: "clock",
                description: Text("The channels you watch show up here.")
            )
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

/// Full screen where the platform has it; a window of its own on the Mac.
struct PlayerPresentation: ViewModifier {
    @Binding var target: PlaybackTarget?

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            // A film belongs in a window that can be moved, resized, put on another display and
            // taken full screen, not a sheet that sits on the list. Opening the same item again
            // brings its window forward instead of making a second one.
            content.onChange(of: target) {
                if let target {
                    openWindow(id: PlayerWindow.id, value: PlayerWindowRequest(target))
                    self.target = nil
                }
            }
        #else
            content.fullScreenCover(item: $target) { target in
                PlayerScreen(target: target)
            }
        #endif
    }
}

/// Search. On Apple TV only once there is something to search: before the first playlist its
/// keyboard, half the screen, would sit above a message about adding one.
///
/// Elsewhere it is always there. Switching it on and off changes the view's structure, which
/// rebuilt the screen when the first playlist loaded, and a UI test sometimes found the search
/// field missing afterwards.
private struct ChannelSearch: ViewModifier {
    @Binding var text: String
    let isOffered: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
            if isOffered {
                content.searchable(text: $text, prompt: "Search channels")
            } else {
                content
            }
        #else
            content.searchable(text: $text, prompt: "Search channels")
        #endif
    }
}
