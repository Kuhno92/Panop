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
    @AppStorage("liveSortOrder") private var storedOrder = LiveOrder.provider.rawValue
    @State private var search = ""
    @State private var searchOpen = false
    @State private var group: String?
    @State private var showingAdd = false
    @State private var playing: PlaybackTarget?
    @State private var showingGuide = false

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
        LiveOrder(rawValue: storedOrder) ?? .provider
    }

    private var mode: LiveListMode {
        LiveListMode(rawValue: storedMode) ?? .all
    }

    /// What to ask the catalog for. Favourites and recents are not in the catalog, so those
    /// ask for their entry ids; the list then narrows by source and search in memory, which is
    /// cheap for a set that small.
    private var spec: ListSpec {
        switch mode {
        case .all:
            ListSpec(
                kind: .live,
                source: selectedSource?.id,
                search: search,
                order: order,
                group: group,
                hidden: userState.hidden,
                hiddenGroups: userState.hiddenCategories(of: .live)
            )
        case .favourites:
            ListSpec(
                kind: .live,
                restrictedTo: entryIDs(of: Array(userState.favorites)),
                hidden: userState.hidden,
                hiddenGroups: userState.hiddenCategories(of: .live)
            )
        case .recents:
            ListSpec(
                kind: .live,
                restrictedTo: entryIDs(of: userState.recents),
                hidden: userState.hidden,
                hiddenGroups: userState.hiddenCategories(of: .live)
            )
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
            spec: spec,
            group: $group,
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
            onPlay: {
                userState.markPlayed($0.id)
                playing = PlaybackTarget(row: $0)
            },
            onPlayTarget: { playing = $0 },
            onAdd: { showingAdd = true },
            onShowGuide: { showingGuide = true },
            onRetry: { ids in
                Task {
                    for id in ids {
                        await library.refresh(id)
                    }
                }
            }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            // Apple TV has no room above its list, so there the chips are the list's first row.
            #if !os(tvOS)
                if mode == .all, !library.playlists.isEmpty {
                    CategoryChips(kind: .live, source: selectedSource?.id, group: $group)
                }
            #endif
        }
        .navigationTitle(selectedSource?.name ?? "Live TV")
        .modifier(ChannelSearch(text: $search, isOpen: $searchOpen, isOffered: !library.playlists.isEmpty))
        .toolbar {
            if !library.playlists.isEmpty {
                ToolbarItem {
                    Button("TV Guide", systemImage: "calendar") { showingGuide = true }
                }
                ToolbarItem { modeMenu }
                ToolbarItem { orderMenu }
            }
            if hasSeveralSources {
                ToolbarItem { sourceMenu }
            }
        }
        // The category may not exist in the other source.
        .onChange(of: storedSource) { group = nil }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .modifier(GuidePresentation(isPresented: $showingGuide) {
            GuideGridView(spec: spec, narrow: {
                LiveListNarrowing.rows(
                    $0, mode: mode, sourceID: selectedSource?.id, search: search, userState: userState
                )
            })
        })
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
                ForEach(LiveOrder.forChannels) { order in
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

/// What a Live TV list shows out of the rows read for it. All channels is the list as read. Favourites and
/// recents were read by entry id alone, so they are narrowed by playlist, the chosen source and the search,
/// and recents are put in the order they were watched. The guide grid uses the same, so it shows the channels
/// the list does.
@MainActor
enum LiveListNarrowing {
    static func rows(
        _ rows: [CatalogRow],
        mode: LiveListMode,
        sourceID: String?,
        search: String,
        userState: UserStateStore
    ) -> [CatalogRow] {
        func matches(_ channel: CatalogRow) -> Bool {
            if let sourceID, channel.playlist != sourceID {
                return false
            }
            let term = CatalogEntryRecord.nameKey(for: search.trimmingCharacters(in: .whitespacesAndNewlines))
            return term.isEmpty || channel.nameKey.contains(term)
        }
        switch mode {
        case .all:
            return rows
        case .favourites:
            return rows.filter { matches($0) && userState.isFavorite($0.id) }
        case .recents:
            let byKey = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return userState.recents.compactMap { byKey[$0] }.filter { matches($0) }
        }
    }
}

/// The list itself. Its `@Query` is rebuilt whenever the descriptor changes, which
/// is how the source, the search and the growing page reach the database.
private struct LiveChannelList: View {
    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog
    @State private var model = CatalogListModel()
    @State private var guideFor: CatalogRow?

    let mode: LiveListMode
    @Binding var modeRaw: String
    @Binding var orderRaw: String
    let sourceID: String?
    let search: String
    let sourceNames: [String: String]
    let showsSource: Bool
    let emptyState: LiveEmptyState
    let problems: [LiveEmptyState.Problem]
    let spec: ListSpec
    @Binding var group: String?
    let onPlay: (CatalogRow) -> Void
    let onPlayTarget: (PlaybackTarget) -> Void
    let onAdd: () -> Void
    let onShowGuide: () -> Void
    let onRetry: ([String]) -> Void

    init(
        spec: ListSpec,
        group: Binding<String?>,
        mode: LiveListMode,
        modeRaw: Binding<String>,
        orderRaw: Binding<String>,
        sourceID: String?,
        search: String,
        sourceNames: [String: String],
        showsSource: Bool,
        emptyState: LiveEmptyState,
        problems: [LiveEmptyState.Problem],
        onPlay: @escaping (CatalogRow) -> Void,
        onPlayTarget: @escaping (PlaybackTarget) -> Void,
        onAdd: @escaping () -> Void,
        onShowGuide: @escaping () -> Void,
        onRetry: @escaping ([String]) -> Void
    ) {
        self.spec = spec
        _group = group
        self.mode = mode
        _modeRaw = modeRaw
        _orderRaw = orderRaw
        self.sourceID = sourceID
        self.search = search
        self.sourceNames = sourceNames
        self.showsSource = showsSource
        self.emptyState = emptyState
        self.problems = problems
        self.onPlay = onPlay
        self.onPlayTarget = onPlayTarget
        self.onAdd = onAdd
        self.onShowGuide = onShowGuide
        self.onRetry = onRetry
    }

    var body: some View {
        List {
            #if os(tvOS)
                // Apple TV shows no toolbar here, so the filter is the first row instead.
                if emptyState != .noPlaylists {
                    Button("TV Guide", systemImage: "calendar", action: onShowGuide)
                    Picker("Show", selection: $modeRaw) {
                        ForEach(LiveListMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Sort", selection: $orderRaw) {
                        ForEach(LiveOrder.forChannels) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if mode == .all {
                        CategoryChips(kind: .live, source: sourceID, group: $group)
                            .listRowInsets(EdgeInsets())
                    }
                }
            #endif
            // Channels are showing, but a source behind them could not be updated: say so,
            // and offer the retry, rather than let the list look current.
            if !shown.isEmpty, !problems.isEmpty {
                problemBanner
            }
            ForEach(shown) { channel in
                let key = channel.id
                Button { onPlay(channel) } label: {
                    // A plain button answers only where something is drawn, so the empty
                    // middle of a row would swallow a tap. The whole row is the target, which
                    // is also what Apple TV focus needs.
                    row(channel, isFavorite: userState.isFavorite(key)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { model.rowAppeared(channel) }
                // Touch and hold (or the remote's long press) on every platform; a swipe too
                // where there is one.
                .contextMenu {
                    favoriteButton(key)
                    Button("Programme Guide", systemImage: "calendar") { guideFor = channel }
                    Button("Hide Channel", systemImage: "eye.slash") { userState.setHidden(true, for: key) }
                }
                #if !os(tvOS)
                .swipeActions(edge: .leading) { favoriteButton(key).tint(.yellow) }
                #endif
            }
            if model.rows.count >= LiveChannelQuery.maxRows {
                Text("Showing the first \(LiveChannelQuery.maxRows.formatted()). Search to narrow it down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            // Not while the first page is still being read: an empty list is not a list with
            // nothing in it until the catalog has answered.
            if shown.isEmpty, model.phase == .loaded {
                emptyContent
            }
        }
        .task(id: spec) { model.show(spec, in: catalog.container) }
        .sheet(item: $guideFor) { channel in
            NavigationStack {
                ChannelGuideView(channel: channel, onPlay: onPlay, onPlayTarget: onPlayTarget)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { guideFor = nil }
                        }
                    }
            }
        }
    }

    private var shown: [CatalogRow] {
        LiveListNarrowing.rows(model.rows, mode: mode, sourceID: sourceID, search: search, userState: userState)
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

    private func row(_ channel: CatalogRow, isFavorite: Bool) -> some View {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                    NowOnAirLine(channel: channel)
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favourite")
                }
            }
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
    /// A snapshot of a list row.
    init(row: CatalogRow) {
        self.init(
            playlist: row.playlist,
            entryID: row.entryID,
            kind: row.kind,
            name: row.name,
            streamURL: row.streamURL,
            remoteID: row.remoteID,
            containerExtension: row.containerExtension
        )
    }

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

/// Search for channels: a magnifier under the section bar that opens a field (see `ExpandingSearch`). Offered once
/// there is a playlist, so it does not sit above a message about adding one.
private struct ChannelSearch: ViewModifier {
    @Binding var text: String
    @Binding var isOpen: Bool
    let isOffered: Bool

    func body(content: Content) -> some View {
        content.modifier(ExpandingSearch(text: $text, isOpen: $isOpen, prompt: "Search channels", isOffered: isOffered))
    }
}

/// Pushes the guide on a phone, tablet or Mac. On Apple TV it takes the whole screen instead: the tab bar
/// and a large title would sit over a grid that pins its time bar to the top, and Menu closes it.
private struct GuidePresentation<Guide: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let guide: () -> Guide

    func body(content: Content) -> some View {
        #if os(tvOS)
            content.fullScreenCover(isPresented: $isPresented) { guide() }
        #else
            content.navigationDestination(isPresented: $isPresented) { guide() }
        #endif
    }
}
