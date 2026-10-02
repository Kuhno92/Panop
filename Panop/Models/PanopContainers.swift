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

    /// User state. Mirrors to CloudKit once the app has a team and an iCloud
    /// container.
    ///
    /// CloudKit is currently off. Turning it on requires a Developer Program
    /// team, the iCloud capability, and a real container identifier; without
    /// those the app fails to launch rather than degrading. Flip this to
    /// `.private("iCloud.<bundle id>")` in the same change that adds the
    /// entitlement.
    static func makeCloud(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CloudUserData",
            schema: cloudSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: cloudSchema, configurations: configuration)
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
