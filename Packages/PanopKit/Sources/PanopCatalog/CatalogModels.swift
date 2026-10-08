import Foundation
import PanopCore
import PanopEPG

/// One browsable item, in the shape the UI wants regardless of which provider
/// protocol it came from.
///
/// Live channels, movies and series shells all use this. Episodes are not
/// stored: like the Xtream API they are fetched on demand when a series is
/// opened, which keeps the catalog an order of magnitude smaller.
public struct CatalogEntry: Sendable, Equatable, Hashable {
    /// Stable identity within one playlist. It must not change between
    /// imports, because favourites and watch progress are keyed by it.
    /// See ``CatalogID``.
    public var id: String
    public var kind: MediaKind
    public var name: String
    /// The provider's category. For M3U this is the group title itself.
    public var groupID: String?
    public var groupName: String?
    public var iconURL: String?
    /// Wide artwork, where the provider's list gives it (a series' backdrop).
    public var backdropURL: String?
    /// Lower-cased EPG channel id, ready to match against guide channels.
    public var epgKey: String?
    /// A complete URL when the source supplies one (M3U, or an Xtream
    /// `direct_source`). Nil for Xtream rows, which build it from `remoteID`.
    public var streamURL: String?
    /// The provider's own numeric id, as a string. Xtream only.
    public var remoteID: String?
    public var containerExtension: String?
    public var sortNumber: Int?
    public var hasArchive: Bool
    public var archiveDays: Int?
    public var addedAt: Date?
    public var rating: Double?
    public var plot: String?
    /// For an episode grouped under a series built from an M3U file, that series' id. Nil for
    /// everything else, including the series themselves.
    public var seriesID: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    /// The title's id at TMDB when the provider gives it: an exact key for matching the entry to
    /// other lists of titles. Nothing here ever contacts TMDB.
    public var tmdbID: Int?
    /// Adult content, by the provider's own flag or the name of its category. Kept out of
    /// anything suggested to the person.
    public var isAdult: Bool
    /// The release year: the provider's, or the one written in the title.
    public var year: Int?
    /// As the provider writes it, such as `Krimi / Drama`.
    public var genre: String?
    public var cast: String?
    /// For a live channel with a guide key: whether it is the first in the playlist to have that key, so a list that
    /// shows one channel per guide shows this one. True for every other entry, and for a channel with no key.
    public var isGuideLead: Bool
    /// The same within its category: the first channel of that category with its guide key. A category's list shows
    /// these, so a variant that lives in another category is not missing from this one.
    public var isCategoryLead: Bool

    public init(
        id: String,
        kind: MediaKind,
        name: String,
        groupID: String? = nil,
        groupName: String? = nil,
        iconURL: String? = nil,
        backdropURL: String? = nil,
        epgKey: String? = nil,
        streamURL: String? = nil,
        remoteID: String? = nil,
        containerExtension: String? = nil,
        sortNumber: Int? = nil,
        hasArchive: Bool = false,
        archiveDays: Int? = nil,
        addedAt: Date? = nil,
        rating: Double? = nil,
        plot: String? = nil,
        seriesID: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        tmdbID: Int? = nil,
        isAdult: Bool = false,
        year: Int? = nil,
        genre: String? = nil,
        cast: String? = nil,
        isGuideLead: Bool = true,
        isCategoryLead: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.groupID = groupID
        self.groupName = groupName
        self.iconURL = iconURL
        self.backdropURL = backdropURL
        self.epgKey = epgKey
        self.streamURL = streamURL
        self.remoteID = remoteID
        self.containerExtension = containerExtension
        self.sortNumber = sortNumber
        self.hasArchive = hasArchive
        self.archiveDays = archiveDays
        self.addedAt = addedAt
        self.rating = rating
        self.plot = plot
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.tmdbID = tmdbID
        self.isAdult = isAdult
        self.year = year
        self.genre = genre
        self.cast = cast
        self.isGuideLead = isGuideLead
        self.isCategoryLead = isCategoryLead
    }
}

public struct CatalogCategory: Sendable, Equatable, Hashable {
    /// Unique within a playlist and kind.
    public var id: String
    public var kind: MediaKind
    public var name: String
    public var parentID: String?
    /// Where the provider lists it, from 1. The order a provider chose is the order its own apps
    /// show, and is lost if categories are sorted by name.
    public var sortNumber: Int?

    public init(id: String, kind: MediaKind, name: String, parentID: String? = nil, sortNumber: Int? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parentID = parentID
        self.sortNumber = sortNumber
    }
}

/// How many rows a batch touched, so a store can report that a re-import of an
/// unchanged catalog wrote nothing.
public struct UpsertSummary: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var unchanged = 0

    public init(inserted: Int = 0, updated: Int = 0, unchanged: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
    }

    public var total: Int {
        inserted + updated + unchanged
    }

    public static func += (lhs: inout UpsertSummary, rhs: UpsertSummary) {
        lhs.inserted += rhs.inserted
        lhs.updated += rhs.updated
        lhs.unchanged += rhs.unchanged
    }
}

/// Identifies one guide row: a channel at a start time.
public struct ProgrammeKey: Sendable, Hashable {
    /// Lower-cased channel id, so `ARD.de` and `ard.de` are the same channel.
    public var channelKey: String
    public var start: Date

    public init(channelKey: String, start: Date) {
        self.channelKey = channelKey
        self.start = start
    }

    public init(_ programme: EPGProgramme) {
        self.init(channelKey: EPGKey.normalize(programme.channelID), start: programme.start)
    }
}

/// Per-playlist bookkeeping that outlives one import.
public struct SyncState: Sendable, Equatable {
    /// Bumped at the start of every catalog import. A deferred removal records
    /// it, so a confirmation that arrives after a newer import is refused.
    public var importCounter: Int
    /// Digest of the last M3U file that imported to completion.
    public var digest: String?
    public var lastCompleted: Date?

    public init(importCounter: Int = 0, digest: String? = nil, lastCompleted: Date? = nil) {
        self.importCounter = importCounter
        self.digest = digest
        self.lastCompleted = lastCompleted
    }
}

/// Matching a playlist entry to a guide channel is case-insensitive in
/// practice: providers write `ARD.de` in one place and `ard.de` in another.
public enum EPGKey {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
