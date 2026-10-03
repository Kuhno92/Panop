import Foundation
import SwiftData

/// The app's two SwiftData containers.
///
/// Panop deliberately runs two rather than one. The reasoning is in
/// docs/adr/0003-two-model-containers.md; the short version is that CloudKit
/// mirroring forbids the uniqueness and relationships a catalogue needs, and a
/// mirrored container re-runs every live `@Query` during import, which is
/// enough to freeze tvOS on a large catalogue.
nonisolated enum PanopContainers {
    /// Local-only catalogue. Every `@Query` in the app targets this.
    ///
    /// Pass `storeURL` for a store at a specific file. Tests that depend on how
    /// SQLite orders and compares (paging, collation) need one: an in-memory
    /// store evaluates those in Swift and hides the difference.
    static func makeCatalog(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration = if let storeURL {
            ModelConfiguration("Catalog", schema: catalogSchema, url: storeURL, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(
                "Catalog",
                schema: catalogSchema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: catalogSchema, configurations: configuration)
    }

    /// User state: favourites, what was watched, hidden titles, category choices and the playlists.
    ///
    /// Mirrors to the person's own iCloud when `mirrored` is set, which `CloudSync.decide` does only for a
    /// build that has the entitlement and an account that is signed in. Without those SwiftData would
    /// refuse to open the store rather than degrade, so the default is local.
    static func makeCloud(inMemory: Bool = false, mirrored: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CloudUserData",
            schema: cloudSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: mirrored && !inMemory ? .private(CloudSync.containerID) : .none
        )
        return try ModelContainer(for: cloudSchema, configurations: configuration)
    }

    /// The cloud container for what `CloudSync` decided, and what that came to: a mirrored container that
    /// would not open is replaced by a local one, and the reason is kept so Settings can say so.
    static func openCloud(
        inMemory: Bool,
        availability: CloudSync.Availability
    ) throws -> (container: ModelContainer, availability: CloudSync.Availability) {
        guard availability == .active, !inMemory else {
            return try (makeCloud(inMemory: inMemory), availability)
        }
        do {
            return try (makeCloud(mirrored: true), .active)
        } catch {
            return try (makeCloud(), .failed(String(describing: error)))
        }
    }

    static let catalogSchema = Schema([
        CatalogEntryRecord.self,
        CatalogCategoryRecord.self,
        EPGChannelRecord.self,
        EPGProgrammeRecord.self,
        SyncStateRecord.self
    ])
    static let cloudSchema = Schema([UserContentState.self, PlaylistRecord.self, CategoryPreference.self])
}
