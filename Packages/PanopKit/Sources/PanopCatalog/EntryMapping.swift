import Foundation
import PanopCore
import PanopXtream

/// Turns each source's rows into ``CatalogEntry``.
enum EntryMapping {
    /// - Returns: nil for an entry with no URL, which cannot be played or
    ///   given a stable identity.
    static func entry(from playlistEntry: PlaylistEntry) -> CatalogEntry? {
        let url = playlistEntry.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        let attributes = playlistEntry.attributes
        let group = attributes.groupTitle.flatMap { $0.isEmpty ? nil : $0 }
        return CatalogEntry(
            id: CatalogID.m3u(url: url),
            kind: playlistEntry.mediaKind,
            name: playlistEntry.name,
            groupID: group,
            groupName: group,
            iconURL: attributes.tvgLogo.flatMap { $0.isEmpty ? nil : $0 },
            epgKey: attributes.tvgID.flatMap { $0.isEmpty ? nil : EPGKey.normalize($0) },
            streamURL: url,
            hasArchive: attributes.catchup.map { !$0.isEmpty } ?? false,
            archiveDays: attributes.catchupDays.flatMap { Int($0) }
        )
    }

    static func entry(from stream: XtreamLiveStream, groups: [String: String]) -> CatalogEntry {
        CatalogEntry(
            id: CatalogID.xtream("live", stream.streamID),
            kind: .live,
            name: stream.name,
            groupID: stream.categoryID,
            groupName: stream.categoryID.flatMap { groups[$0] },
            iconURL: stream.iconURL,
            epgKey: stream.epgChannelID.map(EPGKey.normalize),
            streamURL: stream.directSource,
            remoteID: String(stream.streamID),
            sortNumber: stream.number,
            hasArchive: stream.hasArchive,
            archiveDays: stream.archiveDays,
            addedAt: stream.added
        )
    }

    static func entry(from movie: XtreamMovie, groups: [String: String]) -> CatalogEntry {
        CatalogEntry(
            id: CatalogID.xtream("movie", movie.streamID),
            kind: .movie,
            name: movie.name,
            groupID: movie.categoryID,
            groupName: movie.categoryID.flatMap { groups[$0] },
            iconURL: movie.iconURL,
            streamURL: movie.directSource,
            remoteID: String(movie.streamID),
            containerExtension: movie.containerExtension,
            sortNumber: movie.number,
            addedAt: movie.added,
            rating: movie.rating
        )
    }

    static func entry(from series: XtreamSeries, groups: [String: String]) -> CatalogEntry {
        CatalogEntry(
            id: CatalogID.xtream("series", series.seriesID),
            kind: .series,
            name: series.name,
            groupID: series.categoryID,
            groupName: series.categoryID.flatMap { groups[$0] },
            iconURL: series.coverURL,
            remoteID: String(series.seriesID),
            addedAt: series.lastModified,
            rating: series.rating,
            plot: series.plot
        )
    }

    static func category(from category: XtreamCategory, kind: MediaKind) -> CatalogCategory {
        CatalogCategory(id: category.id, kind: kind, name: category.name, parentID: category.parentID)
    }
}
