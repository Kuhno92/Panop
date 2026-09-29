import Foundation
import PanopCore
import PanopXtream

/// One section of an Xtream import: which kind, into which playlist, and the
/// import counter to record on anything it holds back.
private struct SectionTarget {
    var kind: MediaKind
    var playlist: String
    var counter: Int
}

extension CatalogImporter {
    /// Imports live channels, movies and series from an Xtream panel.
    ///
    /// Each section succeeds or fails on its own. A panel that serves live TV
    /// but times out on the movie list still gets its live channels imported,
    /// and the movie section is left exactly as it was: a failed section never
    /// removes anything.
    ///
    /// - Throws: ``XtreamError/authenticationFailed`` for bad credentials, or
    ///   ``CatalogError/everySectionFailed(firstFailure:)`` when nothing
    ///   imported. Partial failure is returned in the report instead.
    public func importXtream(playlist: String, credentials: ProviderCredentials) async throws -> ImportReport {
        let client = try XtreamClient(credentials: credentials, transport: transport)
        _ = try await client.authenticate()

        var state = try await store.syncState(playlist: playlist) ?? SyncState()
        state.importCounter += 1
        try await store.saveSyncState(state, playlist: playlist)

        var reports: [KindReport] = []
        for kind in [MediaKind.live, .movie, .series] {
            do {
                try await reports.append(importSection(
                    kind,
                    client: client,
                    playlist: playlist,
                    counter: state.importCounter
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reports.append(KindReport(kind: kind, failure: String(describing: error)))
            }
        }

        if let first = reports.first?.failure, reports.allSatisfy({ $0.failure != nil }) {
            throw CatalogError.everySectionFailed(firstFailure: first)
        }
        if reports.allSatisfy({ $0.failure == nil }) {
            state.lastCompleted = now()
            try await store.saveSyncState(state, playlist: playlist)
        }
        return ImportReport(outcome: .imported, kinds: reports)
    }

    private func importSection(
        _ kind: MediaKind,
        client: XtreamClient,
        playlist: String,
        counter: Int
    ) async throws -> KindReport {
        let target = SectionTarget(kind: kind, playlist: playlist, counter: counter)
        switch kind {
        case .live:
            return try await importList(
                target,
                categories: { try await client.liveCategories() },
                rows: client.liveStreams(batchSize: batchSize),
                map: EntryMapping.entry(from:groups:)
            )
        case .movie:
            return try await importList(
                target,
                categories: { try await client.movieCategories() },
                rows: client.movies(batchSize: batchSize),
                map: EntryMapping.entry(from:groups:)
            )
        default:
            return try await importList(
                target,
                categories: { try await client.seriesCategories() },
                rows: client.series(batchSize: batchSize),
                map: EntryMapping.entry(from:groups:)
            )
        }
    }

    private func importList<Item: Decodable & Sendable>(
        _ target: SectionTarget,
        categories fetchCategories: () async throws -> [XtreamCategory],
        rows: XtreamBatches<Item>,
        map: (Item, [String: String]) -> CatalogEntry
    ) async throws -> KindReport {
        let (kind, playlist, counter) = (target.kind, target.playlist, target.counter)
        var tracker = try await KindTracker(kind: kind, before: store.entryCount(kind: kind, playlist: playlist))

        let categories = try await fetchCategories()
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        try await store.upsertCategories(
            categories.map { EntryMapping.category(from: $0, kind: kind) },
            playlist: playlist
        )

        // A throw anywhere in this loop leaves the section untouched by any
        // sweep: the removals below are only reached on a clean finish.
        for try await batch in rows {
            for item in batch {
                tracker.add(map(item, names))
            }
            try await flush(&tracker, playlist: playlist)
        }

        try await sweepCategories(kind: kind, keeping: Set(categories.map(\.id)), playlist: playlist)
        let sweep = try await sweepEntries(tracker, playlist: playlist, importCounter: counter)
        return KindReport(
            kind: kind,
            imported: tracker.imported,
            summary: tracker.summary,
            removed: sweep.removed,
            deferredRemoval: sweep.deferred
        )
    }
}
