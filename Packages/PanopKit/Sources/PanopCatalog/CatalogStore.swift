import Foundation
import PanopCore
import PanopEPG

/// Where the catalog lives. The importer talks only to this, so the app
/// implements it over SwiftData and another platform can implement it over
/// SQLite without touching any import logic.
///
/// Every call is scoped to a `playlist` identifier chosen by the caller.
///
/// **What a store must guarantee**
///
/// - `upsert*` is keyed by `(playlist, id)` and must not write a row whose
///   content did not change. Re-importing an unchanged 80,000-row catalog is
///   the common case, and it should cost reads, not 80,000 writes.
/// - Paged id listings use **binary** ordering (code-unit order), never a
///   localised collation. The importer resumes a page from the last id it saw,
///   which is only sound if the store orders the way it compares.
/// - Removals are by explicit id or key. The store never decides on its own what
///   is stale; that decision, and the safety checks around it, live in
///   ``CatalogImporter``.
public protocol CatalogStore: Sendable {
    // MARK: - Entries

    func upsertEntries(_ entries: [CatalogEntry], playlist: String) async throws -> UpsertSummary

    func entryCount(kind: MediaKind, playlist: String) async throws -> Int

    /// Ids of `kind` strictly greater than `after`, ascending, at most `limit`.
    func entryIDs(kind: MediaKind, playlist: String, after: String?, limit: Int) async throws -> [String]

    func removeEntries(ids: [String], playlist: String) async throws

    // MARK: - Categories

    func upsertCategories(_ categories: [CatalogCategory], playlist: String) async throws

    /// Categories are few (hundreds to low thousands), so no paging.
    func categoryIDs(kind: MediaKind, playlist: String) async throws -> [String]

    func removeCategories(ids: [String], kind: MediaKind, playlist: String) async throws

    // MARK: - Guide

    func upsertEPGChannels(_ channels: [EPGChannel], playlist: String) async throws

    func upsertProgrammes(_ programmes: [EPGProgramme], playlist: String) async throws -> UpsertSummary

    func programmeCount(playlist: String, endingAfter: Date) async throws -> Int

    /// Channel ids of the guide channels stored for this playlist, as written.
    func epgChannelIDs(playlist: String) async throws -> [String]

    /// Start times of one channel's programmes ending after `endingAfter`.
    ///
    /// One indexed range read per channel. The importer sweeps a guide channel by
    /// channel because a single ordered listing of every programme cannot use
    /// an index for its resume cursor: it re-scans and re-sorts on every page,
    /// which measured at 47 seconds for 200,000 rows.
    func programmeStarts(playlist: String, channelKey: String, endingAfter: Date) async throws -> [Date]

    func removeProgrammes(playlist: String, channelKey: String, starts: [Date]) async throws

    /// Drops everything that ended at or before `date`. Purely time-based, so
    /// safe whatever the latest guide contained. "At or before" matches
    /// `endingAfter` above, so no row is ever in neither set.
    func removeProgrammes(endedBefore date: Date, playlist: String) async throws -> Int

    // MARK: - State

    func syncState(playlist: String) async throws -> SyncState?

    func saveSyncState(_ state: SyncState, playlist: String) async throws
}
