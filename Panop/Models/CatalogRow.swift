import Foundation
import PanopCore
import SwiftData

/// A catalog entry as a list draws it: plain values, copied out of the store.
///
/// Lists hold these rather than the live records. A record belongs to the context that fetched
/// it, so a list built on records can only be fed from the main thread, and reading a page of
/// them there costs about 30 microseconds a row. A page read on a background context and handed
/// over as values leaves the main thread only the drawing.
nonisolated struct CatalogRow: Identifiable, Hashable, Sendable {
    var playlist: String
    /// The entry's id within its playlist. Not unique across playlists: see ``id``.
    var entryID: String
    var kind: MediaKind
    var name: String
    var nameKey: String
    var groupName: String?
    var iconURL: String?
    var epgKey: String?
    var streamURL: String?
    var remoteID: String?
    var containerExtension: String?
    var hasArchive: Bool
    var archiveDays: Int?
    var rating: Double?
    var plot: String?

    /// Playlist and entry together, the same key the favourites and resume points use.
    var id: String {
        "\(playlist)|\(entryID)"
    }

    init(_ record: CatalogEntryRecord) {
        playlist = record.playlist
        entryID = record.id
        kind = record.kind
        name = record.name
        nameKey = record.nameKey
        groupName = record.groupName
        iconURL = record.iconURL
        epgKey = record.epgKey
        streamURL = record.streamURL
        remoteID = record.remoteID
        containerExtension = record.containerExtension
        hasArchive = record.hasArchive
        archiveDays = record.archiveDays
        rating = record.rating
        plot = record.plot
    }
}

/// What a list asks the catalog for. Plain values, so it can cross to the reader's thread, which
/// builds the fetch from it there.
nonisolated struct ListSpec: Hashable, Sendable {
    /// Nil for any kind, which only a fixed set (see `restrictedTo`) can ask for.
    var kind: MediaKind?
    var source: String?
    var search = ""
    var order = LiveOrder.provider
    var group: String?
    /// A fixed set of entry ids (favourites, recents), not paged: they are few.
    var restrictedTo: [String]?
    /// Keys (playlist and entry) the person has hidden, left out of what is read.
    var hidden: Set<String> = []
    /// Names of categories the person has hidden: their entries are left out too.
    var hiddenGroups: Set<String> = []

    func descriptor() -> FetchDescriptor<CatalogEntryRecord> {
        if let restrictedTo {
            return LiveChannelQuery.descriptor(restrictedTo: restrictedTo, kind: kind)
        }
        return LiveChannelQuery.descriptor(
            kind: kind ?? .live,
            source: source,
            search: search,
            limit: LiveChannelQuery.maxRows,
            order: order,
            group: group
        )
    }
}

/// Reads pages of the catalog off the main thread.
///
/// A fresh context for every read. A context that lives on keeps the records it has already
/// fetched and does not refresh them from the store, so a list read through it would go on
/// showing a channel's old name after an import changed it.
actor CatalogReader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// The category names for a kind, in the provider's order (see `LiveChannelQuery.categoryNames`).
    func categoryNames(kind: MediaKind, source: String?) -> [String] {
        LiveChannelQuery.categoryNames(kind: kind, source: source, in: ModelContext(container))
    }

    func rows(_ spec: ListSpec, offset: Int, limit: Int) -> [CatalogRow] {
        let context = ModelContext(container)
        var descriptor = spec.descriptor()
        if spec.restrictedTo == nil {
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Swift.max(Swift.min(limit, LiveChannelQuery.maxRows - offset), 0)
        }
        guard descriptor.fetchLimit != 0 else { return [] }
        return ((try? context.fetch(descriptor)) ?? []).map(CatalogRow.init)
    }
}
