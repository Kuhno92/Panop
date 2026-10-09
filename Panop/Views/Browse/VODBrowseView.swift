import PanopCore
import PanopDiscover
import PanopSimkl
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

    /// Whether this screen leads with suggestions (the carousel and the rails). Kept for Movies and Series apart, so
    /// someone who wants only the list on one of them can have it so.
    @AppStorage("showsSuggestionsOnMovies") private var suggestionsOnMovies = true
    @AppStorage("showsSuggestionsOnSeries") private var suggestionsOnSeries = true
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
        kind == .movie ? String(localized: "Movies") : String(localized: "Series")
    }

    private var showsSuggestions: Binding<Bool> {
        kind == .movie ? $suggestionsOnMovies : $suggestionsOnSeries
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
            rails: isSearching || group != nil || !showsSuggestions.wrappedValue ? [] : discovery.rails
                .filter { ($0.mediaKind ?? discovery.rows[$0.keys.first ?? ""]?.kind) == kind },
            railRows: discovery.rows,
            railLinks: discovery.trendingLinks,
            nextEpisodes: discovery.nextEpisodes,
            onSelect: select,
            backdrop: { discovery.backdrop(for: $0) },
            onAdd: { showingAdd = true },
            header: { header }
        )
        .background { PageBackground() }
        .navigationTitle(title)
        .withoutTVTitleBar()
        .modifier(VODSearch(
            text: $search,
            tab: kind == .movie ? .movies : .series
        ))
        .task(id: CategoryLoad(source: selectedSource?.id, syncing: status.isAnySyncing)) {
            providerCategories = await CatalogReader(container: catalog.container)
                .categoryNames(kind: kind, source: selectedSource?.id)
            categoriesKnown = true
        }
        // The category may not exist in the other source.
        .onChange(of: storedSource) { group = nil }
        .navigationDestination(item: $openSeries) { SeriesDetailView(series: $0) }
        .navigationDestination(item: $openMovie) { MovieDetailView(movie: $0) }
        .addPlaylistSheet(isPresented: $showingAdd)
        .resumeDialog($resume)
        .modifier(PlayerPresentation(target: $playing))
    }

    /// The choices above the list, which scroll away with it: suggestions, sort and source, then the categories.
    @ViewBuilder
    private var header: some View {
        if !library.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    suggestionsToggle
                    sortMenu
                    if sources.count > 1 {
                        sourceMenu
                    }
                    Spacer()
                }
                #if os(tvOS) || os(iOS)
                // Light pills, so the three read as buttons and not as dark bars the width of the row.
                .buttonStyle(HeaderButtonStyle())
                .focusEffectDisabled()
                #endif
                .padding(.horizontal)
                CategoryChips(kind: kind, source: selectedSource?.id, group: $group)
            }
        }
    }

    /// Shows or hides the carousel and the rails above the list.
    @ViewBuilder
    private var suggestionsToggle: some View {
        #if os(tvOS)
            // A toggle stretches over the whole row on Apple TV and hides the buttons beside it: a button, like them.
            Button {
                showsSuggestions.wrappedValue.toggle()
            } label: {
                Label(
                    showsSuggestions.wrappedValue ? "Suggestions: On" : "Suggestions: Off",
                    systemImage: "sparkles"
                )
            }
        #elseif os(iOS)
            // A button like the others beside it, lighter while on; it reads as a switch to VoiceOver and to tests.
            Button {
                showsSuggestions.wrappedValue.toggle()
            } label: {
                Label("Suggestions", systemImage: "sparkles")
            }
            .buttonStyle(HeaderButtonStyle(isChosen: showsSuggestions.wrappedValue))
            .accessibilityValue(Text(verbatim: showsSuggestions.wrappedValue ? "1" : "0"))
            .accessibilityAddTraits(.isToggle)
        #else
            Toggle(isOn: showsSuggestions) {
                Label("Suggestions", systemImage: "sparkles")
            }
            .toggleStyle(.button)
            .help("Show or hide the suggestions above the list")
        #endif
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
                plot: item.plot,
                tmdbID: item.tmdbID,
                backdropURL: item.backdropURL,
                rating: item.rating,
                year: item.year,
                genre: item.genre,
                cast: item.cast
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
    var tmdbID: Int?
    var backdropURL: String?
    /// What the catalog already knows, so the page has it before the panel answers.
    var rating: Double?
    var year: Int?
    var genre: String?
    var cast: String?

    var id: String {
        "\(playlist)|\(entryID)"
    }
}

/// The grid itself: one section per category under its heading, fed in pages by a background read
/// (see `CategorySectionsModel`).
private struct VODGrid<Header: View>: View {
    @Environment(\.modelContext) private var catalog
    @State private var model = CategorySectionsModel()
    /// What the hero's artwork reaches up through to the top of the screen: the navigation bar (iPhone and iPad; inside
    /// a
    /// scroll view `ignoresSafeArea` does not do it).
    @State private var barHeight: CGFloat = 0
    /// Nil while what to show is not yet known.
    let plan: CategorySectionsModel.Plan?

    let kind: MediaKind
    let isSearching: Bool
    let hasPlaylists: Bool
    let isSyncing: Bool
    let rails: [Rail]
    let railRows: [String: CatalogRow]
    let railLinks: [String: URL]
    let nextEpisodes: [String: SimklNextEpisode]
    let onSelect: (CatalogRow) -> Void
    /// Wide artwork for a title, if any is known.
    let backdrop: (CatalogRow) -> String?
    let onAdd: () -> Void
    let header: Header

    init(
        plan: CategorySectionsModel.Plan?,
        kind: MediaKind,
        isSearching: Bool,
        hasPlaylists: Bool,
        isSyncing: Bool,
        rails: [Rail],
        railRows: [String: CatalogRow],
        railLinks: [String: URL],
        nextEpisodes: [String: SimklNextEpisode],
        onSelect: @escaping (CatalogRow) -> Void,
        backdrop: @escaping (CatalogRow) -> String?,
        onAdd: @escaping () -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.plan = plan
        self.kind = kind
        self.isSearching = isSearching
        self.hasPlaylists = hasPlaylists
        self.isSyncing = isSyncing
        self.rails = rails
        self.railRows = railRows
        self.railLinks = railLinks
        self.nextEpisodes = nextEpisodes
        self.onSelect = onSelect
        self.backdrop = backdrop
        self.onAdd = onAdd
        self.header = header()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing, pinnedViews: Self.pinnedHeadings) {
                // The choices go inside the carousel when there is one, so its artwork, which reaches up behind them,
                // is drawn under them.
                if heroRows.isEmpty {
                    header
                } else {
                    HeroCarousel(
                        rows: heroRows,
                        backdrop: backdrop,
                        onInfo: onSelect,
                        above: AnyView(header)
                    )
                }
                ForEach(rails) { rail in
                    PosterRail(
                        rail: rail,
                        rows: railRows,
                        links: railLinks,
                        nextEpisodes: nextEpisodes,
                        onSelect: onSelect
                    )
                }
                if rails.contains(where: RailHeading.isFromSimkl) {
                    SimklCredit()
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
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barHeight = $0 }
        .environment(\.heroReach, barHeight + 56)
        #endif
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

    /// The carousel's titles: from the rails, or, in a UI test about the hero, the ones it seeded (films only).
    private var heroRows: [CatalogRow] {
        let seeded = kind == .movie ? UITestMode.heroTitles : []
        return seeded.isEmpty ? HeroSelection.rows(rails: rails, rows: railRows, backdrop: backdrop) : seeded
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
                // A pinned heading has to cover the posters that scroll under it; a material does, and lets the page's
                // colours show (the plain background was a black bar on the dark gradient). Not pinned on Apple TV.
                .background(Self.headingBackdrop)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Pinned, so the category being browsed stays in view while its titles scroll. Apple TV moves
    /// by focus, where a pinned heading would only sit over the posters.
    private static var headingBackdrop: AnyShapeStyle {
        #if os(tvOS)
            AnyShapeStyle(.clear)
        #else
            AnyShapeStyle(.regularMaterial)
        #endif
    }

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

/// Search for films or series, in the system's field (see `ScreenSearch`).
private struct VODSearch: ViewModifier {
    @Binding var text: String
    let tab: AppTab

    func body(content: Content) -> some View {
        content.modifier(ScreenSearch(text: $text, tab: tab, prompt: "Search"))
    }
}
