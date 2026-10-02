import Foundation
import PanopCore

/// A title of the person's own library, as the recommendations see it. Only plain values: the
/// app builds these from its catalog, and nothing here knows where they came from.
public struct DiscoveryTitle: Sendable, Equatable, Hashable, Identifiable {
    /// Playlist and entry together, the key the rest of the app uses for the title.
    public var key: String
    public var kind: MediaKind
    public var name: String
    /// The provider's category.
    public var category: String?
    public var year: Int?
    /// 0 to 10, as the provider gives it.
    public var rating: Double?
    /// Lower-cased, one entry per genre (see ``TitleText/genres(from:)``).
    public var genres: Set<String>
    /// Lower-cased names of the leading cast.
    public var cast: Set<String>
    public var tmdbID: Int?
    public var isAdult: Bool
    public var hasPoster: Bool

    public var id: String {
        key
    }

    public init(
        key: String,
        kind: MediaKind,
        name: String,
        category: String? = nil,
        year: Int? = nil,
        rating: Double? = nil,
        genres: Set<String> = [],
        cast: Set<String> = [],
        tmdbID: Int? = nil,
        isAdult: Bool = false,
        hasPoster: Bool = true
    ) {
        self.key = key
        self.kind = kind
        self.name = name
        self.category = category
        self.year = year
        self.rating = rating
        self.genres = genres
        self.cast = cast
        self.tmdbID = tmdbID
        self.isAdult = isAdult
        self.hasPoster = hasPoster
    }
}

/// A title the person has shown a taste for, and how strongly.
public struct DiscoverySeed: Sendable, Equatable {
    public var key: String
    public var weight: Double

    public init(key: String, weight: Double) {
        self.key = key
        self.weight = weight
    }
}

/// One place on a list of what is popular, matched to the library by the title's TMDB id.
public struct TrendingEntry: Sendable, Equatable, Codable {
    public var kind: MediaKind
    public var tmdbID: Int
    /// Higher is more popular.
    public var score: Double
    /// Where the list's own page for the title is, for the lists whose terms ask for a link back.
    public var link: String?

    public init(kind: MediaKind, tmdbID: Int, score: Double, link: String? = nil) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.score = score
        self.link = link
    }
}

/// How often a title has been opened.
public struct PlayCount: Sendable, Equatable {
    public var key: String
    public var times: Int

    public init(key: String, times: Int) {
        self.key = key
        self.times = times
    }
}

/// Everything the rails are made from.
public struct DiscoveryInput: Sendable {
    /// The candidates: a bounded selection of the library, not all of it.
    public var titles: [DiscoveryTitle]
    public var seeds: [DiscoverySeed]
    /// What is known about each seed, which may not be among the candidates.
    public var seedTitles: [String: DiscoveryTitle]
    /// Watched, or being watched: never suggested again.
    public var unavailable: Set<String>
    public var hidden: Set<String>
    /// Names of the categories the person hid, by kind.
    public var hiddenCategories: [MediaKind: Set<String>]
    public var trending: [TrendingEntry]
    /// Titles the person plans to watch, by TMDB id, in the order they keep them.
    public var planned: [TrendingEntry]
    /// TMDB ids of what they have finished somewhere else: never suggested.
    public var finishedElsewhere: Set<Int>
    public var playCounts: [PlayCount]
    public var now: Date

    public init(
        titles: [DiscoveryTitle],
        seeds: [DiscoverySeed] = [],
        seedTitles: [String: DiscoveryTitle] = [:],
        unavailable: Set<String> = [],
        hidden: Set<String> = [],
        hiddenCategories: [MediaKind: Set<String>] = [:],
        trending: [TrendingEntry] = [],
        planned: [TrendingEntry] = [],
        finishedElsewhere: Set<Int> = [],
        playCounts: [PlayCount] = [],
        now: Date
    ) {
        self.titles = titles
        self.seeds = seeds
        self.seedTitles = seedTitles
        self.unavailable = unavailable
        self.hidden = hidden
        self.hiddenCategories = hiddenCategories
        self.trending = trending
        self.planned = planned
        self.finishedElsewhere = finishedElsewhere
        self.playCounts = playCounts
        self.now = now
    }
}

public enum RailKind: Sendable, Hashable, Codable {
    /// What the person plans to watch, from their own list.
    case onYourList
    case trending(MediaKind)
    case becauseYouWatched(seed: String)
    case newReleases(MediaKind)
    case mostWatched
    case topRated(MediaKind)
    case genre(MediaKind, String)
    case franchise(String)
    case classics(MediaKind)
    case decade(MediaKind, Int)
    case pickOfTheDay(MediaKind)
}

/// A row of titles under one heading. It holds keys, in the order to show them; the app looks the
/// titles up.
public struct Rail: Sendable, Equatable, Identifiable, Codable {
    public var kind: RailKind
    public var keys: [String]
    /// What the heading is about: the title it was drawn from, the genre, the franchise.
    public var subject: String?

    public var id: String {
        switch kind {
        case let .trending(kind): "trending.\(kind.rawValue)"
        case let .becauseYouWatched(seed): "because.\(seed)"
        case let .newReleases(kind): "new.\(kind.rawValue)"
        case .onYourList: "onYourList"
        case .mostWatched: "mostWatched"
        case let .topRated(kind): "top.\(kind.rawValue)"
        case let .genre(kind, genre): "genre.\(kind.rawValue).\(genre)"
        case let .franchise(stem): "franchise.\(stem)"
        case let .classics(kind): "classics.\(kind.rawValue)"
        case let .decade(kind, decade): "decade.\(kind.rawValue).\(decade)"
        case let .pickOfTheDay(kind): "pick.\(kind.rawValue)"
        }
    }

    public init(kind: RailKind, keys: [String], subject: String? = nil) {
        self.kind = kind
        self.keys = keys
        self.subject = subject
    }
}
