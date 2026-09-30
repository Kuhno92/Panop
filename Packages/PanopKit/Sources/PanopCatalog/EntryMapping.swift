import Foundation
import PanopCore
import PanopXtream

/// Turns each source's rows into ``CatalogEntry``.
enum EntryMapping {
    /// - Parameter base: the playlist's own address, for resolving a relative one.
    /// - Returns: nil for an entry with no playable address: empty, or relative with
    ///   nothing to resolve it against. Such a row could never play, and giving it
    ///   an identity would only hide the problem.
    static func entry(from playlistEntry: PlaylistEntry, base: URL? = nil) -> CatalogEntry? {
        guard let url = playableAddress(playlistEntry.url, base: base) else { return nil }

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

    /// The absolute address for an entry's URL, or nil if there is none.
    ///
    /// A URL with a scheme is kept exactly as written: providers put things in
    /// URLs that `URL` would rewrite, and the catalog's identity hashes the text.
    /// Only a scheme-less one is resolved, against the playlist's own address.
    static func playableAddress(_ raw: String, base: URL?) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if hasScheme(text) {
            return text
        }
        guard let base, let resolved = URL(string: text, relativeTo: base)?.absoluteURL,
              resolved.scheme != nil, resolved.host?.isEmpty == false
        else { return nil }
        return resolved.absoluteString
    }

    /// `http://`, `rtmp://`, `file://` and so on. Looks for `scheme:` followed by `//`,
    /// not just a colon, so a path such as `a:b/c` is not mistaken for one.
    private static func hasScheme(_ text: String) -> Bool {
        guard let range = text.range(of: "://") else { return false }
        let scheme = text[..<range.lowerBound]
        return !scheme.isEmpty && scheme
            .allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
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
