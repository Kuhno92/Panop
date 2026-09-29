import Foundation
import PanopCore

/// Incremental M3U/M3U8 parser.
///
/// Push bytes in with ``consume(_:)`` and entries come out as they complete.
/// The parser holds only the current line plus one pending `#EXTINF`, so a
/// playlist of any size costs constant memory. Real provider playlists reach
/// 80,000 entries and loading one as a single string is the difference between
/// a responsive import and a jetsam kill on tvOS.
///
/// Chunk boundaries may fall anywhere, including mid-line and mid-UTF-8.
///
/// ```swift
/// var parser = M3UParser()
/// var entries = parser.consume(firstChunk)
/// entries += parser.consume(secondChunk)
/// entries += parser.finish()
/// ```
public struct M3UParser: Sendable {
    /// Playlist-level metadata. Populated once the `#EXTM3U` line is seen.
    public private(set) var header = PlaylistHeader()

    private var carry: [UInt8] = []
    private var pendingDuration: Double?
    private var pendingAttributes = ChannelAttributes()
    private var pendingName: String?
    /// From a standalone `#EXTGRP:` line, which overrides nothing but fills in
    /// a missing `group-title`.
    private var pendingGroup: String?

    public init() {}

    /// Feeds a chunk of bytes and returns whatever entries completed.
    public mutating func consume(_ bytes: some Sequence<UInt8>) -> [PlaylistEntry] {
        var output: [PlaylistEntry] = []
        for byte in bytes {
            if byte == 0x0A {
                consumeLine(into: &output)
            } else if byte != 0x0D {
                carry.append(byte)
            }
        }
        return output
    }

    /// Flushes a trailing line that was not newline-terminated.
    public mutating func finish() -> [PlaylistEntry] {
        var output: [PlaylistEntry] = []
        if !carry.isEmpty {
            consumeLine(into: &output)
        }
        return output
    }

    private mutating func consumeLine(into output: inout [PlaylistEntry]) {
        defer { carry.removeAll(keepingCapacity: true) }

        let line = Self.decode(carry).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }

        if line.hasPrefix("#") {
            handleDirective(line)
            return
        }

        // Any non-comment line is the URL for the preceding #EXTINF. Providers
        // sometimes emit a bare URL with no #EXTINF at all, so fall back to the
        // last path component for a name rather than dropping the entry.
        let name = pendingName ?? Self.fallbackName(for: line)
        var attributes = pendingAttributes
        if attributes.groupTitle == nil {
            attributes.groupTitle = pendingGroup
        }

        output.append(
            PlaylistEntry(
                name: name,
                url: line,
                duration: pendingDuration,
                attributes: attributes,
                mediaKind: Self.inferKind(url: line, duration: pendingDuration)
            )
        )

        pendingName = nil
        pendingDuration = nil
        pendingAttributes = ChannelAttributes()
        pendingGroup = nil
    }

    private mutating func handleDirective(_ line: String) {
        if line.hasPrefix("#EXTINF:") {
            parseExtInf(line.dropFirst("#EXTINF:".count))
        } else if line.hasPrefix("#EXTGRP:") {
            pendingGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("#EXTM3U") {
            parseHeader(line.dropFirst("#EXTM3U".count))
        }
        // Everything else (#EXTVLCOPT, #KODIPROP, #EXTIMG, plain comments) is
        // deliberately ignored: none of it changes what Panop plays.
    }

    private mutating func parseHeader(_ rest: Substring) {
        let attributes = Self.parseAttributes(rest)
        // Either spelling may appear, and either may hold several comma-separated URLs.
        for key in ["url-tvg", "x-tvg-url"] {
            guard let value = attributes[key] else { continue }
            for url in value.split(separator: ",") {
                let trimmed = url.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !header.epgURLs.contains(trimmed) {
                    header.epgURLs.append(trimmed)
                }
            }
        }
    }

    private mutating func parseExtInf(_ rest: Substring) {
        // Layout: <duration> [key="value" ...],<display name>
        // The display name is whatever follows the last comma that is not
        // inside quotes. Attribute values legitimately contain commas, which is
        // why a plain split on "," corrupts a noticeable fraction of playlists.
        let splitIndex = Self.lastUnquotedComma(in: rest)
        let metadata: Substring
        if let splitIndex {
            metadata = rest[rest.startIndex ..< splitIndex]
            pendingName = String(rest[rest.index(after: splitIndex)...]).trimmingCharacters(in: .whitespaces)
        } else {
            metadata = rest
            pendingName = nil
        }

        // Duration is the first whitespace-delimited token.
        if let firstToken = metadata.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first {
            pendingDuration = Double(firstToken)
        }

        let attributes = Self.parseAttributes(metadata)
        pendingAttributes = ChannelAttributes(
            tvgID: attributes["tvg-id"],
            tvgName: attributes["tvg-name"],
            tvgLogo: attributes["tvg-logo"],
            groupTitle: attributes["group-title"],
            tvgShift: attributes["tvg-shift"],
            catchup: attributes["catchup"],
            catchupSource: attributes["catchup-source"],
            catchupDays: attributes["catchup-days"]
        )

        // A missing display name is common on entries that carry tvg-name.
        if pendingName?.isEmpty ?? true {
            pendingName = attributes["tvg-name"]
        }
    }

    // MARK: - Helpers

    /// Decodes a line, falling back to Latin-1 when the bytes are not valid UTF-8.
    ///
    /// Provider playlists are frequently mislabelled or mixed-encoding, and a
    /// lossy UTF-8 decode turns accented channel names into replacement
    /// characters that then fail to match EPG data.
    static func decode(_ bytes: [UInt8]) -> String {
        if let utf8 = String(bytes: bytes, encoding: .utf8) {
            return utf8
        }
        return String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    static func lastUnquotedComma(in text: Substring) -> Substring.Index? {
        var inQuotes = false
        var result: Substring.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                result = index
            }
            index = text.index(after: index)
        }
        return result
    }

    /// Extracts `key="value"` and bare `key=value` pairs.
    static func parseAttributes(_ text: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var index = text.startIndex

        while index < text.endIndex {
            // Find the next '=' and walk back to the start of its key.
            guard let equals = text[index...].firstIndex(of: "=") else { break }

            var keyStart = equals
            while keyStart > text.startIndex {
                let previous = text.index(before: keyStart)
                if text[previous] == " " || text[previous] == "\t" {
                    break
                }
                keyStart = previous
            }
            let key = String(text[keyStart ..< equals]).lowercased()

            var valueStart = text.index(after: equals)
            var value = ""
            if valueStart < text.endIndex, text[valueStart] == "\"" {
                valueStart = text.index(after: valueStart)
                if let closing = text[valueStart...].firstIndex(of: "\"") {
                    value = String(text[valueStart ..< closing])
                    index = text.index(after: closing)
                } else {
                    // Unterminated quote: take the rest and stop.
                    value = String(text[valueStart...])
                    index = text.endIndex
                }
            } else {
                let end = text[valueStart...].firstIndex(of: " ") ?? text.endIndex
                value = String(text[valueStart ..< end])
                index = end
            }

            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    static func inferKind(url: String, duration: Double?) -> MediaKind {
        // Xtream-style URLs carry the kind in the path, which is more reliable
        // than duration because some providers emit -1 for everything.
        let lowered = url.lowercased()
        if lowered.contains("/series/") {
            return .series
        }
        if lowered.contains("/movie/") {
            return .movie
        }
        if lowered.contains("/live/") {
            return .live
        }

        guard let duration else { return .unknown }
        if duration < 0 {
            return .live
        }
        if duration > 0 {
            return .movie
        }
        return .unknown
    }

    static func fallbackName(for url: String) -> String {
        let withoutQuery = url.split(separator: "?").first.map(String.init) ?? url
        let lastComponent = withoutQuery.split(separator: "/").last.map(String.init) ?? withoutQuery
        return lastComponent.isEmpty ? url : lastComponent
    }
}
