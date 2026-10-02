import PanopCore
import PanopPlaylist
import PanopXtream
import SwiftData
import SwiftUI

/// A series' seasons and episodes.
///
/// Where they come from depends on the playlist. A provider panel lists series as shells, so
/// the episodes are fetched here, when someone opens one, rather than for every series in the
/// catalog. A series built from an M3U file already has its episodes in the catalog, linked to
/// it when the playlist was imported, so they are read from there and need no network.
struct SeriesDetailView: View {
    let series: SeriesReference

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(\.modelContext) private var catalog

    /// An episode as the screen needs it, whichever playlist it came from.
    private struct Episode: Identifiable {
        var id: String
        var number: Int
        var title: String
        var seconds: Int?
        /// What its resume point and history are filed under.
        var entryID: String
        var streamURL: String?
        var remoteID: String?
        var containerExtension: String?
    }

    private struct Season: Identifiable {
        var number: Int
        var episodes: [Episode]

        var id: Int {
            number
        }

        var title: String {
            number == 0 ? "Specials" : "Season \(number)"
        }
    }

    private enum Load {
        case loading
        case failed(String)
        case loaded(seasons: [Season], plot: String?)
    }

    @State private var load = Load.loading
    @State private var playing: PlaybackTarget?
    @State private var resume: ResumeChoice?

    var body: some View {
        content
            .navigationTitle(series.name)
            .task { await fetch() }
            .resumeDialog($resume)
            .modifier(PlayerPresentation(target: $playing))
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            ProgressView("Getting the episodes…")
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load the episodes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    load = .loading
                    Task { await fetch() }
                }
            }
        case let .loaded(seasons, plot):
            if seasons.isEmpty {
                ContentUnavailableView(
                    "No episodes",
                    systemImage: "rectangle.stack",
                    description: Text("Nothing is listed for this series.")
                )
            } else {
                List {
                    if let plot = series.plot ?? plot, !plot.isEmpty {
                        Section { Text(plot).font(.callout).foregroundStyle(.secondary) }
                    }
                    ForEach(seasons) { season in
                        Section(season.title) {
                            ForEach(season.episodes) { episode in
                                episodeRow(episode, season: season)
                            }
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: Episode, season: Season) -> some View {
        let key = UserStateStore.key(playlist: series.playlist, entry: episode.entryID)
        let progress = userState.progress[key]
        return Button {
            select(episode, season: season, key: key)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(episode.number). \(episode.title)")
                    Spacer()
                    if userState.isWatched(key) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Watched")
                    }
                    if let seconds = episode.seconds, seconds > 0 {
                        Text(PlayerTime.text(Double(seconds))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let fraction = progress?.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel("Watched \(Int(fraction * 100)) percent")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            let seen = userState.isWatched(key)
            Button {
                userState.setWatched(!seen, for: key)
            } label: {
                Label(seen ? "Mark as Not Watched" : "Mark as Watched", systemImage: seen ? "eye.slash" : "eye")
            }
        }
    }

    private func select(_ episode: Episode, season: Season, key: String) {
        let name = "\(series.name) · S\(season.number)E\(episode.number)"
        if let position = userState.resumePosition(for: key) {
            resume = ResumeChoice(title: name, position: position) { start in
                play(episode, name: name, key: key, at: start)
            }
        } else {
            play(episode, name: name, key: key, at: nil)
        }
    }

    private func play(_ episode: Episode, name: String, key: String, at position: Double?) {
        userState.markPlayed(key)
        playing = PlaybackTarget(
            playlist: series.playlist,
            entryID: episode.entryID,
            kind: .series,
            name: name,
            streamURL: episode.streamURL,
            // For a panel's episode, the id and extension, so a player window can rebuild the
            // address itself; an M3U episode's address is in the catalog and found there.
            remoteID: episode.remoteID,
            containerExtension: episode.containerExtension,
            resumeAt: position
        )
    }

    // MARK: - Loading

    private func fetch() async {
        if series.remoteID == nil {
            loadFromCatalog()
        } else {
            await loadFromPanel()
        }
    }

    /// An M3U series: its episodes are catalog rows, linked to it at import.
    private func loadFromCatalog() {
        let rows = (try? catalog.fetch(LiveChannelQuery.episodes(of: series.entryID, in: series.playlist))) ?? []
        let episodes = rows.map { row in
            (
                season: row.seasonNumber ?? 0,
                episode: Episode(
                    id: row.id,
                    number: row.episodeNumber ?? 0,
                    // What follows the numbers, if the name has anything; otherwise just its number.
                    title: EpisodeTitle.parse(row.name)?.title ?? "Episode \(row.episodeNumber ?? 0)",
                    seconds: nil,
                    entryID: row.id,
                    streamURL: row.streamURL,
                    remoteID: nil,
                    containerExtension: row.containerExtension
                )
            )
        }
        load = .loaded(seasons: Self.seasons(from: episodes), plot: nil)
    }

    /// A panel's series: the episodes are fetched now.
    private func loadFromPanel() async {
        guard let remote = series.remoteID.flatMap(Int.init),
              case let .xtream(credentials)? = try? library.descriptor(for: series.playlist)?.source
        else {
            load =
                .failed("This series' login details are missing on this device. Delete the playlist and add it again.")
            return
        }
        do {
            let client = try XtreamClient(credentials: credentials, transport: URLSessionTransport())
            let info = try await client.seriesInfo(seriesID: remote)
            let episodes = info.episodes.map { episode in
                (
                    season: episode.seasonNumber,
                    episode: Episode(
                        id: episode.id,
                        number: episode.episodeNumber,
                        title: episode.title,
                        seconds: episode.durationSeconds,
                        // Not catalog rows, so an id of their own for resume points.
                        entryID: "episode:\(episode.id)",
                        streamURL: client.episodeURL(
                            episodeID: episode.id,
                            containerExtension: episode.containerExtension
                        )?.absoluteString,
                        remoteID: episode.id,
                        containerExtension: episode.containerExtension
                    )
                )
            }
            load = .loaded(seasons: Self.seasons(from: episodes), plot: info.plot)
        } catch {
            load = .failed(SyncErrorMessage.text(for: error))
        }
    }

    /// Seasons in order, specials last, each season's episodes in order.
    private static func seasons(from episodes: [(season: Int, episode: Episode)]) -> [Season] {
        Dictionary(grouping: episodes, by: \.season)
            .map { Season(number: $0.key, episodes: $0.value.map(\.episode).sorted { $0.number < $1.number }) }
            .sorted { lhs, rhs in
                if (lhs.number == 0) != (rhs.number == 0) {
                    return rhs.number == 0
                }
                return lhs.number < rhs.number
            }
    }
}
