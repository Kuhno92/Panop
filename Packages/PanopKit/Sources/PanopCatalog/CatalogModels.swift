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

    public init(
        id: String,
        kind: MediaKind,
        name: String,
        groupID: String? = nil,
        groupName: String? = nil,
        iconURL: String? = nil,
        epgKey: String? = nil,
        streamURL: String? = nil,
        remoteID: String? = nil,
        containerExtension: String? = nil,
        sortNumber: Int? = nil,
        hasArchive: Bool = false,
        archiveDays: Int? = nil,
        addedAt: Date? = nil,
        rating: Double? = nil,
        plot: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.groupID = groupID
        self.groupName = groupName
        self.iconURL = iconURL
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
    }
}

public struct CatalogCategory: Sendable, Equatable, Hashable {
    /// Unique within a playlist and kind.
    public var id: String
    public var kind: MediaKind
    public var name: String
    public var parentID: String?

    public init(id: String, kind: MediaKind, name: String, parentID: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parentID = parentID
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
///
/// Ordered so a store can page through keys without holding them all.
public struct ProgrammeKey: Sendable, Hashable, Comparable {
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

    /// Orders by binary comparison of the channel key, never localised, so a
    /// store's own ordering can agree with it.
    public static func < (lhs: ProgrammeKey, rhs: ProgrammeKey) -> Bool {
        if lhs.channelKey != rhs.channelKey {
            return lhs.channelKey.utf8.lexicographicallyPrecedes(rhs.channelKey.utf8)
        }
        return lhs.start < rhs.start
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
