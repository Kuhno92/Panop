import Foundation

/// Cuts a multivariant HLS playlist down to one video stream.
///
/// FFmpeg's HLS demuxer, which LumeEngine is built on, opens **every** variant and audio group of
/// a multivariant playlist before it starts: one request per playlist, then a segment of each to
/// find out what is in it. A broadcaster's playlist with six video variants and eight audio and
/// subtitle entries took about 3.2 seconds to start, against about 0.9 seconds for a playlist
/// naming only the variant actually played (measured on a real broadcast stream). FFmpeg does not
/// switch between variants as the network changes either, so naming one loses no adaptive
/// behaviour: it only stops paying to open the ones that would never be used.
///
/// The playlist this makes names the best variant under a bitrate cap, the audio that variant
/// uses, and nothing else (no subtitles, which Panop draws from their own tracks). Every address
/// is made absolute, since the new playlist lives somewhere other than the old one.
public enum HLSMultivariant {
    /// Above this the stream is more than a living-room connection should be asked to carry in
    /// real time, and more than the engines' read-ahead is sized for.
    public static let defaultBandwidthCap = 6_000_000

    /// The simplified playlist, or nil when there is nothing to simplify: not a multivariant
    /// playlist, or one with a single variant.
    ///
    /// - Parameters:
    ///   - text: the multivariant playlist as downloaded.
    ///   - base: the address it was downloaded from, for resolving relative addresses.
    ///   - maxBandwidth: the highest bits per second to choose.
    public static func simplified(_ text: String, base: URL, maxBandwidth: Int = defaultBandwidthCap) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }

        var variants: [Variant] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            guard let uri = lines[(index + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix("#") }) else { continue }
            let attributes = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            let bandwidth = attributes.first { $0.key == "BANDWIDTH" }.flatMap { Int($0.value) } ?? 0
            variants.append(Variant(attributes: attributes, uri: uri, bandwidth: bandwidth))
        }
        guard variants.count > 1 else { return nil }

        // The best under the cap; the first in the file among equals (a broadcaster that lists the
        // same stream on two paths puts its primary first); the lowest if every one is over.
        let underCap = variants.filter { $0.bandwidth <= maxBandwidth }
        let chosen: Variant
        if let best = underCap.map(\.bandwidth).max() {
            chosen = underCap.first { $0.bandwidth == best } ?? variants[0]
        } else {
            let lowest = variants.map(\.bandwidth).min() ?? 0
            chosen = variants.first { $0.bandwidth == lowest } ?? variants[0]
        }
        let audioGroup = chosen.attributes.first { $0.key == "AUDIO" }.map { unquoted($0.value) }

        var output = ["#EXTM3U"]
        output += lines.filter { $0.hasPrefix("#EXT-X-VERSION") || $0.hasPrefix("#EXT-X-INDEPENDENT-SEGMENTS") }
        if let audioGroup {
            for line in lines where line.hasPrefix("#EXT-X-MEDIA:") {
                let attributes = parseAttributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                let value = { (key: String) in attributes.first { $0.key == key }.map { unquoted($0.value) } }
                guard value("TYPE") == "AUDIO", value("GROUP-ID") == audioGroup else { continue }
                output.append("#EXT-X-MEDIA:" + render(attributes, absoluteAgainst: base))
            }
        }
        // Subtitles and closed captions are left out: they would each be one more playlist to open.
        let kept = chosen.attributes.filter { $0.key != "SUBTITLES" && $0.key != "CLOSED-CAPTIONS" }
        output.append("#EXT-X-STREAM-INF:" + render(kept, absoluteAgainst: base))
        output.append(absolute(chosen.uri, against: base))
        return output.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    private struct Variant {
        var attributes: [(key: String, value: String)]
        var uri: String
        var bandwidth: Int
    }

    /// `KEY=value,KEY="a,b"` into pairs, in order. Commas inside quotes belong to the value:
    /// `CODECS="avc1.4d401f,mp4a.40.2"` is one attribute.
    private static func parseAttributes(_ text: String) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        var current = ""
        var inQuotes = false
        func finish() {
            if let equals = current.firstIndex(of: "=") {
                pairs.append((
                    key: String(current[..<equals]).trimmingCharacters(in: .whitespaces),
                    value: String(current[current.index(after: equals)...])
                ))
            }
            current = ""
        }
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == ",", !inQuotes {
                finish()
            } else {
                current.append(character)
            }
        }
        finish()
        return pairs
    }

    private static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Puts the attributes back as written, with any `URI` made absolute.
    private static func render(_ attributes: [(key: String, value: String)], absoluteAgainst base: URL) -> String {
        attributes.map { attribute in
            guard attribute.key == "URI" else { return "\(attribute.key)=\(attribute.value)" }
            return "URI=\"\(absolute(unquoted(attribute.value), against: base))\""
        }.joined(separator: ",")
    }

    private static func absolute(_ address: String, against base: URL) -> String {
        URL(string: address, relativeTo: base)?.absoluteURL.absoluteString ?? address
    }
}
