import Foundation
import PanopCore

/// The episodes of one show that a person has watched, by season.
public struct SimklWatchedShow: Sendable, Equatable, Codable {
    public var tmdbID: Int
    public var seasons: [SimklWatchedSeason]

    public init(tmdbID: Int, seasons: [SimklWatchedSeason]) {
        self.tmdbID = tmdbID
        self.seasons = seasons
    }
}

public struct SimklWatchedSeason: Sendable, Equatable, Codable {
    public var number: Int
    public var episodes: [Int]

    public init(number: Int, episodes: [Int]) {
        self.number = number
        self.episodes = episodes
    }
}

public extension SimklClient {
    /// Every show the person has watched anything of, with the episodes they have watched.
    ///
    /// Built from Simkl's documentation and **not yet seen against a live account**: `extended=full` with
    /// `episode_watched_at=yes` is what is asked for, since the plain list (see ``library(since:)``) carries no
    /// episodes.
    /// Whatever comes back that has no show id or no seasons is left out rather than failing the lot, and an answer
    /// with
    /// no `seasons` at all gives an empty list, which shows no badges: the safe way to be wrong.
    func watchedEpisodes() async throws -> [SimklWatchedShow] {
        let data = try await get("/sync/all-items/shows", query: [
            URLQueryItem(name: "extended", value: "full"),
            URLQueryItem(name: "episode_watched_at", value: "yes")
        ])
        guard let reply = try? JSONDecoder().decode(WatchedReply.self, from: data) else { throw SimklError.undecodable }
        return reply.shows
    }
}

private struct WatchedReply: Decodable {
    var shows: [SimklWatchedShow]

    private enum Keys: String, CodingKey { case shows }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let entries = (try? container.decodeIfPresent([Lenient<Entry>].self, forKey: .shows)) ?? []
        shows = entries.compactMap { $0.value?.watched }
    }
}

private struct Lenient<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct Entry: Decodable {
    var show: Stub?
    var seasons: [Lenient<Season>]?

    var watched: SimklWatchedShow? {
        guard let id = show?.ids?.tmdb, id > 0 else { return nil }
        let watchedSeasons = (seasons ?? []).compactMap { $0.value?.watched }.filter { !$0.episodes.isEmpty }
        return watchedSeasons.isEmpty ? nil : SimklWatchedShow(tmdbID: id, seasons: watchedSeasons)
    }
}

private struct Stub: Decodable {
    var ids: IDs?
}

private struct IDs: Decodable {
    var tmdb: Int?

    private enum Keys: String, CodingKey { case tmdb }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        // A number in one file and a string in another.
        tmdb = (try? container.decodeIfPresent(Int.self, forKey: .tmdb))
            ?? (try? container.decodeIfPresent(String.self, forKey: .tmdb)).flatMap { $0.flatMap(Int.init) }
    }
}

private struct Season: Decodable {
    var number: Int?
    var episodes: [Lenient<Episode>]?

    var watched: SimklWatchedSeason? {
        guard let number else { return nil }
        return SimklWatchedSeason(number: number, episodes: (episodes ?? []).compactMap { $0.value?.number })
    }
}

private struct Episode: Decodable {
    var number: Int?

    private enum Keys: String, CodingKey { case number }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        number = (try? container.decodeIfPresent(Int.self, forKey: .number))
    }
}
