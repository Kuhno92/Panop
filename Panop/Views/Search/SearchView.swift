import PanopCore
import SwiftData
import SwiftUI

/// The results of one search over everything: live channels, movies and series together, each
/// section short. Shown on Home in place of its rails while there is something typed.
///
/// Each section is the same bounded, indexed fetch its own screen uses, with a small limit, so
/// the cost does not grow with the catalog. The screens themselves remain the place to browse a
/// long list; this is for finding one thing.
struct SearchView: View {
    /// What is typed, as it is typed.
    let query: String

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState

    /// The text searched for: `query`, a moment after typing stops, so a fetch does not run on
    /// every keystroke.
    @State private var term = ""
    @State private var playing: PlaybackTarget?
    @State private var openMovie: MovieReference?
    @State private var openSeries: SeriesReference?

    /// Few enough to read at a glance.
    private static let perSection = 12

    private var isSearching: Bool {
        !term.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                SearchSection(
                    kind: .live, title: "Channels", term: term, limit: Self.perSection,
                    hidden: userState.hidden, hiddenGroups: userState.hiddenCategories(of: .live), onSelect: select
                )
                if library.offersVOD {
                    SearchSection(
                        kind: .movie, title: "Movies", term: term, limit: Self.perSection,
                        hidden: userState.hidden, hiddenGroups: userState.hiddenCategories(of: .movie), onSelect: select
                    )
                    SearchSection(
                        kind: .series, title: "Series", term: term, limit: Self.perSection,
                        hidden: userState.hidden, hiddenGroups: userState.hiddenCategories(of: .series),
                        onSelect: select
                    )
                }
            }
        }
        .pageBackdrop()
        .task(id: query) {
            // Typing again cancels this task, so only the pause counts.
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled {
                term = query
            }
        }
        .navigationDestination(item: $openMovie) { MovieDetailView(movie: $0) }
        .navigationDestination(item: $openSeries) { SeriesDetailView(series: $0) }
        .modifier(PlayerPresentation(target: $playing))
    }

    private func select(_ item: CatalogEntryRecord) {
        switch item.kind {
        case .movie:
            openMovie = MovieReference(item)
        case .series where (item.streamURL ?? "").isEmpty:
            // A provider's series is a shell: its episodes are fetched when it opens.
            openSeries = SeriesReference(
                playlist: item.playlist,
                entryID: item.id,
                remoteID: item.remoteID,
                name: item.name,
                posterURL: item.iconURL,
                plot: item.plot,
                tmdbID: item.tmdbID == 0 ? nil : item.tmdbID,
                backdropURL: item.backdropURL,
                rating: item.rating,
                year: item.year == 0 ? nil : item.year,
                genre: item.genre,
                cast: item.cast
            )
        default:
            userState.markPlayed(UserStateStore.key(playlist: item.playlist, entry: item.id))
            var target = PlaybackTarget(entry: item)
            if item.kind != .live {
                target.resumeAt = userState.resumePosition(for: UserStateStore.key(
                    playlist: item.playlist,
                    entry: item.id
                ))
            }
            playing = target
        }
    }
}

/// One kind's matches. Its `@Query` is rebuilt when the term changes. A kind with no match is
/// not drawn, rather than shown empty.
private struct SearchSection: View {
    @Query private var matches: [CatalogEntryRecord]
    let title: LocalizedStringKey
    let hidden: Set<String>
    let hiddenGroups: Set<String>
    let onSelect: (CatalogEntryRecord) -> Void

    init(
        kind: MediaKind,
        title: LocalizedStringKey,
        term: String,
        limit: Int,
        hidden: Set<String>,
        hiddenGroups: Set<String>,
        onSelect: @escaping (CatalogEntryRecord) -> Void
    ) {
        self.hidden = hidden
        self.hiddenGroups = hiddenGroups
        _matches = Query(LiveChannelQuery.descriptor(kind: kind, source: nil, search: term, limit: limit))
        self.title = title
        self.onSelect = onSelect
    }

    var body: some View {
        let shown = matches.filter {
            !hidden.contains(UserStateStore.key(playlist: $0.playlist, entry: $0.id))
                && !($0.groupName.map(hiddenGroups.contains) ?? false)
        }
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown) { item in
                    Button { onSelect(item) } label: {
                        HStack(spacing: 12) {
                            ChannelLogo(address: item.iconURL)
                            Text(item.name)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
