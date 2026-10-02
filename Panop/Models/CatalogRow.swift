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
    /// Only the entries with no category (see `LiveChannelQuery.ungroupedDescriptor`).
    var ungrouped = false

    func descriptor() -> FetchDescriptor<CatalogEntryRecord> {
        if let restrictedTo {
            return LiveChannelQuery.descriptor(restrictedTo: restrictedTo, kind: kind)
        }
        if ungrouped {
            var descriptor = LiveChannelQuery.ungroupedDescriptor(
                kind: kind ?? .live, source: source, search: search, order: order
            )
            descriptor.fetchLimit = LiveChannelQuery.maxRows
            return descriptor
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

/// One category's rows within a list shown category by category. `name` is nil for the entries
/// that belong to none.
nonisolated struct CategorySection: Identifiable, Hashable, Sendable {
    var name: String?
    var rows: [CatalogRow]

    var id: String {
        name.map { "c:\($0)" } ?? "none"
    }
}

/// What one read of a list shown category by category found, and where to carry on from.
nonisolated struct SectionBatch: Sendable {
    var sections: [CategorySection]
    /// Which category the next read starts in, and how far into it.
    var step: Int
    var offset: Int
    var finished: Bool
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

    /// Reads a list category by category, in the order of `steps`, until at least `minimum` rows
    /// are found or there are no more. All on this actor, so the main thread is not involved until
    /// the result is handed over.
    func sections(_ steps: [ListSpec], step start: Int, offset startOffset: Int, minimum: Int, pageSize: Int)
        -> SectionBatch
    {
        let context = ModelContext(container)
        var sections: [CategorySection] = []
        var found = 0
        var step = start
        var offset = startOffset
        while found < minimum, step < steps.count {
            let spec = steps[step]
            var descriptor = spec.descriptor()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Swift.max(Swift.min(pageSize, LiveChannelQuery.maxRows - offset), 0)
            let page = descriptor.fetchLimit == 0 ? [] : ((try? context.fetch(descriptor)) ?? []).map(CatalogRow.init)
            let visible = spec.hidden.isEmpty ? page : page.filter { !spec.hidden.contains($0.id) }
            if !visible.isEmpty {
                let name = spec.ungrouped ? nil : spec.group
                if sections.last?.name == name, sections.last != nil {
                    sections[sections.count - 1].rows += visible
                } else {
                    sections.append(CategorySection(name: name, rows: visible))
                }
                found += visible.count
            }
            offset += page.count
            // A short page is the end of this category.
            if page.count < pageSize || offset >= LiveChannelQuery.maxRows {
                step += 1
                offset = 0
            }
        }
        return SectionBatch(sections: sections, step: step, offset: offset, finished: step >= steps.count)
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
