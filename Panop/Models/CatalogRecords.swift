import Foundation
import PanopCatalog
import PanopCore
import PanopEPG
import SwiftData

// The catalog container's models. They live in the local-only container, so
// they are free of CloudKit's schema rules. See docs/adr/0003-two-model-containers.md.
//
// **No `#Unique` on the big tables, on purpose.** A composite unique constraint
// measured about 35% slower on bulk insert (7.2k against 10.8k rows/s), and it
// would only guard against something the store already rules out: every write
// goes through one actor that looks rows up and inserts in a single call with no
// suspension between, so two writers cannot both miss the same id. A plain index
// on the same columns serves the same lookups. `SwiftDataCatalogStoreTests`
// asserts that no import path can produce a duplicate row.
//
// Each type mirrors one PanopCatalog value type and knows how to apply it
// *without dirtying itself when nothing changed*. That is the point of
// `apply(_:)`: a SwiftData context with no dirty objects skips its save, so
// re-importing an unchanged 80,000-row catalog costs reads, not writes.

/// One channel, movie or series shell.
@Model
final class CatalogEntryRecord {
    // (playlist, id) serves the upsert lookup. (playlist, kind, id) serves the
    // per-kind counts the importer makes eight times per run, and the ordered
    // sweep. Dropping it made those counts scan the table (0.01 s became 0.15 s
    // each) and slowed every refresh by more than it saved on first import.
    // Browse indexes arrive with the browse screens, so they are shaped by real
    // queries rather than guessed.
    #Index<CatalogEntryRecord>([\.playlist, \.id], [\.playlist, \.kindRaw, \.id])

    var playlist: String
    var id: String
    var kindRaw: String
    var name: String
    var groupID: String?
    var groupName: String?
    var iconURL: String?
    var epgKey: String?
    var streamURL: String?
    var remoteID: String?
    var containerExtension: String?
    var sortNumber: Int?
    var hasArchive: Bool
    var archiveDays: Int?
    var addedAt: Date?
    var rating: Double?
    var plot: String?

    init(playlist: String, entry: CatalogEntry) {
        self.playlist = playlist
        id = entry.id
        kindRaw = entry.kind.rawValue
        name = entry.name
        groupID = entry.groupID
        groupName = entry.groupName
        iconURL = entry.iconURL
        epgKey = entry.epgKey
        streamURL = entry.streamURL
        remoteID = entry.remoteID
        containerExtension = entry.containerExtension
        sortNumber = entry.sortNumber
        hasArchive = entry.hasArchive
        archiveDays = entry.archiveDays
        addedAt = entry.addedAt
        rating = entry.rating
        plot = entry.plot
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .unknown
    }

    /// Copies fields that differ. Returns false, having touched nothing, when
    /// the record already matches.
    func apply(_ entry: CatalogEntry) -> Bool {
        var changed = false
        func assign<Value: Equatable>(_ path: ReferenceWritableKeyPath<CatalogEntryRecord, Value>, _ value: Value) {
            if self[keyPath: path] != value {
                self[keyPath: path] = value
                changed = true
            }
        }
        assign(\.kindRaw, entry.kind.rawValue)
        assign(\.name, entry.name)
        assign(\.groupID, entry.groupID)
        assign(\.groupName, entry.groupName)
        assign(\.iconURL, entry.iconURL)
        assign(\.epgKey, entry.epgKey)
        assign(\.streamURL, entry.streamURL)
        assign(\.remoteID, entry.remoteID)
        assign(\.containerExtension, entry.containerExtension)
        assign(\.sortNumber, entry.sortNumber)
        assign(\.hasArchive, entry.hasArchive)
        assign(\.archiveDays, entry.archiveDays)
        assign(\.addedAt, entry.addedAt)
        assign(\.rating, entry.rating)
        assign(\.plot, entry.plot)
        return changed
    }
}

@Model
final class CatalogCategoryRecord {
    #Unique<CatalogCategoryRecord>([\.playlist, \.kindRaw, \.id])
    #Index<CatalogCategoryRecord>([\.playlist, \.kindRaw])

    var playlist: String
    var kindRaw: String
    var id: String
    var name: String
    var parentID: String?

    init(playlist: String, category: CatalogCategory) {
        self.playlist = playlist
        kindRaw = category.kind.rawValue
        id = category.id
        name = category.name
        parentID = category.parentID
    }

    func apply(_ category: CatalogCategory) -> Bool {
        var changed = false
        if name != category.name {
            name = category.name
            changed = true
        }
        if parentID != category.parentID {
            parentID = category.parentID
            changed = true
        }
        return changed
    }
}

@Model
final class EPGChannelRecord {
    #Unique<EPGChannelRecord>([\.playlist, \.id])

    var playlist: String
    var id: String
    /// Joined with U+001F, which no channel name contains. A `[String]` would
    /// be stored as an archived blob and decoded on every read.
    var displayNamesRaw: String
    var iconURL: String?

    init(playlist: String, channel: EPGChannel) {
        self.playlist = playlist
        id = channel.id
        displayNamesRaw = Self.join(channel.displayNames)
        iconURL = channel.iconURL
    }

    var displayNames: [String] {
        displayNamesRaw.isEmpty ? [] : displayNamesRaw.components(separatedBy: "\u{1F}")
    }

    func apply(_ channel: EPGChannel) -> Bool {
        var changed = false
        let names = Self.join(channel.displayNames)
        if displayNamesRaw != names {
            displayNamesRaw = names
            changed = true
        }
        if iconURL != channel.iconURL {
            iconURL = channel.iconURL
            changed = true
        }
        return changed
    }

    private static func join(_ names: [String]) -> String {
        names.joined(separator: "\u{1F}")
    }
}

@Model
final class EPGProgrammeRecord {
    // Channel then time: the upsert lookup, the importer's per-channel sweep and
    // the guide screen's range read. And end time: the count and the expiry.
    #Index<EPGProgrammeRecord>([\.playlist, \.channelKey, \.start], [\.playlist, \.stop])

    var playlist: String
    /// Lower-cased channel id, the identity the store keys on.
    var channelKey: String
    /// The id as the guide wrote it, kept for display and debugging.
    var channelID: String
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var details: String?
    var categoriesRaw: String
    var iconURL: String?
    var episodeNumber: String?
    var language: String?

    init(playlist: String, programme: EPGProgramme) {
        self.playlist = playlist
        channelKey = EPGKey.normalize(programme.channelID)
        channelID = programme.channelID
        start = programme.start
        stop = programme.stop
        title = programme.title
        subtitle = programme.subtitle
        details = programme.details
        categoriesRaw = programme.categories.joined(separator: "\u{1F}")
        iconURL = programme.iconURL
        episodeNumber = programme.episodeNumber
        language = programme.language
    }

    var categories: [String] {
        categoriesRaw.isEmpty ? [] : categoriesRaw.components(separatedBy: "\u{1F}")
    }

    func apply(_ programme: EPGProgramme) -> Bool {
        var changed = false
        func assign<Value: Equatable>(_ path: ReferenceWritableKeyPath<EPGProgrammeRecord, Value>, _ value: Value) {
            if self[keyPath: path] != value {
                self[keyPath: path] = value
                changed = true
            }
        }
        assign(\.channelID, programme.channelID)
        assign(\.stop, programme.stop)
        assign(\.title, programme.title)
        assign(\.subtitle, programme.subtitle)
        assign(\.details, programme.details)
        assign(\.categoriesRaw, programme.categories.joined(separator: "\u{1F}"))
        assign(\.iconURL, programme.iconURL)
        assign(\.episodeNumber, programme.episodeNumber)
        assign(\.language, programme.language)
        return changed
    }
}

/// Per-playlist bookkeeping: the import counter, the last M3U digest, and when
/// the last import completed.
@Model
final class SyncStateRecord {
    #Unique<SyncStateRecord>([\.playlist])

    var playlist: String
    var importCounter: Int
    var digest: String?
    var lastCompleted: Date?

    init(playlist: String, state: SyncState) {
        self.playlist = playlist
        importCounter = state.importCounter
        digest = state.digest
        lastCompleted = state.lastCompleted
    }

    var state: SyncState {
        SyncState(importCounter: importCounter, digest: digest, lastCompleted: lastCompleted)
    }
}
