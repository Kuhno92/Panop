import Foundation
import PanopCatalog
import PanopCore
import PanopEPG
import SwiftData

/// ``CatalogStore`` over the local-only catalog container.
///
/// A `ModelActor`, so every read and write runs off the main thread on its own
/// context. That matters twice over: a 100,000-row import must not block the
/// UI, and any save made on the main context would re-run every live `@Query`.
///
/// Rules this type keeps, and why:
///
/// - **Autosave is off.** Each batch is one explicit transaction.
/// - **Unchanged rows are never dirtied.** Each `apply(_:)` only assigns a
///   field that differs, so an unchanged batch leaves the context clean and the
///   save is skipped.
/// - **Paging sorts lexically.** SwiftData's default `String` comparator is
///   localised, and no index can serve it. The importer resumes a page from the
///   last id it saw, which is only correct if the store orders the way the
///   predicate compares, so every ordered read names `.lexical` explicitly.
actor SwiftDataCatalogStore: CatalogStore, ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer

    /// Ids per `IN (...)` lookup. Well under SQLite's variable limit.
    private static let lookupChunk = 500

    /// Rows per save. Measured on 20,000 inserts into this schema: 1,000 rows a
    /// save managed 7.2k rows/s, 5,000 managed 3.3k, and 100 to 250 managed
    /// 9.2k to 9.5k. Save cost grows faster than the batch does, so the store
    /// saves in small slices whatever batch size the importer hands it.
    private static let saveSlice = 200

    init(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        modelContainer = container
    }

    // MARK: - Entries

    func upsertEntries(_ entries: [CatalogEntry], playlist: String) throws -> UpsertSummary {
        guard !entries.isEmpty else { return UpsertSummary() }

        let ids = Array(Set(entries.map(\.id)))
        var existing: [String: CatalogEntryRecord] = [:]
        for chunk in ids.chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<CatalogEntryRecord>(
                predicate: #Predicate { $0.playlist == playlist && chunk.contains($0.id) }
            )
            for record in try modelContext.fetch(descriptor) {
                existing[record.id] = record
            }
        }

        var summary = UpsertSummary()
        for (offset, entry) in entries.enumerated() {
            if let record = existing[entry.id] {
                if record.apply(entry) {
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
            } else {
                let record = CatalogEntryRecord(playlist: playlist, entry: entry)
                modelContext.insert(record)
                // A repeated id later in this batch must update this record,
                // not insert a second one.
                existing[entry.id] = record
                summary.inserted += 1
            }
            if (offset + 1) % Self.saveSlice == 0 {
                try saveIfNeeded()
            }
        }
        try saveIfNeeded()
        return summary
    }

    func entryCount(kind: MediaKind, playlist: String) throws -> Int {
        let raw = kind.rawValue
        return try modelContext.fetchCount(FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw }
        ))
    }

    func entryIDs(kind: MediaKind, playlist: String, after: String?, limit: Int) throws -> [String] {
        let raw = kind.rawValue
        var descriptor: FetchDescriptor<CatalogEntryRecord> = if let after {
            FetchDescriptor(
                predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw && $0.id > after },
                sortBy: [SortDescriptor(\.id, comparator: .lexical)]
            )
        } else {
            FetchDescriptor(
                predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw },
                sortBy: [SortDescriptor(\.id, comparator: .lexical)]
            )
        }
        descriptor.fetchLimit = limit
        descriptor.propertiesToFetch = [\.id]
        return try modelContext.fetch(descriptor).map(\.id)
    }

    func removeEntries(ids: [String], playlist: String) throws {
        for chunk in ids.chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<CatalogEntryRecord>(
                predicate: #Predicate { $0.playlist == playlist && chunk.contains($0.id) }
            )
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
        try saveIfNeeded()
    }

    // MARK: - Categories

    func upsertCategories(_ categories: [CatalogCategory], playlist: String) throws {
        for (kind, group) in Dictionary(grouping: categories, by: \.kind) {
            let raw = kind.rawValue
            let ids = group.map(\.id)
            var existing: [String: CatalogCategoryRecord] = [:]
            for chunk in ids.chunked(into: Self.lookupChunk) {
                let descriptor = FetchDescriptor<CatalogCategoryRecord>(
                    predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw && chunk.contains($0.id) }
                )
                for record in try modelContext.fetch(descriptor) {
                    existing[record.id] = record
                }
            }
            for category in group {
                if let record = existing[category.id] {
                    _ = record.apply(category)
                } else {
                    let record = CatalogCategoryRecord(playlist: playlist, category: category)
                    modelContext.insert(record)
                    existing[category.id] = record
                }
            }
        }
        try saveIfNeeded()
    }

    func categoryIDs(kind: MediaKind, playlist: String) throws -> [String] {
        let raw = kind.rawValue
        var descriptor = FetchDescriptor<CatalogCategoryRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw }
        )
        descriptor.propertiesToFetch = [\.id]
        return try modelContext.fetch(descriptor).map(\.id)
    }

    func removeCategories(ids: [String], kind: MediaKind, playlist: String) throws {
        let raw = kind.rawValue
        for chunk in ids.chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<CatalogCategoryRecord>(
                predicate: #Predicate { $0.playlist == playlist && $0.kindRaw == raw && chunk.contains($0.id) }
            )
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
        try saveIfNeeded()
    }

    // MARK: - Guide

    func upsertEPGChannels(_ channels: [EPGChannel], playlist: String) throws {
        guard !channels.isEmpty else { return }
        var existing: [String: EPGChannelRecord] = [:]
        for chunk in channels.map(\.id).chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<EPGChannelRecord>(
                predicate: #Predicate { $0.playlist == playlist && chunk.contains($0.id) }
            )
            for record in try modelContext.fetch(descriptor) {
                existing[record.id] = record
            }
        }
        for channel in channels {
            if let record = existing[channel.id] {
                _ = record.apply(channel)
            } else {
                let record = EPGChannelRecord(playlist: playlist, channel: channel)
                modelContext.insert(record)
                existing[channel.id] = record
            }
        }
        try saveIfNeeded()
    }

    func upsertProgrammes(_ programmes: [EPGProgramme], playlist: String) throws -> UpsertSummary {
        guard let first = programmes.first else { return UpsertSummary() }

        // One fetch for the whole batch. A batch is mostly consecutive
        // programmes of a few channels, so bounding by those channels and the
        // batch's time span reads little more than the rows it will compare.
        let channelKeys = Array(Set(programmes.map { EPGKey.normalize($0.channelID) }))
        let earliest = programmes.reduce(first.start) { min($0, $1.start) }
        let latest = programmes.reduce(first.start) { max($0, $1.start) }

        var existing: [ProgrammeKey: EPGProgrammeRecord] = [:]
        for chunk in channelKeys.chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<EPGProgrammeRecord>(
                predicate: #Predicate {
                    $0.playlist == playlist && chunk.contains($0.channelKey)
                        && $0.start >= earliest && $0.start <= latest
                }
            )
            for record in try modelContext.fetch(descriptor) {
                existing[ProgrammeKey(channelKey: record.channelKey, start: record.start)] = record
            }
        }

        var summary = UpsertSummary()
        for (offset, programme) in programmes.enumerated() {
            let key = ProgrammeKey(programme)
            if let record = existing[key] {
                if record.apply(programme) {
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
            } else {
                let record = EPGProgrammeRecord(playlist: playlist, programme: programme)
                modelContext.insert(record)
                existing[key] = record
                summary.inserted += 1
            }
            if (offset + 1) % Self.saveSlice == 0 {
                try saveIfNeeded()
            }
        }
        try saveIfNeeded()
        return summary
    }

    func programmeCount(playlist: String, endingAfter: Date) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.stop > endingAfter }
        ))
    }

    func epgChannelIDs(playlist: String) throws -> [String] {
        var descriptor = FetchDescriptor<EPGChannelRecord>(predicate: #Predicate { $0.playlist == playlist })
        descriptor.propertiesToFetch = [\.id]
        return try modelContext.fetch(descriptor).map(\.id)
    }

    /// One range read on the `(playlist, channelKey, start)` index. Deliberately
    /// unsorted: the caller only needs the set, and a sort here would cost more
    /// than the read.
    func programmeStarts(playlist: String, channelKey: String, endingAfter: Date) throws -> [Date] {
        var descriptor = FetchDescriptor<EPGProgrammeRecord>(
            predicate: #Predicate {
                $0.playlist == playlist && $0.channelKey == channelKey && $0.stop > endingAfter
            }
        )
        descriptor.propertiesToFetch = [\.start]
        return try modelContext.fetch(descriptor).map(\.start)
    }

    func removeProgrammes(playlist: String, channelKey: String, starts: [Date]) throws {
        for chunk in starts.chunked(into: Self.lookupChunk) {
            let descriptor = FetchDescriptor<EPGProgrammeRecord>(
                predicate: #Predicate {
                    $0.playlist == playlist && $0.channelKey == channelKey && chunk.contains($0.start)
                }
            )
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
        try saveIfNeeded()
    }

    func removeProgrammes(endedBefore date: Date, playlist: String) throws -> Int {
        let predicate = #Predicate<EPGProgrammeRecord> { $0.playlist == playlist && $0.stop <= date }
        let count = try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
        guard count > 0 else { return 0 }
        try modelContext.delete(model: EPGProgrammeRecord.self, where: predicate)
        try saveIfNeeded()
        return count
    }

    // MARK: - Removal

    func removePlaylist(_ playlist: String) throws {
        // No cascade exists from a playlist to its rows (the catalog has no
        // relationships), so each table is cleared by its playlist column.
        try modelContext.delete(model: CatalogEntryRecord.self, where: #Predicate { $0.playlist == playlist })
        try modelContext.delete(model: CatalogCategoryRecord.self, where: #Predicate { $0.playlist == playlist })
        try modelContext.delete(model: EPGChannelRecord.self, where: #Predicate { $0.playlist == playlist })
        try modelContext.delete(model: EPGProgrammeRecord.self, where: #Predicate { $0.playlist == playlist })
        try modelContext.delete(model: SyncStateRecord.self, where: #Predicate { $0.playlist == playlist })
        try saveIfNeeded()
    }

    // MARK: - State

    func syncState(playlist: String) throws -> SyncState? {
        try fetchStateRecord(playlist)?.state
    }

    func saveSyncState(_ state: SyncState, playlist: String) throws {
        if let record = try fetchStateRecord(playlist) {
            record.importCounter = state.importCounter
            record.digest = state.digest
            record.lastCompleted = state.lastCompleted
        } else {
            modelContext.insert(SyncStateRecord(playlist: playlist, state: state))
        }
        try saveIfNeeded()
    }

    private func fetchStateRecord(_ playlist: String) throws -> SyncStateRecord? {
        var descriptor = FetchDescriptor<SyncStateRecord>(predicate: #Predicate { $0.playlist == playlist })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Saving

    /// Saves only when something changed, so an unchanged batch costs no write.
    /// A failed save is rolled back, leaving the context clean for the next call.
    private func saveIfNeeded() throws {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

extension Array {
    /// `nonisolated` because the project defaults to the main actor, and this is
    /// called from the catalog actor.
    nonisolated func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
