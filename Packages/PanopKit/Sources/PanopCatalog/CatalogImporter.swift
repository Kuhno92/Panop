import Foundation
import PanopCore
import PanopPlaylist

/// Where an M3U playlist comes from.
public enum M3USource: Sendable, Equatable {
    /// `redacting` lists strings (usually the account's username and password)
    /// to scrub from error messages, since these URLs commonly embed them.
    case remote(URL, redacting: [String] = [])
    case file(path: String)
}

/// Imports playlists and guides into a ``CatalogStore``.
///
/// **The rule everything here is built around:** a row is removed only after an
/// import that completed, and even then only if the removal is small enough to
/// be believable. A failed, cancelled or truncated import removes nothing.
/// Favourites and watch progress hang off catalog rows, so a wrongly deleted
/// row is user data lost, while a stale row left behind costs nothing.
///
/// Downloaded playlists are written under `workingDirectory` and deleted when
/// the import ends, so point it at a caches folder, not somewhere backed up.
///
/// Memory stays flat regardless of catalog size. Entries are written in
/// batches as they parse, and "what was seen" is a set of 64-bit hashes, a few
/// megabytes for a catalog of 100,000 rows, instead of the rows themselves.
public struct CatalogImporter: Sendable {
    let store: any CatalogStore
    let transport: any HTTPTransport
    let policy: PrunePolicy
    let batchSize: Int
    let now: @Sendable () -> Date
    let progress: (@Sendable (ImportProgress) -> Void)?
    let workingDirectory: URL

    static let readSize = 512 * 1024
    static let sweepPageSize = 2000
    static let removeChunkSize = 500

    public init(
        store: any CatalogStore,
        transport: any HTTPTransport,
        policy: PrunePolicy = PrunePolicy(),
        batchSize: Int = 1000,
        now: @escaping @Sendable () -> Date = { Date() },
        progress: (@Sendable (ImportProgress) -> Void)? = nil,
        workingDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.store = store
        self.transport = transport
        self.policy = policy
        self.batchSize = Swift.max(1, batchSize)
        self.now = now
        self.progress = progress
        self.workingDirectory = workingDirectory
    }

    // MARK: - M3U

    /// Imports an M3U playlist.
    ///
    /// The file is fetched (or read) once to a digest, and skipped entirely when
    /// it matches the last completed import. Downloading is unavoidable, since
    /// M3U servers offer nothing to make a conditional request with, but
    /// parsing and writing 80,000 rows again is not.
    ///
    /// - Parameter force: import even when the digest is unchanged.
    public func importM3U(playlist: String, source: M3USource, force: Bool = false) async throws -> ImportReport {
        let file = try await prepare(source)
        defer {
            if file.isTemporary {
                try? FileManager.default.removeItem(atPath: file.path)
            }
        }

        var state = try await store.syncState(playlist: playlist) ?? SyncState()
        if !force, state.digest == file.digest {
            return ImportReport(outcome: .unchanged)
        }
        state.importCounter += 1
        try await store.saveSyncState(state, playlist: playlist)

        var trackers: [MediaKind: KindTracker] = [:]
        for kind in MediaKind.allCases {
            trackers[kind] = try await KindTracker(kind: kind, before: store.entryCount(kind: kind, playlist: playlist))
        }
        let header = try await parseM3U(path: file.path, playlist: playlist, trackers: &trackers)

        // Reaching here means the whole file was read without error. It does
        // not mean the file was whole, which is what the sweep's gate is for.
        var reports: [KindReport] = []
        for kind in MediaKind.allCases {
            guard let tracker = trackers[kind] else { continue }
            let categories = tracker.groups.sorted().map { CatalogCategory(id: $0, kind: kind, name: $0) }
            try await store.upsertCategories(categories, playlist: playlist)
            try await sweepCategories(kind: kind, keeping: Set(tracker.groups), playlist: playlist)

            let sweep = try await sweepEntries(tracker, playlist: playlist, importCounter: state.importCounter)
            reports.append(KindReport(
                kind: kind,
                imported: tracker.imported,
                summary: tracker.summary,
                removed: sweep.removed,
                deferredRemoval: sweep.deferred
            ))
        }

        state.digest = file.digest
        state.lastCompleted = now()
        try await store.saveSyncState(state, playlist: playlist)
        return ImportReport(outcome: .imported, kinds: reports.filter(\.isWorthReporting), epgURLs: header.epgURLs)
    }

    private func parseM3U(
        path: String,
        playlist: String,
        trackers: inout [MediaKind: KindTracker]
    ) async throws -> PlaylistHeader {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw CatalogError.cannotReadFile }
        defer { try? handle.close() }

        var parser = M3UParser()
        while let chunk = try handle.read(upToCount: Self.readSize), !chunk.isEmpty {
            try await accept(parser.consume(chunk), playlist: playlist, trackers: &trackers)
        }
        try await accept(parser.finish(), playlist: playlist, trackers: &trackers)
        for kind in MediaKind.allCases {
            try await flush(&trackers[kind, default: KindTracker(kind: kind, before: 0)], playlist: playlist)
        }
        return parser.header
    }

    private func accept(
        _ parsed: [PlaylistEntry],
        playlist: String,
        trackers: inout [MediaKind: KindTracker]
    ) async throws {
        for item in parsed {
            guard let entry = EntryMapping.entry(from: item) else { continue }
            var tracker = trackers[entry.kind] ?? KindTracker(kind: entry.kind, before: 0)
            trackers[entry.kind] = nil
            tracker.add(entry)
            if tracker.pending.count >= batchSize {
                try await flush(&tracker, playlist: playlist)
            }
            trackers[entry.kind] = tracker
        }
    }

    // MARK: - Confirming a held-back removal

    /// Carries out a removal the safety check declined, after the user agrees.
    ///
    /// - Throws: ``CatalogError/staleConfirmation`` if another import has run
    ///   since. That import may have restored these rows.
    public func confirm(_ removal: DeferredRemoval, playlist: String) async throws {
        let state = try await store.syncState(playlist: playlist)
        guard state?.importCounter == removal.importCounter else { throw CatalogError.staleConfirmation }
        for chunk in removal.ids.chunked(into: Self.removeChunkSize) {
            try await store.removeEntries(ids: chunk, playlist: playlist)
        }
    }
}

// MARK: - Shared helpers

/// What an import has seen for one media kind so far.
struct KindTracker {
    let kind: MediaKind
    /// Rows stored before this import began, the baseline the sweep gate uses.
    let before: Int
    var seen = Set<UInt64>()
    var summary = UpsertSummary()
    var imported = 0
    var pending: [CatalogEntry] = []
    /// M3U only: distinct group titles, which become the categories.
    var groups = Set<String>()

    mutating func add(_ entry: CatalogEntry) {
        pending.append(entry)
        seen.insert(CatalogID.hash64(entry.id))
        imported += 1
        if let group = entry.groupID {
            groups.insert(group)
        }
    }
}

extension CatalogImporter {
    func flush(_ tracker: inout KindTracker, playlist: String) async throws {
        guard !tracker.pending.isEmpty else { return }
        tracker.summary += try await store.upsertEntries(tracker.pending, playlist: playlist)
        tracker.pending.removeAll(keepingCapacity: true)
        progress?(ImportProgress(kind: tracker.kind, processed: tracker.imported))
    }
}

private extension KindReport {
    /// Kinds that saw no rows and lost none add only noise to a report.
    var isWorthReporting: Bool {
        imported > 0 || removed > 0 || deferredRemoval != nil || failure != nil
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
