import PanopCore
import SwiftData
import SwiftUI

/// The Movies and Series screens: a poster grid over the catalog, searchable, with a way back
/// into what was left part-way.
///
/// One view for both, since they differ only in what a tap does: a film plays, a series shows
/// its episodes. The grid is the same bounded, indexed fetch the channel list uses.
struct VODBrowseView: View {
    let kind: MediaKind

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(SyncStatusCenter.self) private var status

    @State private var search = ""
    @State private var group: String?
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

    var body: some View {
        VODGrid(
            spec: ListSpec(kind: kind, search: search, group: group),
            kind: kind,
            isSearching: isSearching,
            hasPlaylists: !library.playlists.isEmpty,
            isSyncing: status.isAnySyncing,
            onSelect: select,
            onAdd: { showingAdd = true }
        )
        .navigationTitle(title)
        .modifier(VODSearch(text: $search, isOffered: !library.playlists.isEmpty))
        .toolbar {
            if !library.playlists.isEmpty {
                ToolbarItem { CategoryButton(kind: kind, source: nil, group: $group) }
            }
        }
        .navigationDestination(item: $openSeries) { SeriesDetailView(series: $0) }
        .navigationDestination(item: $openMovie) { MovieDetailView(movie: $0) }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddPlaylistView() }
        }
        .resumeDialog($resume)
        .modifier(PlayerPresentation(target: $playing))
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

/// The grid itself, fed in pages by a background read (see `CatalogListModel`).
private struct VODGrid: View {
    @Environment(\.modelContext) private var catalog
    @State private var model = CatalogListModel()
    let spec: ListSpec

    let kind: MediaKind
    let isSearching: Bool
    let hasPlaylists: Bool
    let isSyncing: Bool
    let onSelect: (CatalogRow) -> Void
    let onAdd: () -> Void

    init(
        spec: ListSpec,
        kind: MediaKind,
        isSearching: Bool,
        hasPlaylists: Bool,
        isSyncing: Bool,
        onSelect: @escaping (CatalogRow) -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.spec = spec
        self.kind = kind
        self.isSearching = isSearching
        self.hasPlaylists = hasPlaylists
        self.isSyncing = isSyncing
        self.onSelect = onSelect
        self.onAdd = onAdd
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Self.spacing)],
                spacing: Self.spacing
            ) {
                ForEach(model.rows) { item in
                    VODCard(item: item, kind: kind) { onSelect(item) }
                        .onAppear { model.rowAppeared(item) }
                }
            }
            .padding()
        }
        .overlay {
            if model.rows.isEmpty, model.phase == .loaded {
                emptyContent
            }
        }
        .task(id: spec) { model.show(spec, in: catalog.container) }
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
