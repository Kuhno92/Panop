import Foundation

/// Tells an HLS manifest apart from an IPTV playlist.
///
/// Both are `.m3u8` text files that start with `#EXTM3U`, so a URL ending in `.m3u8`
/// could be either. An IPTV playlist lists many channels, each with its own address. An
/// HLS manifest describes **one** stream (its variants, audio groups or segments), and
/// its entries are parts of that stream, not channels. Importing one as a playlist
/// produces rows named `1.m3u8`, `2.m3u8` whose addresses are usually relative paths
/// that nothing can play.
///
/// The signal is a tag that only HLS uses. A playlist never has one.
public enum HLSManifest {
    /// Tags that appear in a multivariant or media playlist and never in an IPTV playlist.
    private static let markers = [
        "#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-MEDIA:",
        "#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE", "#EXT-X-PLAYLIST-TYPE"
    ]

    /// How the stream behaves, for choosing what kind of item it is.
    public enum Kind: Sendable, Equatable {
        /// No `#EXT-X-ENDLIST`: a live stream, or a multivariant playlist (which names streams).
        case live
        /// Has `#EXT-X-ENDLIST`: a fixed-length recording.
        case onDemand
    }

    /// Whether `prefix` (the start of a file) is an HLS manifest, and of which kind.
    /// A prefix of the first 64 KB is plenty: the tags come before any media.
    public static func kind(ofPrefix prefix: Data) -> Kind? {
        let text = String(bytes: prefix.prefix(64 * 1024), encoding: .utf8) ?? ""
        guard text.hasPrefix("#EXTM3U") || text.contains("#EXTM3U") else { return nil }

        var isHLS = false
        var ended = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXT-X-") else { continue }
            if markers.contains(where: { line.hasPrefix($0) }) {
                isHLS = true
            }
            if line.hasPrefix("#EXT-X-ENDLIST") {
                ended = true
            }
        }
        guard isHLS else { return nil }
        return ended ? .onDemand : .live
    }
}
