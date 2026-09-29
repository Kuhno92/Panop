/// One playable item from a playlist.
///
/// This is the parser's output and the catalog layer's input. It deliberately
/// holds the URL as a `String`: provider playlists routinely contain URLs that
/// `URL` rejects or silently mangles, and dropping an entry at parse time is
/// worse than carrying it and failing later at playback with a clear reason.
public struct PlaylistEntry: Sendable, Equatable, Hashable, Codable {
    /// Display name, taken from the text after the final comma on the `#EXTINF` line.
    public var name: String
    public var url: String
    /// `-1` for live streams, a positive length for VOD, `nil` when unparseable.
    public var duration: Double?
    public var attributes: ChannelAttributes
    public var mediaKind: MediaKind

    public init(
        name: String,
        url: String,
        duration: Double? = nil,
        attributes: ChannelAttributes = ChannelAttributes(),
        mediaKind: MediaKind = .unknown
    ) {
        self.name = name
        self.url = url
        self.duration = duration
        self.attributes = attributes
        self.mediaKind = mediaKind
    }

    /// Best available identifier for matching against EPG data.
    ///
    /// Falls back to the display name because a large share of real playlists
    /// omit `tvg-id` entirely.
    public var epgMatchKey: String {
        if let tvgID = attributes.tvgID, !tvgID.isEmpty {
            return tvgID
        }
        if let tvgName = attributes.tvgName, !tvgName.isEmpty {
            return tvgName
        }
        return name
    }
}

/// Playlist-level metadata from the `#EXTM3U` header line.
public struct PlaylistHeader: Sendable, Equatable, Codable {
    /// EPG sources advertised by the playlist, from `url-tvg` or `x-tvg-url`.
    ///
    /// Either attribute may hold several comma-separated URLs.
    public var epgURLs: [String]

    public init(epgURLs: [String] = []) {
        self.epgURLs = epgURLs
    }
}
