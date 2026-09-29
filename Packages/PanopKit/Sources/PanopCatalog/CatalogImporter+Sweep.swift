import Foundation
import PanopCore

/// The only code that decides a stored row is stale, and the only place that
/// calls a removal. Keeping it in one file keeps the safety rule reviewable.
extension CatalogImporter {
    struct SweepResult {
        var removed = 0
        var deferred: DeferredRemoval?
    }

    /// Removes stored entries of `tracker.kind` that this import did not see.
    ///
    /// Call only after the import ran to completion.
    func sweepEntries(_ tracker: KindTracker, playlist: String, importCounter: Int) async throws -> SweepResult {
        var stale: [String] = []
        var cursor: String?
        while true {
            let page = try await store.entryIDs(
                kind: tracker.kind,
                playlist: playlist,
                after: cursor,
                limit: Self.sweepPageSize
            )
            guard let last = page.last else { break }
            stale += page.filter { !tracker.seen.contains(CatalogID.hash64($0)) }
            cursor = last
        }
        guard !stale.isEmpty else { return SweepResult() }

        guard policy.allows(removing: stale.count, of: tracker.before) else {
            return SweepResult(deferred: DeferredRemoval(kind: tracker.kind, ids: stale, importCounter: importCounter))
        }
        for chunk in stale.chunked(into: Self.removeChunkSize) {
            try await store.removeEntries(ids: chunk, playlist: playlist)
        }
        return SweepResult(removed: stale.count)
    }

    /// Categories are cheap to rebuild and nothing hangs off them, so a held-back
    /// category sweep is simply skipped rather than reported.
    func sweepCategories(kind: MediaKind, keeping keep: Set<String>, playlist: String) async throws {
        let stored = try await store.categoryIDs(kind: kind, playlist: playlist)
        let stale = stored.filter { !keep.contains($0) }
        guard !stale.isEmpty, policy.allows(removing: stale.count, of: stored.count) else { return }
        try await store.removeCategories(ids: stale, kind: kind, playlist: playlist)
    }

    /// Guide sweep. Stale programmes age out by time anyway, so there is no
    /// confirmation path: a held-back sweep just reports how many it left.
    func sweepProgrammes(
        seen: Set<UInt64>,
        before: Int,
        playlist: String,
        from windowStart: Date
    ) async throws -> (removed: Int, deferred: Int) {
        var stale: [ProgrammeKey] = []
        var cursor: ProgrammeKey?
        while true {
            let page = try await store.programmeKeys(
                playlist: playlist,
                endingAfter: windowStart,
                after: cursor,
                limit: Self.sweepPageSize
            )
            guard let last = page.last else { break }
            stale += page.filter { !seen.contains($0.hash64) }
            cursor = last
        }
        guard !stale.isEmpty else { return (0, 0) }
        guard policy.allows(removing: stale.count, of: before) else { return (0, stale.count) }

        for chunk in stale.chunked(into: Self.removeChunkSize) {
            try await store.removeProgrammes(keys: chunk, playlist: playlist)
        }
        return (stale.count, 0)
    }
}
