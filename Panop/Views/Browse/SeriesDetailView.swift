import PanopCore
import PanopXtream
import SwiftUI

/// A series' seasons and episodes. A provider panel lists series as shells, so the episodes
/// are fetched here, when someone opens one, rather than for every series in the catalog.
struct SeriesDetailView: View {
    let series: SeriesReference

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState

    private enum Load {
        case loading
        case failed(String)
        case loaded(client: XtreamClient, info: XtreamSeriesInfo)
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
        case let .loaded(client, info):
            if info.seasons.isEmpty {
                ContentUnavailableView(
                    "No episodes",
                    systemImage: "rectangle.stack",
                    description: Text("The provider lists none for this series.")
                )
            } else {
                List {
                    if let plot = series.plot ?? info.plot, !plot.isEmpty {
                        Section { Text(plot).font(.callout).foregroundStyle(.secondary) }
                    }
                    ForEach(info.seasons) { season in
                        Section(season.title) {
                            ForEach(season.episodes, id: \.id) { episode in
                                episodeRow(episode, season: season, client: client)
                            }
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: XtreamEpisode, season: XtreamSeason, client: XtreamClient) -> some View {
        let key = UserStateStore.key(playlist: series.playlist, entry: Self.entryID(of: episode))
        let progress = userState.progress[key]
        return Button {
            select(episode, season: season, client: client, key: key)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(episode.episodeNumber). \(episode.title)")
                    Spacer()
                    if let seconds = episode.durationSeconds, seconds > 0 {
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
    }

    private func select(_ episode: XtreamEpisode, season: XtreamSeason, client: XtreamClient, key: String) {
        let name = "\(series.name) · S\(season.number)E\(episode.episodeNumber)"
        if let position = userState.resumePosition(for: key) {
            resume = ResumeChoice(title: name, position: position) { start in
                play(episode, name: name, client: client, key: key, at: start)
            }
        } else {
            play(episode, name: name, client: client, key: key, at: nil)
        }
    }

    private func play(_ episode: XtreamEpisode, name: String, client: XtreamClient, key: String, at position: Double?) {
        userState.markPlayed(key)
        playing = PlaybackTarget(
            playlist: series.playlist,
            entryID: Self.entryID(of: episode),
            kind: .series,
            name: name,
            streamURL: client.episodeURL(episodeID: episode.id, containerExtension: episode.containerExtension)?
                .absoluteString,
            resumeAt: position
        )
    }

    /// Episodes are not catalog rows, so they get an id of their own for resume points.
    static func entryID(of episode: XtreamEpisode) -> String {
        "episode:\(episode.id)"
    }

    private func fetch() async {
        guard let remote = series.remoteID.flatMap(Int.init),
              case let .xtream(credentials)? = try? library.descriptor(for: series.playlist)?.source
        else {
            load =
                .failed("This series' login details are missing on this device. Delete the playlist and add it again.")
            return
        }
        do {
            let client = try XtreamClient(credentials: credentials, transport: URLSessionTransport())
            load = try await .loaded(client: client, info: client.seriesInfo(seriesID: remote))
        } catch {
            load = .failed(SyncErrorMessage.text(for: error))
        }
    }
}
