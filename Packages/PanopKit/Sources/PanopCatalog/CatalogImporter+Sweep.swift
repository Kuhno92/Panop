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
        // Every id this import saw was written, so if the store holds exactly
        // that many, nothing else is in it. That is the steady state of a
        // refresh, and it skips reading every id back. The check errs safe: a
        // collision in the seen set makes `seen.count` smaller than the id
        // count, which forces the full scan, and a row that changed kind
        // mid-import can only make a stale row survive one more import.
        if try await store.entryCount(kind: tracker.kind, playlist: playlist) == tracker.seen.count {
            return SweepResult()
        }

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
    ///
    /// Works channel by channel, over the channels this guide mentioned plus
    /// every guide channel already stored. A channel that appears in neither
    /// (programmes stored without a `<channel>` entry, then dropped) is not
    /// swept; its rows expire by time.
    func sweepProgrammes(
        seen: Set<UInt64>,
        seenChannels: Set<String>,
        before: Int,
        playlist: String,
        from windowStart: Date
    ) async throws -> (removed: Int, deferred: Int) {
        // As with entries: if the store holds exactly what was seen, nothing
        // is stale, and no per-channel reads are needed.
        if try await store.programmeCount(playlist: playlist, endingAfter: windowStart) == seen.count {
            return (0, 0)
        }

        let stored = try await store.epgChannelIDs(playlist: playlist).map(EPGKey.normalize)
        let channels = seenChannels.union(stored).sorted()

        var stale: [(channelKey: String, starts: [Date])] = []
        var staleCount = 0
        for channelKey in channels {
            let starts = try await store.programmeStarts(
                playlist: playlist,
                channelKey: channelKey,
                endingAfter: windowStart
            )
            let missing = starts.filter { !seen.contains(ProgrammeKey(channelKey: channelKey, start: $0).hash64) }
            if !missing.isEmpty {
                stale.append((channelKey, missing))
                staleCount += missing.count
            }
        }
        guard staleCount > 0 else { return (0, 0) }
        guard policy.allows(removing: staleCount, of: before) else { return (0, staleCount) }

        for (channelKey, starts) in stale {
            for chunk in starts.chunked(into: Self.removeChunkSize) {
                try await store.removeProgrammes(playlist: playlist, channelKey: channelKey, starts: chunk)
            }
        }
        return (staleCount, 0)
    }

    /// Removes every movie and series entry of a playlist, with their categories, because the
    /// user turned them off for it.
    ///
    /// Not a sweep, so the mass-removal safety check does not apply: that check guards against
    /// a bad download emptying the catalog, and this is the person asking for exactly that part
    /// to go. Live channels are not touched.
    public func dropVOD(playlist: String) async throws {
        for kind in [MediaKind.movie, .series] {
            while true {
                let page = try await store.entryIDs(
                    kind: kind,
                    playlist: playlist,
                    after: nil,
                    limit: Self.sweepPageSize
                )
                if page.isEmpty {
                    break
                }
                try await store.removeEntries(ids: page, playlist: playlist)
            }
            let categories = try await store.categoryIDs(kind: kind, playlist: playlist)
            if !categories.isEmpty {
                try await store.removeCategories(ids: categories, kind: kind, playlist: playlist)
            }
        }
    }
}
