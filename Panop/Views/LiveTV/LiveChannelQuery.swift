import Foundation
import PanopCore
import SwiftData

/// The fetch behind the Live TV list.
///
/// Every shape of it is bounded, ordered by an indexed column and filtered in
/// SQL. That is the whole point of this type existing: a list over an 80,000
/// channel catalog is only snappy if the database does the narrowing, and a fetch
/// that sorts or filters on an unindexed column reads the whole table however
/// small the limit looks.
enum LiveChannelQuery {
    /// Rows to load first, and the step the list grows by as you scroll.
    static let pageSize = 300
    /// The most rows the list will ever hold. Each is a live model object, so
    /// this bounds memory; search reaches everything past it.
    static let maxRows = 5000

    /// - Parameters:
    ///   - source: one playlist's id, or nil for every playlist.
    ///   - search: matched against the folded name, so case and accents are ignored.
    ///   - kind: live channels by default; the Movies and Series screens ask for theirs, through
    ///     the same bounded, indexed fetch.
    static func descriptor(
        kind: MediaKind = .live,
        source: String?,
        search: String,
        limit: Int,
        order: LiveOrder = .name
    ) -> FetchDescriptor<CatalogEntryRecord> {
        // Series are listed as shows: an episode grouped under its show is reached through the show.
        if kind == .series {
            return seriesDescriptor(source: source, search: search, limit: limit, order: order)
        }
        let live = kind.rawValue
        let term = CatalogEntryRecord.nameKey(for: search.trimmingCharacters(in: .whitespacesAndNewlines))
        // `.lexical` on a folded key is binary order, which an index can serve.
        // The id breaks ties so equal names keep a stable order between fetches.
        let sort = Self.sort(for: order)

        var descriptor: FetchDescriptor<CatalogEntryRecord> = switch (source, term.isEmpty) {
        case let (source?, true):
            FetchDescriptor(
                predicate: #Predicate { $0.playlist == source && $0.kindRaw == live },
                sortBy: sort
            )
        case let (source?, false):
            FetchDescriptor(
                predicate: #Predicate { $0.playlist == source && $0.kindRaw == live && $0.nameKey.contains(term) },
                sortBy: sort
            )
        case (nil, true):
            FetchDescriptor(predicate: #Predicate { $0.kindRaw == live }, sortBy: sort)
        case (nil, false):
            FetchDescriptor(
                predicate: #Predicate { $0.kindRaw == live && $0.nameKey.contains(term) },
                sortBy: sort
            )
        }
        descriptor.fetchLimit = Swift.min(Swift.max(limit, 1), maxRows)
        return descriptor
    }

    /// The channels with these entry ids, for the favourites and recents views.
    ///
    /// Those sets live in the cloud container and cannot be joined to the catalog, so the ids
    /// go into the catalog query. They are few (a person's favourites, at most fifty recents),
    /// which is why this is fine where it would not be for the whole catalog. An id can repeat
    /// across playlists, so the caller still checks the playlist.
    ///
    /// - Parameter kind: live channels by default, since that is what the channel list wants;
    ///   nil for any kind, which is what Home wants, where a film can sit beside a channel.
    static func descriptor(
        restrictedTo entryIDs: [String],
        kind: MediaKind? = .live
    ) -> FetchDescriptor<CatalogEntryRecord> {
        let wanted = entryIDs
        let sort = [
            SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical),
            SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
        ]
        var descriptor: FetchDescriptor<CatalogEntryRecord>
        if let kind {
            let raw = kind.rawValue
            descriptor = FetchDescriptor(
                predicate: #Predicate { wanted.contains($0.id) && $0.kindRaw == raw },
                sortBy: sort
            )
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { wanted.contains($0.id) }, sortBy: sort)
        }
        descriptor.fetchLimit = maxRows
        return descriptor
    }

    private static func sort(for order: LiveOrder) -> [SortDescriptor<CatalogEntryRecord>] {
        switch order {
        case .name:
            [
                SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical),
                SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
            ]
        case .provider:
            // The provider's number first; entries with none sort together, then by name, so the
            // order never depends on where the database left them.
            [
                SortDescriptor(\CatalogEntryRecord.sortNumber),
                SortDescriptor(\CatalogEntryRecord.nameKey, comparator: .lexical),
                SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
            ]
        }
    }

    /// The Series screen: shows, and any series entry that is not an episode of one. An episode
    /// grouped under its show is left out, which is the point: a real playlist has hundreds of
    /// thousands of episodes and a few thousand shows.
    private static func seriesDescriptor(
        source: String?,
        search: String,
        limit: Int,
        order: LiveOrder
    ) -> FetchDescriptor<CatalogEntryRecord> {
        let series = MediaKind.series.rawValue
        let term = CatalogEntryRecord.nameKey(for: search.trimmingCharacters(in: .whitespacesAndNewlines))
        let sort = Self.sort(for: order)
        var descriptor: FetchDescriptor<CatalogEntryRecord> = switch (source, term.isEmpty) {
        case let (source?, true):
            FetchDescriptor(
                predicate: #Predicate { $0.playlist == source && $0.kindRaw == series && $0.seriesID == nil },
                sortBy: sort
            )
        case let (source?, false):
            FetchDescriptor(
                predicate: #Predicate {
                    $0.playlist == source && $0.kindRaw == series && $0.seriesID == nil && $0.nameKey.contains(term)
                },
                sortBy: sort
            )
        case (nil, true):
            FetchDescriptor(predicate: #Predicate { $0.kindRaw == series && $0.seriesID == nil }, sortBy: sort)
        case (nil, false):
            FetchDescriptor(
                predicate: #Predicate { $0.kindRaw == series && $0.seriesID == nil && $0.nameKey.contains(term) },
                sortBy: sort
            )
        }
        descriptor.fetchLimit = Swift.min(Swift.max(limit, 1), maxRows)
        return descriptor
    }

    /// One series' episodes, season by season and in order.
    static func episodes(of seriesID: String, in playlist: String) -> FetchDescriptor<CatalogEntryRecord> {
        var descriptor = FetchDescriptor<CatalogEntryRecord>(
            predicate: #Predicate { $0.playlist == playlist && $0.seriesID == seriesID },
            sortBy: [
                SortDescriptor(\CatalogEntryRecord.seasonNumber),
                SortDescriptor(\CatalogEntryRecord.episodeNumber),
                SortDescriptor(\CatalogEntryRecord.id, comparator: .lexical)
            ]
        )
        descriptor.fetchLimit = maxRows
        return descriptor
    }

    /// Doubles rather than adding a page, so reaching row 5,000 costs a handful
    /// of re-reads instead of seventeen.
    static func nextLimit(after limit: Int) -> Int {
        Swift.min(limit * 2, maxRows)
    }
}

/// How the channel list is ordered.
enum LiveOrder: String, CaseIterable, Identifiable {
    case name, provider

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .name: "By name"
        case .provider: "Provider's order"
        }
    }
}

/// Which channels to list.
enum LiveListMode: String, CaseIterable, Identifiable {
    case all, favourites, recents

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All channels"
        case .favourites: "Favourites"
        case .recents: "Recently watched"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tv"
        case .favourites: "star"
        case .recents: "clock"
        }
    }
}

/// Which playlist's channels to show.
enum LiveSourceFilter {
    /// The stored value meaning "every playlist". Not a playlist id, which is a UUID.
    static let allID = "all"
}
