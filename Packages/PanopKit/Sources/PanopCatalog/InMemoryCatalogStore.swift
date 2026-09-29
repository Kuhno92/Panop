import Foundation
import PanopCore
import PanopEPG

/// A dictionary-backed ``CatalogStore``.
///
/// The reference for the protocol's contract, and what the importer's tests run
/// against. It is not meant for a real catalog: id listings sort on every call,
/// which is fine for hundreds of rows and wrong for tens of thousands.
public actor InMemoryCatalogStore: CatalogStore {
    private struct CategoryKey: Hashable {
        var kind: MediaKind
        var id: String
    }

    private var entries: [String: [String: CatalogEntry]] = [:]
    private var categories: [String: [CategoryKey: CatalogCategory]] = [:]
    private var channels: [String: [String: EPGChannel]] = [:]
    private var programmes: [String: [ProgrammeKey: EPGProgramme]] = [:]
    private var states: [String: SyncState] = [:]

    /// Rows actually written (inserted or changed), across every upsert. A
    /// re-import of an unchanged catalog must leave this untouched.
    public private(set) var writeCount = 0

    public init() {}

    // MARK: - Inspection, for tests and previews

    public func allEntries(playlist: String) -> [CatalogEntry] {
        (entries[playlist] ?? [:]).values.sorted { $0.id < $1.id }
    }

    public func allCategories(playlist: String) -> [CatalogCategory] {
        (categories[playlist] ?? [:]).values.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
    }

    public func allProgrammes(playlist: String) -> [EPGProgramme] {
        (programmes[playlist] ?? [:]).values.sorted { ($0.channelID, $0.start) < ($1.channelID, $1.start) }
    }

    public func allEPGChannels(playlist: String) -> [EPGChannel] {
        (channels[playlist] ?? [:]).values.sorted { $0.id < $1.id }
    }

    // MARK: - Entries

    public func upsertEntries(_ batch: [CatalogEntry], playlist: String) -> UpsertSummary {
        var summary = UpsertSummary()
        for entry in batch {
            switch entries[playlist, default: [:]][entry.id] {
            case nil:
                summary.inserted += 1
            case let existing? where existing == entry:
                summary.unchanged += 1
                continue
            default:
                summary.updated += 1
            }
            entries[playlist, default: [:]][entry.id] = entry
            writeCount += 1
        }
        return summary
    }

    public func entryCount(kind: MediaKind, playlist: String) -> Int {
        (entries[playlist] ?? [:]).values.filter { $0.kind == kind }.count
    }

    public func entryIDs(kind: MediaKind, playlist: String, after: String?, limit: Int) -> [String] {
        let ids = (entries[playlist] ?? [:]).values.filter { $0.kind == kind }.map(\.id)
        let ordered = ids.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let remaining = after.map { cursor in
            ordered.filter { cursor.utf8.lexicographicallyPrecedes($0.utf8) }
        } ?? ordered
        return Array(remaining.prefix(limit))
    }

    public func removeEntries(ids: [String], playlist: String) {
        for id in ids {
            entries[playlist]?[id] = nil
        }
    }

    // MARK: - Categories

    public func upsertCategories(_ batch: [CatalogCategory], playlist: String) {
        for category in batch {
            let key = CategoryKey(kind: category.kind, id: category.id)
            if categories[playlist, default: [:]][key] != category {
                categories[playlist, default: [:]][key] = category
                writeCount += 1
            }
        }
    }

    public func categoryIDs(kind: MediaKind, playlist: String) -> [String] {
        (categories[playlist] ?? [:]).keys.filter { $0.kind == kind }.map(\.id).sorted()
    }

    public func removeCategories(ids: [String], kind: MediaKind, playlist: String) {
        for id in ids {
            categories[playlist]?[CategoryKey(kind: kind, id: id)] = nil
        }
    }

    // MARK: - Guide

    public func upsertEPGChannels(_ batch: [EPGChannel], playlist: String) {
        for channel in batch where channels[playlist, default: [:]][channel.id] != channel {
            channels[playlist, default: [:]][channel.id] = channel
        }
    }

    public func upsertProgrammes(_ batch: [EPGProgramme], playlist: String) -> UpsertSummary {
        var summary = UpsertSummary()
        for programme in batch {
            let key = ProgrammeKey(programme)
            switch programmes[playlist, default: [:]][key] {
            case nil:
                summary.inserted += 1
            case let existing? where existing == programme:
                summary.unchanged += 1
                continue
            default:
                summary.updated += 1
            }
            programmes[playlist, default: [:]][key] = programme
            writeCount += 1
        }
        return summary
    }

    public func programmeCount(playlist: String, endingAfter: Date) -> Int {
        (programmes[playlist] ?? [:]).values.filter { $0.stop > endingAfter }.count
    }

    public func epgChannelIDs(playlist: String) -> [String] {
        (channels[playlist] ?? [:]).keys.sorted()
    }

    public func programmeStarts(playlist: String, channelKey: String, endingAfter: Date) -> [Date] {
        (programmes[playlist] ?? [:])
            .filter { $0.key.channelKey == channelKey && $0.value.stop > endingAfter }
            .map(\.key.start)
            .sorted()
    }

    public func removeProgrammes(playlist: String, channelKey: String, starts: [Date]) {
        for start in starts {
            programmes[playlist]?[ProgrammeKey(channelKey: channelKey, start: start)] = nil
        }
    }

    public func removeProgrammes(endedBefore date: Date, playlist: String) -> Int {
        let expired = (programmes[playlist] ?? [:]).filter { $0.value.stop <= date }.keys
        for key in expired {
            programmes[playlist]?[key] = nil
        }
        return expired.count
    }

    // MARK: - State

    public func syncState(playlist: String) -> SyncState? {
        states[playlist]
    }

    public func saveSyncState(_ state: SyncState, playlist: String) {
        states[playlist] = state
    }
}
