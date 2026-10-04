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
            archiveDays: attributes.catchupDays.flatMap { Int($0) },
            isAdult: TitleMetadata.isAdultCategory(group),
            year: TitleMetadata.year(fromTitle: playlistEntry.name)
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
        let group = stream.categoryID.flatMap { groups[$0] }
        return CatalogEntry(
            id: CatalogID.xtream("live", stream.streamID),
            kind: .live,
            name: stream.name,
            groupID: stream.categoryID,
            groupName: group,
            iconURL: stream.iconURL,
            epgKey: stream.epgChannelID.map(EPGKey.normalize),
            streamURL: stream.directSource,
            remoteID: String(stream.streamID),
            sortNumber: stream.number,
            hasArchive: stream.hasArchive,
            archiveDays: stream.archiveDays,
            addedAt: stream.added,
            // A panel does not flag its adult channels (on a real one, every channel in "FOR ADULTS"
            // said it was not), so the category's name is what tells.
            isAdult: TitleMetadata.isAdultCategory(group)
        )
    }

    static func entry(from movie: XtreamMovie, groups: [String: String]) -> CatalogEntry {
        let group = movie.categoryID.flatMap { groups[$0] }
        return CatalogEntry(
            id: CatalogID.xtream("movie", movie.streamID),
            kind: .movie,
            name: movie.name,
            groupID: movie.categoryID,
            groupName: group,
            iconURL: movie.iconURL,
            streamURL: movie.directSource,
            remoteID: String(movie.streamID),
            containerExtension: movie.containerExtension,
            sortNumber: movie.number,
            addedAt: movie.added,
            rating: movie.rating,
            tmdbID: movie.tmdbID,
            isAdult: movie.isAdult || TitleMetadata.isAdultCategory(group),
            // The title often carries it ("Backrooms (2026)") when the panel's field is empty.
            year: movie.year ?? TitleMetadata.year(fromTitle: movie.name),
            genre: movie.genre,
            cast: movie.cast
        )
    }

    static func entry(from series: XtreamSeries, groups: [String: String]) -> CatalogEntry {
        let group = series.categoryID.flatMap { groups[$0] }
        return CatalogEntry(
            id: CatalogID.xtream("series", series.seriesID),
            kind: .series,
            name: series.name,
            groupID: series.categoryID,
            groupName: group,
            iconURL: series.coverURL,
            backdropURL: series.backdropURLs.first(where: { !$0.isEmpty }),
            remoteID: String(series.seriesID),
            sortNumber: series.number,
            addedAt: series.lastModified,
            rating: series.rating,
            plot: series.plot,
            tmdbID: series.tmdbID,
            isAdult: TitleMetadata.isAdultCategory(group),
            year: TitleMetadata.year(fromDate: series.releaseDate) ?? TitleMetadata.year(fromTitle: series.name),
            genre: series.genre,
            cast: series.cast
        )
    }

    /// A provider's visual divider: a "channel" that is only a heading between blocks of real
    /// ones, such as `##### DE SPORTS #####`, `=== NEWS ===` or `★★★ KIDS ★★★`.
    ///
    /// Nothing but the name tells it apart. On a real provider every other field of a divider
    /// (kind, category, logo slot, guide, even a stream address that answers) was identical to a
    /// channel's. So the name is read for what dividers have in common: a run of three or more of
    /// the same decoration character, neither letter nor digit, at the start *and* at the end,
    /// or nothing but such a run. A single `#` or a dash in a real name does not qualify, and
    /// neither does a name decorated at one end only.
    ///
    /// A provider that decorates differently is not recognised. That is what hiding a channel by
    /// hand is for.
    static func isDivider(_ name: String) -> Bool {
        let characters = Array(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard characters.count >= 3 else { return false }
        let lead = decorationRun(characters)
        let trail = decorationRun(characters.reversed())
        if lead == characters.count {
            return lead >= 5
        }
        return lead >= 3 && trail >= 3
    }

    /// How many times the first character repeats, if it is decoration; otherwise 0.
    private static func decorationRun(_ characters: some Sequence<Character>) -> Int {
        guard let first = characters.first(where: { _ in true }),
              !first.isLetter, !first.isNumber, !first.isWhitespace, first != "." else { return 0 }
        return characters.prefix { $0 == first }.count
    }

    static func category(from category: XtreamCategory, kind: MediaKind, position: Int? = nil) -> CatalogCategory {
        CatalogCategory(
            id: category.id,
            kind: kind,
            name: category.name,
            parentID: category.parentID,
            sortNumber: position
        )
    }
}
