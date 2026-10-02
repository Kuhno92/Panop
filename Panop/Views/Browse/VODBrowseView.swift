import PanopCore
import PanopDiscover
import SwiftData
import SwiftUI

/// The Movies and Series screens: posters shown category by category, searchable, with a way to
/// choose the source and the sort.
///
/// One view for both, since they differ only in what a tap does: a film opens its page, a series
/// shows its episodes. With every category selected, the first category's titles come first, then
/// the second's, each under its heading, in the order the categories are arranged; a chosen
/// category is just its own titles. The sort applies within each category.
struct VODBrowseView: View {
    let kind: MediaKind

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(SyncStatusCenter.self) private var status
    @Environment(DiscoveryModel.self) private var discovery

    @Environment(\.modelContext) private var catalog

    /// Remembered between launches, and shared by Movies and Series. A source that was since
    /// deleted reads as "all sources".
    @AppStorage("vodSourceFilter") private var storedSource = LiveSourceFilter.allID
    @AppStorage("vodSortOrder") private var storedOrder = LiveOrder.provider.rawValue

    @State private var search = ""
    @State private var group: String?
    /// Every category of this kind and source, in the provider's order, once known.
    @State private var providerCategories: [String] = []
    @State private var categoriesKnown = false
    @State private var playing: PlaybackTarget?
    @State private var resume: ResumeChoice?
    @State private var openSeries: SeriesReference?
    @State private var openMovie: MovieReference?
    @State private var showingAdd = false

    private var title: String {
        kind == .movie ? "Movies" : "Series"
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The playlists that have films and series at all.
    private var sources: [PlaylistSummary] {
        library.playlists.filter(\.includesVOD)
    }

    private var selectedSource: PlaylistSummary? {
        sources.first { $0.id == storedSource }
    }

    private var order: LiveOrder {
        LiveOrder(rawValue: storedOrder) ?? .provider
    }

    /// What to show: the chosen category alone, or every visible category one after another in
    /// the order the person arranged them, then whatever has none. Nil until the categories are
    /// known, so the list does not show the uncategorised alone for a moment first.
    private var plan: CategorySectionsModel.Plan? {
        guard categoriesKnown else { return nil }
        let base = ListSpec(
            kind: kind,
            source: selectedSource?.id,
            search: search,
            order: order,
            hidden: userState.hidden
        )
        if let group {
            return .init(base: base, categories: [group], includesUngrouped: false)
        }
        return .init(
            base: base,
            categories: userState.visibleCategories(providerCategories, kind: kind),
            includesUngrouped: true
        )
    }

    private struct CategoryLoad: Hashable {
        var source: String?
        var syncing: Bool
    }

    var body: some View {
        VODGrid(
            plan: plan,
            kind: kind,
            isSearching: isSearching,
            hasPlaylists: !library.playlists.isEmpty,
            isSyncing: status.isAnySyncing,
            // Suggestions are for browsing: a search or a chosen category wants its own titles.
            rails: isSearching || group != nil ? [] : discovery.rails
                .filter { ($0.mediaKind ?? discovery.rows[$0.keys.first ?? ""]?.kind) == kind },
            railRows: discovery.rows,
            onSelect: select,
            onAdd: { showingAdd = true }
        )
        .navigationTitle(title)
        .modifier(VODSearch(text: $search, isOffered: !library.playlists.isEmpty))
        .safeAreaInset(edge: .top, spacing: 0) {
            if !library.playlists.isEmpty {
                VStack(spacing: 0) {
                    #if os(tvOS)
                        // Apple TV has no toolbar, so the choices are a row above the chips.
                        HStack(spacing: 24) {
                            sortMenu
                            if sources.count > 1 {
                                sourceMenu
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                    #endif
                    CategoryChips(kind: kind, source: selectedSource?.id, group: $group)
                }
            }
        }
        .toolbar {
            #if !os(tvOS)
                if !library.playlists.isEmpty {
                    ToolbarItem { sortMenu }
                    if sources.count > 1 {
                        ToolbarItem { sourceMenu }
                    }
                }
            #endif
        }
        .task(id: CategoryLoad(source: selectedSource?.id, syncing: status.isAnySyncing)) {
            providerCategories = await CatalogReader(container: catalog.container)
                .categoryNames(kind: kind, source: selectedSource?.id)
            categoriesKnown = true
        }
        // The category may not exist in the other source.
        .onChange(of: storedSource) { group = nil }
        .navigationDestination(item: $openSeries) { SeriesDetailView(series: $0) }
        .navigationDestination(item: $openMovie) { MovieDetailView(movie: $0) }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .resumeDialog($resume)
        .modifier(PlayerPresentation(target: $playing))
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $storedOrder) {
                ForEach(LiveOrder.forFilms) { order in
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
                ForEach(sources) { playlist in
                    Text(playlist.name).tag(playlist.id)
                }
            }
        } label: {
            Label(selectedSource?.name ?? "All sources", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Source")
    }

    private func select(_ item: CatalogRow) {
        // A series from a provider panel is a shell: its episodes are fetched when it is opened.
        // An M3U "series" entry is already one episode, with its own address, so it plays.
        if kind == .series, (item.streamURL ?? "").isEmpty {
            openSeries = SeriesReference(
                playlist: item.playlist,
                entryID: item.entryID,
                remoteID: item.remoteID,
                name: item.name,
                posterURL: item.iconURL,
                plot: item.plot
            )
            return
        }
        // A film opens its page, which has the resume choice and the details.
        if kind == .movie {
            openMovie = MovieReference(item)
            return
        }
        if let position = userState.resumePosition(for: item.id) {
            resume = ResumeChoice(title: item.name, position: position) { start in
                play(item, at: start)
            }
        } else {
            play(item, at: nil)
        }
    }

    private func play(_ item: CatalogRow, at position: Double?) {
        userState.markPlayed(item.id)
        var target = PlaybackTarget(row: item)
        target.resumeAt = position
        playing = target
    }
}

/// A series, as the detail screen needs to know it. Not the live record, which should not
/// outlive the list it came from.
struct SeriesReference: Hashable, Identifiable {
    var playlist: String
    var entryID: String
    var remoteID: String?
    var name: String
    var posterURL: String?
    var plot: String?

    var id: String {
        "\(playlist)|\(entryID)"
    }
}

/// The grid itself: one section per category under its heading, fed in pages by a background read
/// (see `CategorySectionsModel`).
private struct VODGrid: View {
    @Environment(\.modelContext) private var catalog
    @State private var model = CategorySectionsModel()
    /// Nil while what to show is not yet known.
    let plan: CategorySectionsModel.Plan?

    let kind: MediaKind
    let isSearching: Bool
    let hasPlaylists: Bool
    let isSyncing: Bool
    let rails: [Rail]
    let railRows: [String: CatalogRow]
    let onSelect: (CatalogRow) -> Void
    let onAdd: () -> Void

    init(
        plan: CategorySectionsModel.Plan?,
        kind: MediaKind,
        isSearching: Bool,
        hasPlaylists: Bool,
        isSyncing: Bool,
        rails: [Rail],
        railRows: [String: CatalogRow],
        onSelect: @escaping (CatalogRow) -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.plan = plan
        self.kind = kind
        self.isSearching = isSearching
        self.hasPlaylists = hasPlaylists
        self.isSyncing = isSyncing
        self.rails = rails
        self.railRows = railRows
        self.onSelect = onSelect
        self.onAdd = onAdd
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing, pinnedViews: Self.pinnedHeadings) {
                ForEach(rails) { rail in
                    PosterRail(rail: rail, rows: railRows, onSelect: onSelect)
                }
                ForEach(model.sections) { section in
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Self.spacing)],
                            spacing: Self.spacing
                        ) {
                            ForEach(section.rows) { item in
                                VODCard(item: item, kind: kind) { onSelect(item) }
                                    .onAppear { model.rowAppeared(item) }
                            }
                        }
                        .padding(.horizontal)
                    } header: {
                        heading(section)
                    }
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if plan != nil, model.sections.isEmpty, model.phase == .loaded {
                emptyContent
            }
        }
        .task(id: plan) {
            if let plan {
                model.show(plan, in: catalog.container)
            }
        }
    }

    /// The category being browsed. Left out when the list is a single run with no category at all,
    /// which would only be headed "Other".
    @ViewBuilder
    private func heading(_ section: CategorySection) -> some View {
        if !(model.sections.count == 1 && section.name == nil) {
            Text(section.name ?? "Other")
                .font(.title3.bold())
                .lineLimit(1)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Rectangle().fill(.background))
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Pinned, so the category being browsed stays in view while its titles scroll. Apple TV moves
    /// by focus, where a pinned heading would only sit over the posters.
    private static var pinnedHeadings: PinnedScrollableViews {
        #if os(tvOS)
            []
        #else
            [.sectionHeaders]
        #endif
    }

    @ViewBuilder
    private var emptyContent: some View {
        if isSearching {
            ContentUnavailableView.search
        } else if !hasPlaylists {
            ContentUnavailableView {
                Label("No playlist yet", systemImage: "antenna.radiowaves.left.and.right")
            } description: {
                Text("Add an M3U playlist or Xtream provider to get started.")
            } actions: {
                Button("Add playlist", action: onAdd)
            }
        } else if isSyncing {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("Getting your \(kind == .movie ? "movies" : "series")…")
            }
        } else {
            ContentUnavailableView(
                kind == .movie ? "No movies" : "No series",
                systemImage: kind == .movie ? "film" : "rectangle.stack",
                description: Text("Your playlists have none yet.")
            )
        }
    }

    private static var cardWidth: CGFloat {
        #if os(tvOS)
            220
        #else
            140
        #endif
    }

    private static var spacing: CGFloat {
        #if os(tvOS)
            40
        #else
            16
        #endif
    }
}

/// One poster, its title, and how far through it someone got.
private struct VODCard: View {
    let item: CatalogRow
    let kind: MediaKind
    let action: () -> Void

    @Environment(UserStateStore.self) private var userState

    private var key: String {
        item.id
    }

    var body: some View {
        let isFavorite = userState.isFavorite(key)
        let fraction = userState.progress[key]?.fraction
        let isWatched = userState.isWatched(key)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(address: item.iconURL, symbol: kind == .movie ? "film" : "rectangle.stack")
                    .overlay(alignment: .bottom) {
                        if let fraction {
                            ProgressView(value: fraction)
                                .tint(.white)
                                .padding(8)
                                .accessibilityLabel("Watched \(Int(fraction * 100)) percent")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .accessibilityLabel("Favourite")
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isWatched {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, .green)
                                .padding(6)
                                .accessibilityLabel("Watched")
                        }
                    }
                Text(item.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(item.name)
        .contextMenu {
            Button {
                userState.toggleFavorite(key)
            } label: {
                Label(
                    isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
            // A series entry is a show, which is watched through its episodes.
            Button {
                userState.setHidden(true, for: key)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            if kind == .movie {
                Button {
                    userState.setWatched(!isWatched, for: key)
                } label: {
                    Label(
                        isWatched ? "Mark as Not Watched" : "Mark as Watched",
                        systemImage: isWatched ? "eye.slash" : "eye"
                    )
                }
            }
        }
    }
}

/// Search, once there is something to search (on Apple TV its keyboard fills half the screen).
private struct VODSearch: ViewModifier {
    @Binding var text: String
    let isOffered: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
            if isOffered {
                content.searchable(text: $text, prompt: "Search")
            } else {
                content
            }
        #else
            content.searchable(text: $text, prompt: "Search")
        #endif
    }
}
