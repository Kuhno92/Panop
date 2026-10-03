import Foundation
import PanopCore
import SwiftData

/// Everything the app's screens share, built once at launch.
///
/// The catalog store and sync service are actors and never run on the main
/// thread; the library and status center are main-actor because views read them.
@MainActor
final class AppServices {
    let library: PlaylistLibrary
    let userState: UserStateStore
    let syncStatus: SyncStatusCenter
    let sync: SyncService
    let catalogStore: SwiftDataCatalogStore
    let catalogContainer: ModelContainer

    init(
        catalog: ModelContainer,
        cloud: ModelContainer,
        credentials: any CredentialStore,
        transport: any HTTPTransport = URLSessionTransport(),
        playlistsDirectory: URL = AppServices.defaultPlaylistsDirectory
    ) {
        let status = SyncStatusCenter()
        let store = SwiftDataCatalogStore(container: catalog)
        let sync = SyncService(store: store, transport: transport, center: status)

        catalogStore = store
        catalogContainer = catalog
        syncStatus = status
        self.sync = sync
        let userState = UserStateStore(context: ModelContext(cloud), profile: ProfileStore.savedCurrentID())
        self.userState = userState
        library = PlaylistLibrary(
            context: ModelContext(cloud),
            credentials: credentials,
            sync: sync,
            transport: transport,
            directory: playlistsDirectory
        )
        // A deleted playlist's favourites and history go with it.
        library.onRemoved = { id in userState.forget(playlist: id) }
    }

    /// In-memory containers and Keychain, for previews and tests.
    static func preview() -> AppServices {
        do {
            return try AppServices(
                catalog: PanopContainers.makeCatalog(inMemory: true),
                cloud: PanopContainers.makeCloud(inMemory: true),
                credentials: InMemoryCredentialStore()
            )
        } catch {
            fatalError("In-memory containers failed to open: \(error)")
        }
    }

    /// Application Support, not Documents: these are the app's own copies, not
    /// files the user manages, and they should not appear in the Files app.
    nonisolated static var defaultPlaylistsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Playlists", isDirectory: true)
    }
}
