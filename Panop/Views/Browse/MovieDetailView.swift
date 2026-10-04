import PanopCore
import PanopXtream
import SwiftUI

/// A film, as the detail screen needs to know it. Not the live record, which should not outlive
/// the grid it came from.
struct MovieReference: Hashable, Identifiable {
    var playlist: String
    var entryID: String
    var remoteID: String?
    var name: String
    var posterURL: String?
    var groupName: String?
    var plot: String?
    /// Out of ten, as the catalog has it.
    var rating: Double?
    var streamURL: String?
    var containerExtension: String?
    var tmdbID: Int?
    var backdropURL: String?

    var id: String {
        "\(playlist)|\(entryID)"
    }

    init(_ row: CatalogRow) {
        playlist = row.playlist
        entryID = row.entryID
        remoteID = row.remoteID
        name = row.name
        posterURL = row.iconURL
        groupName = row.groupName
        plot = row.plot
        rating = row.rating
        streamURL = row.streamURL
        containerExtension = row.containerExtension
        tmdbID = row.tmdbID
        backdropURL = row.backdropURL
    }

    init(_ item: CatalogEntryRecord) {
        playlist = item.playlist
        entryID = item.id
        remoteID = item.remoteID
        name = item.name
        posterURL = item.iconURL
        groupName = item.groupName
        plot = item.plot
        rating = item.rating
        streamURL = item.streamURL
        containerExtension = item.containerExtension
        tmdbID = item.tmdbID == 0 ? nil : item.tmdbID
    }

    var target: PlaybackTarget {
        PlaybackTarget(
            playlist: playlist,
            entryID: entryID,
            kind: .movie,
            name: name,
            streamURL: streamURL,
            remoteID: remoteID,
            containerExtension: containerExtension
        )
    }
}

/// The one line under a film's title: year, genre, length and rating, whichever are known.
nonisolated enum MovieMeta {
    static func line(year: Int?, genre: String?, durationSeconds: Int?, rating: Double?) -> String {
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        // A panel lists several, "Horror, Sci-Fi, Thriller"; the first two say enough.
        if let genre {
            let shown = genre.split(separator: ",").prefix(2)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !shown.isEmpty {
                parts.append(shown.joined(separator: ", "))
            }
        }
        if let durationSeconds, durationSeconds >= 60 {
            parts.append(length(durationSeconds))
        }
        if let rating, rating > 0 {
            parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1))))
        }
        return parts.joined(separator: " · ")
    }

    static func length(_ seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return String(localized: "\(hours) h \(rest) min")
        }
        return String(localized: "\(minutes) min")
    }
}

/// A film's page: what is known about it, and the ways to play it.
///
/// What the catalog holds (title, poster, and for some panels a plot and rating) shows at once.
/// A provider panel knows more (cast, director, year, length), which is fetched when the page is
/// opened rather than for every film in the catalog. An M3U playlist has nothing more to fetch.
struct MovieDetailView: View {
    let movie: MovieReference

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(SimklSync.self) private var simkl
    @Environment(DiscoveryModel.self) private var discovery

    @State private var info: XtreamMovieInfo?
    @State private var playing: PlaybackTarget?

    private var key: String {
        UserStateStore.key(playlist: movie.playlist, entry: movie.entryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(alignment: .leading, spacing: 20) {
                    actions
                    if let plot = info?.plot ?? movie.plot, !plot.isEmpty {
                        Text(plot).font(.body)
                    }
                    credits
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationTitle(movie.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await loadInfo() }
            .onAppear { simkl.register(movie.id, as: movie.tmdbID.map { .movie(tmdb: $0) }) }
            .modifier(PlayerPresentation(target: $playing))
    }

    // MARK: - Pieces

    private var header: some View {
        DetailHeader(
            backdrop: discovery.backdrop(kind: .movie, tmdbID: movie.tmdbID, provider: info?.backdropURLs.first),
            poster: info?.coverURL ?? movie.posterURL,
            title: movie.name,
            meta: MovieMeta.line(
                year: info?.year,
                genre: info?.genre ?? movie.groupName,
                durationSeconds: info?.durationSeconds,
                rating: info?.rating ?? movie.rating
            )
        ) {
            if userState.isWatched(key) {
                Label("Watched", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let position = userState.resumePosition(for: key) {
                Button("Resume from \(PlayerTime.text(position))", systemImage: "play.fill") {
                    play(at: position)
                }
                .buttonStyle(.borderedProminent)
                Button("Start over", systemImage: "arrow.counterclockwise") { play(at: nil) }
            } else {
                Button("Play", systemImage: "play.fill") { play(at: nil) }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                let isFavorite = userState.isFavorite(key)
                Button(
                    isFavorite ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: isFavorite ? "star.fill" : "star"
                ) { userState.toggleFavorite(key) }
                let seen = userState.isWatched(key)
                Button(
                    seen ? "Mark as Not Watched" : "Mark as Watched",
                    systemImage: seen ? "eye.slash" : "eye"
                ) { userState.setWatched(!seen, for: key) }
            }
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 8) {
            credit("Director", info?.director)
            credit("Cast", info?.cast)
            credit("Country", info?.country)
        }
    }

    @ViewBuilder
    private func credit(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.callout)
            }
        }
    }

    // MARK: - Actions

    private func play(at position: Double?) {
        userState.markPlayed(key)
        var target = movie.target
        target.resumeAt = position
        playing = target
    }

    /// A panel's extra details. Quiet on failure: the page is complete without them.
    private func loadInfo() async {
        guard let remote = movie.remoteID.flatMap(Int.init),
              case let .xtream(credentials)? = try? library.descriptor(for: movie.playlist)?.source,
              let client = try? XtreamClient(credentials: credentials, transport: URLSessionTransport())
        else { return }
        info = try? await client.movieInfo(streamID: remote)
    }
}
