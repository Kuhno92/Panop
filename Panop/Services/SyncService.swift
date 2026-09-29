import Foundation
import PanopCatalog
import PanopCore

/// Runs playlist imports in the background, one per playlist at a time.
///
/// An actor, so nothing here touches the main thread. Views only ever see the
/// `SyncStatusCenter`, which this updates as work proceeds.
actor SyncService {
    private let store: SwiftDataCatalogStore
    private let transport: any HTTPTransport
    private let center: SyncStatusCenter
    private let now: @Sendable () -> Date
    private var tasks: [String: Task<Void, Never>] = [:]

    init(
        store: SwiftDataCatalogStore,
        transport: any HTTPTransport,
        center: SyncStatusCenter,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.center = center
        self.now = now
    }

    /// Starts a sync unless one is already running for this playlist.
    ///
    /// The task holds `self` strongly on purpose: it lives only until the sync
    /// ends, and it must be able to clear its own entry when it does.
    func start(_ playlist: PlaylistDescriptor, force: Bool = false) {
        guard tasks[playlist.id] == nil else { return }
        let id = playlist.id
        let (store, transport, center, now) = (store, transport, center, now)

        tasks[id] = Task {
            await center.set(.syncing(processed: 0), for: id)

            let importer = CatalogImporter(
                store: store,
                transport: transport,
                now: now,
                progress: { progress in
                    Task { @MainActor in
                        // A late progress tick must not overwrite a finished status.
                        if case .syncing = center.status(for: id) {
                            center.set(.syncing(processed: progress.processed), for: id)
                        }
                    }
                }
            )

            do {
                let outcome = try await importer.sync(playlist, force: force)
                await center.set(.finished(SyncSummary(outcome: outcome, finishedAt: now())), for: id)
            } catch is CancellationError {
                await center.set(.idle, for: id)
            } catch {
                await center.set(.failed(SyncErrorMessage.text(for: error)), for: id)
            }
            self.finished(id)
        }
    }

    func isSyncing(_ playlist: String) -> Bool {
        tasks[playlist] != nil
    }

    /// Returns once any running sync for this playlist has finished.
    func waitForCompletion(_ playlist: String) async {
        await tasks[playlist]?.value
    }

    func cancel(_ playlist: String) {
        tasks[playlist]?.cancel()
    }

    /// Stops any sync, then deletes everything stored for the playlist.
    func remove(_ playlist: String) async throws {
        tasks[playlist]?.cancel()
        await tasks[playlist]?.value
        tasks[playlist] = nil
        try await store.removePlaylist(playlist)
        await center.clear(playlist)
    }

    /// Carries out a removal the safety check held back, after the user agreed.
    func confirm(_ removal: DeferredRemoval, playlist: String) async throws {
        let importer = CatalogImporter(store: store, transport: transport)
        try await importer.confirm(removal, playlist: playlist)
        await center.resolve(removal, for: playlist)
    }

    /// When this playlist last synced to completion, from the catalog itself, so
    /// it survives a relaunch.
    func lastCompleted(_ playlist: String) async -> Date? {
        try? await store.syncState(playlist: playlist)?.lastCompleted
    }

    private func finished(_ playlist: String) {
        tasks[playlist] = nil
    }
}
