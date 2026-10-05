import PanopCore
import PanopPlaylist
import PanopSimkl
import PanopXtream
import SwiftData
import SwiftUI

/// A series' seasons and episodes.
///
/// Where they come from depends on the playlist. A provider panel lists series as shells, so
/// the episodes are fetched here, when someone opens one, rather than for every series in the
/// catalog. A series built from an M3U file already has its episodes in the catalog, linked to
/// it when the playlist was imported, so they are read from there and need no network.
///
/// The page opens on the artwork and the facts about the show (rating, year, genres, how many seasons and
/// episodes, cast), a button for what to watch next, and then one season at a time with a picture, a date, a length,
/// the file's quality and a line of plot for each episode.
struct SeriesDetailView: View {
    let series: SeriesReference

    @Environment(PlaylistLibrary.self) private var library
    @Environment(UserStateStore.self) private var userState
    @Environment(SimklSync.self) private var simkl
    @Environment(DiscoveryModel.self) private var discovery
    @Environment(\.modelContext) private var catalog
    @Environment(\.openURL) private var openURL

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
        var plot: String?
        var imageURL: String?
        var airDate: String?
        var rating: Double?
        var quality: String?
    }

    private struct Season: Identifiable {
        var number: Int
        var episodes: [Episode]

        var id: Int {
            number
        }

        var title: String {
            number == 0 ? String(localized: "Specials") : String(localized: "Season \(number)")
        }
    }

    /// What the panel says about the show itself.
    private struct Details {
        var plot: String?
        var genre: String?
        var cast: String?
        var director: String?
        var releaseDate: String?
        var rating: Double?
        var runtimeMinutes: Int?
        var backdrop: String?
        var trailer: String?
    }

    private enum Load {
        case loading
        case failed(String)
        case loaded(seasons: [Season], details: Details)
    }

    @State private var load = Load.loading
    @State private var playing: PlaybackTarget?
    @State private var resume: ResumeChoice?
    @State private var selectedSeason: Int?
    @State private var plotExpanded = false

    var body: some View {
        content
            .navigationTitle(series.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
        case let .loaded(seasons, details):
            if seasons.isEmpty {
                ContentUnavailableView(
                    "No episodes",
                    systemImage: "rectangle.stack",
                    description: Text("Nothing is listed for this series.")
                )
            } else {
                page(seasons, details)
            }
        }
    }

    // MARK: - The page

    private func page(_ seasons: [Season], _ details: Details) -> some View {
        let shown = seasons.first { $0.number == selectedSeason } ?? seasons
            .first(where: { $0.number == startSeason(seasons) })
            ?? seasons[0]
        return ScrollViewReader { proxy in
            List {
                Section {
                    header(seasons, details)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    #if !os(tvOS)
                        .listRowSeparator(.hidden)
                    #endif
                    actions(seasons, details)
                    overview(details)
                    facts(details)
                    watchedSummary(seasons)
                }
                if seasons.count > 1 {
                    Section { seasonPicker(seasons, shown) }
                }
                Section(shown.title) {
                    ForEach(shown.episodes) { episode in
                        episodeRow(episode, season: shown)
                            .id(Self.rowID(season: shown.number, episode: episode.number))
                    }
                }
            }
            .pageBackdrop()
            // Flat rows, so the header's artwork runs to the edges instead of sitting in a rounded card.
            .listStyle(.plain)
            // Straight to where the person left off, when their Simkl account says where that is.
            .task(id: seasons.count) {
                if let next = upNext {
                    selectedSeason = next.season
                    proxy.scrollTo(Self.rowID(season: next.season, episode: next.number), anchor: .top)
                }
            }
        }
    }

    private func header(_ seasons: [Season], _ details: Details) -> some View {
        DetailHeader(
            backdrop: discovery.backdrop(
                kind: .series,
                tmdbID: series.tmdbID,
                provider: details.backdrop ?? series.backdropURL
            ),
            poster: series.posterURL,
            title: series.name,
            meta: stats(seasons, details),
            symbol: "rectangle.stack"
        ) {
            DetailChips(chips: chips(details))
        }
    }

    /// `2023 · 3 seasons · 28 episodes · 45 min`
    private func stats(_ seasons: [Season], _ details: Details) -> String {
        var parts: [String] = []
        if let year = DetailFormat.year(from: details.releaseDate) ?? series.year {
            parts.append(String(year))
        }
        let real = seasons.filter { $0.number > 0 }.count
        if real > 0 {
            parts.append(DetailFormat.seasons(real))
        }
        parts.append(DetailFormat.episodes(seasons.reduce(0) { $0 + $1.episodes.count }))
        if let minutes = details.runtimeMinutes, minutes > 0 {
            parts.append(DetailFormat.runtime(minutes: minutes))
        }
        return parts.joined(separator: " · ")
    }

    /// The rating, then up to three genres.
    private func chips(_ details: Details) -> [DetailChip] {
        var result: [DetailChip] = []
        if let rating = details.rating ?? series.rating, rating > 0 {
            result.append(DetailChip(text: DetailFormat.rating(rating), symbol: "star.fill", tint: .yellow))
        }
        result += DetailFormat.genres(details.genre ?? series.genre).map { DetailChip(text: $0) }
        return result
    }

    /// What to watch next, and the trailer when the panel has one.
    private func actions(_ seasons: [Season], _ details: Details) -> some View {
        HStack(spacing: 12) {
            if let next = nextToWatch(seasons) {
                let key = UserStateStore.key(playlist: series.playlist, entry: next.episode.entryID)
                Button {
                    select(next.episode, season: next.season, key: key)
                } label: {
                    Label(nextLabel(next, key: key), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            if let trailer = trailerURL(details.trailer) {
                Button { openURL(trailer) } label: {
                    Label("Trailer", systemImage: "play.rectangle")
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        #if !os(tvOS)
        .listRowSeparator(.hidden)
        #endif
    }

    private func nextLabel(_ next: (season: Season, episode: Episode), key: String) -> String {
        let code = "S\(next.season.number) E\(next.episode.number)"
        let started = userState.progress[key] != nil
        return started ? String(localized: "Continue \(code)") : String(localized: "Play \(code)")
    }

    @ViewBuilder
    private func overview(_ details: Details) -> some View {
        if let plot = series.plot ?? details.plot, !plot.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(plot)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(plotExpanded ? nil : 4)
                if plot.count > 220 {
                    Button(plotExpanded ? "Less" : "More") { plotExpanded.toggle() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
            }
            #if !os(tvOS)
            .listRowSeparator(.hidden)
            #endif
        }
    }

    @ViewBuilder
    private func facts(_ details: Details) -> some View {
        let cast = details.cast ?? series.cast
        if [cast, details.director, details.releaseDate].contains(where: { $0?.isEmpty == false }) {
            VStack(alignment: .leading, spacing: 10) {
                DetailFact(title: "Cast", value: cast)
                DetailFact(title: "Director", value: details.director)
                DetailFact(title: "First aired", value: DetailFormat.date(details.releaseDate))
            }
            #if !os(tvOS)
            .listRowSeparator(.hidden)
            #endif
        }
    }

    /// `12 of 28 watched`, with a bar.
    @ViewBuilder
    private func watchedSummary(_ seasons: [Season]) -> some View {
        let all = seasons.flatMap(\.episodes)
        let seen = all.filter { userState.isWatched(UserStateStore.key(playlist: series.playlist, entry: $0.entryID)) }
            .count
        if seen > 0, !all.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(seen) of \(all.count) watched").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ProgressView(value: Double(seen), total: Double(all.count))
            }
            #if !os(tvOS)
            .listRowSeparator(.hidden)
            #endif
        }
    }

    private func seasonPicker(_ seasons: [Season], _ shown: Season) -> some View {
        Picker(selection: Binding(get: { shown.number }, set: { selectedSeason = $0 })) {
            ForEach(seasons) { season in
                Text(season.title).tag(season.number)
            }
        } label: {
            Label("Season", systemImage: "list.number")
        }
        #if os(macOS)
        .pickerStyle(.menu)
        #endif
    }

    /// The season the page opens on: the one with the episode to watch next.
    private func startSeason(_ seasons: [Season]) -> Int {
        if let next = upNext {
            return next.season
        }
        return nextToWatch(seasons)?.season.number ?? seasons[0].number
    }

    /// The episode left part-way if there is one, else the first not yet watched, else the first of the show.
    private func nextToWatch(_ seasons: [Season]) -> (season: Season, episode: Episode)? {
        let all = seasons.flatMap { season in season.episodes.map { (season: season, episode: $0) } }
        func key(_ item: (season: Season, episode: Episode)) -> String {
            UserStateStore.key(playlist: series.playlist, entry: item.episode.entryID)
        }
        if let next = upNext,
           let found = all.first(where: { $0.season.number == next.season && $0.episode.number == next.number })
        {
            return found
        }
        if let partway = all.first(where: { userState.progress[key($0)] != nil && !userState.isWatched(key($0)) }) {
            return partway
        }
        return all.first { !userState.isWatched(key($0)) } ?? all.first
    }

    /// A YouTube id or address, as the panel writes it.
    private func trailerURL(_ text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        if text.hasPrefix("http") {
            return URL(string: text)
        }
        return URL(string: "https://www.youtube.com/watch?v=\(text)")
    }

    private static func rowID(season: Int, episode: Int) -> String {
        "s\(season)e\(episode)"
    }

    /// The episode Simkl says is next for this show, once the show is known by its TMDB id.
    private var upNext: SimklNextEpisode? {
        series.tmdbID.flatMap { discovery.nextEpisodes[DiscoveryModel.linkKey(kind: .series, tmdbID: $0)] }
    }
}

/// The episode rows, and what is said under each.
extension SeriesDetailView {
    // MARK: - An episode

    private func episodeRow(_ episode: Episode, season: Season) -> some View {
        let key = UserStateStore.key(playlist: series.playlist, entry: episode.entryID)
        let progress = userState.progress[key]
        return Button {
            select(episode, season: season, key: key)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(episode, progress: progress?.fraction)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(episode.number). \(episode.title)").font(.subheadline.weight(.semibold))
                        if let next = upNext, next.season == season.number, next.number == episode.number {
                            Text("Up next")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.2), in: Capsule())
                        }
                        Spacer(minLength: 4)
                        if userState.isWatched(key) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Watched")
                        }
                    }
                    if let line = detailLine(episode) {
                        Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let plot = episode.plot, !plot.isEmpty {
                        Text(plot).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            let seen = userState.isWatched(key)
            Button {
                registerForSimkl(episode, season: season, key: key)
                userState.setWatched(!seen, for: key)
            } label: {
                Label(seen ? "Mark as Not Watched" : "Mark as Watched", systemImage: seen ? "eye.slash" : "eye")
            }
        }
    }

    /// `22 September 2004 · 45 min · ★ 7.5 · 1080p · HEVC · AC3`
    private func detailLine(_ episode: Episode) -> String? {
        var parts: [String] = []
        if let date = DetailFormat.date(episode.airDate) {
            parts.append(date)
        }
        if let seconds = episode.seconds, seconds > 0 {
            parts.append(PlayerTime.text(Double(seconds)))
        }
        if let rating = episode.rating, rating > 0 {
            parts.append("★ " + DetailFormat.rating(rating))
        }
        if let quality = episode.quality {
            parts.append(quality)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The episode's picture, with how far through it the person is as a bar along the bottom. Without a picture, a
    /// tile of the same size so the rows line up.
    private func thumbnail(_ episode: Episode, progress: Double?) -> some View {
        BackdropView(address: episode.imageURL)
            .frame(width: Self.thumbnailWidth, height: Self.thumbnailWidth * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if let progress {
                    ProgressBar(fraction: progress).padding(6)
                }
            }
            .accessibilityHidden(true)
    }

    private static var thumbnailWidth: CGFloat {
        #if os(tvOS)
            280
        #else
            120
        #endif
    }

    private func select(_ episode: Episode, season: Season, key: String) {
        let name = "\(series.name) · S\(season.number)E\(episode.number)"
        if let position = userState.resumePosition(for: key) {
            resume = ResumeChoice(title: name, position: position) { start in
                play(episode, season: season, name: name, key: key, at: start)
            }
        } else {
            play(episode, season: season, name: name, key: key, at: nil)
        }
    }

    /// Tells the Simkl sync what this episode is, for when it is finished or marked.
    private func registerForSimkl(_ episode: Episode, season: Season, key: String) {
        simkl.register(key, as: series.tmdbID.map {
            .episode(showTMDB: $0, season: season.number, number: episode.number)
        })
    }

    private func play(_ episode: Episode, season: Season, name: String, key: String, at position: Double?) {
        registerForSimkl(episode, season: season, key: key)
        userState.markPlayed(key, parent: UserStateStore.key(playlist: series.playlist, entry: series.entryID))
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
                    containerExtension: row.containerExtension,
                    plot: nil,
                    imageURL: nil,
                    airDate: nil,
                    rating: nil,
                    quality: nil
                )
            )
        }
        load = .loaded(seasons: Self.seasons(from: episodes), details: Details())
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
                        containerExtension: episode.containerExtension,
                        plot: episode.plot,
                        imageURL: episode.imageURL,
                        airDate: episode.airDate,
                        rating: episode.rating,
                        quality: DetailFormat.quality(
                            height: episode.videoHeight,
                            video: episode.videoCodec,
                            audio: episode.audioCodec
                        )
                    )
                )
            }
            let details = Details(
                plot: info.plot,
                genre: info.genre,
                cast: info.cast,
                director: info.director,
                releaseDate: info.releaseDate,
                rating: info.rating,
                runtimeMinutes: info.episodeRunTime,
                backdrop: info.backdropURLs.first,
                trailer: info.trailer
            )
            load = .loaded(seasons: Self.seasons(from: episodes), details: details)
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
