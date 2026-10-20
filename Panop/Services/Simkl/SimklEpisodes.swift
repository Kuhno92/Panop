import Foundation
import Observation
import PanopSimkl

private struct EpisodesSnapshot: Codable {
    /// Bumped when what is asked of Simkl changes, so what was saved from an older request is fetched again.
    static let currentFormat = 1

    var format: Int?
    var activities: String
    var shows: [SimklWatchedShow]
}

/// The episodes the person's Simkl account says they have watched, kept on disk like their lists (`SimklLibrary`) and
/// fetched the same way: only when Simkl says something changed. Unlike the lists they are asked for when a series page
/// opens, not when the app does: they are the heaviest thing asked of Simkl, and only a series page uses them.
@MainActor
@Observable
final class SimklEpisodes {
    /// Show (TMDB id), then season, then the episode numbers.
    private(set) var watched: [Int: [Int: Set<Int>]]

    private let activities: @Sendable () async throws -> SimklActivities
    private let fetch: @Sendable () async throws -> [SimklWatchedShow]
    private let cacheURL: URL?
    @ObservationIgnored private var seen: String?

    init(
        cacheURL: URL? = SimklEpisodes.defaultCacheURL,
        activities: @escaping @Sendable () async throws -> SimklActivities,
        fetch: @escaping @Sendable () async throws -> [SimklWatchedShow]
    ) {
        self.cacheURL = cacheURL
        self.activities = activities
        self.fetch = fetch
        let saved = Self.load(cacheURL)
        watched = Self.index(saved?.shows ?? [])
        seen = saved?.activities
    }

    /// Nothing for a show with no TMDB id, which is how a show is joined to Simkl's.
    func isWatched(show: Int?, season: Int, episode: Int) -> Bool {
        show.flatMap { watched[$0]?[season]?.contains(episode) } ?? false
    }

    func refresh() async {
        guard let latest = try? await activities().all else { return }
        guard latest != seen || seen == nil else { return }
        guard let fresh = try? await fetch() else { return }
        watched = Self.index(fresh)
        seen = latest
        save(EpisodesSnapshot(format: EpisodesSnapshot.currentFormat, activities: latest, shows: fresh))
    }

    /// Forgets them, for when the account is disconnected: they were that account's.
    func clear() {
        watched = [:]
        seen = nil
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    private static func index(_ shows: [SimklWatchedShow]) -> [Int: [Int: Set<Int>]] {
        var result: [Int: [Int: Set<Int>]] = [:]
        for show in shows {
            for season in show.seasons {
                result[show.tmdbID, default: [:]][season.number, default: []].formUnion(season.episodes)
            }
        }
        return result
    }

    private func save(_ snapshot: EpisodesSnapshot) {
        guard let cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func load(_ url: URL?) -> EpisodesSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let snapshot = try? JSONDecoder().decode(EpisodesSnapshot.self, from: data)
        return snapshot?.format == EpisodesSnapshot.currentFormat ? snapshot : nil
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Simkl", isDirectory: true)
            .appendingPathComponent("episodes.json")
    }
}
