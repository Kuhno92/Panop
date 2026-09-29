import Foundation
import PanopCore
@testable import PanopPlaylist
import Testing

// Helper: parse a whole string in one go.
private func parseAll(_ text: String) -> (entries: [PlaylistEntry], header: PlaylistHeader) {
    var parser = M3UParser()
    var entries = parser.consume(Array(text.utf8))
    entries += parser.finish()
    return (entries, parser.header)
}

@Suite("M3U parsing")
struct M3UParserTests {
    @Test
    func `parses a minimal entry`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1,Das Erste
            http://example.com/live/1.ts
            """
        )

        #expect(entries.count == 1)
        #expect(entries[0].name == "Das Erste")
        #expect(entries[0].url == "http://example.com/live/1.ts")
        #expect(entries[0].duration == -1)
    }

    @Test
    func `parses tvg attributes`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1 tvg-id="ard.de" tvg-name="ARD" tvg-logo="http://img/1.png" group-title="DE",Das Erste HD
            http://example.com/live/1.ts
            """
        )

        let attributes = entries[0].attributes
        #expect(attributes.tvgID == "ard.de")
        #expect(attributes.tvgName == "ARD")
        #expect(attributes.tvgLogo == "http://img/1.png")
        #expect(attributes.groupTitle == "DE")
        #expect(entries[0].name == "Das Erste HD")
    }

    /// A plain split on "," corrupts these, and real playlists contain them
    /// constantly in group titles.
    @Test
    func `a comma inside a quoted attribute does not split the name`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1 tvg-id="x" group-title="Sports, Live",ESPN HD
            http://example.com/live/2.ts
            """
        )

        #expect(entries[0].attributes.groupTitle == "Sports, Live")
        #expect(entries[0].name == "ESPN HD")
    }

    @Test
    func `reads EPG urls from the header`() {
        let (_, header) = parseAll(
            """
            #EXTM3U url-tvg="http://example.com/epg.xml.gz,http://backup/epg.xml"
            #EXTINF:-1,A
            http://example.com/live/1.ts
            """
        )

        #expect(header.epgURLs == ["http://example.com/epg.xml.gz", "http://backup/epg.xml"])
    }

    @Test
    func `accepts the x-tvg-url spelling too`() {
        let (_, header) = parseAll(#"#EXTM3U x-tvg-url="http://example.com/guide.xml""#)
        #expect(header.epgURLs == ["http://example.com/guide.xml"])
    }

    @Test
    func `#EXTGRP fills in a missing group title`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1,Channel A
            #EXTGRP:News
            http://example.com/live/1.ts
            """
        )

        #expect(entries[0].attributes.groupTitle == "News")
    }

    @Test
    func `group-title wins over #EXTGRP`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1 group-title="Movies",Channel A
            #EXTGRP:News
            http://example.com/live/1.ts
            """
        )

        #expect(entries[0].attributes.groupTitle == "Movies")
    }

    @Test
    func `ignores directives that do not affect playback`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTVLCOPT:network-caching=1000
            #KODIPROP:inputstream=inputstream.adaptive
            #EXTINF:-1,Channel A
            #EXTVLCOPT:http-user-agent=Foo
            http://example.com/live/1.ts
            """
        )

        #expect(entries.count == 1)
        #expect(entries[0].name == "Channel A")
    }

    @Test
    func `keeps a bare url that has no #EXTINF`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            http://example.com/live/sky-sports.ts
            """
        )

        #expect(entries.count == 1)
        #expect(entries[0].name == "sky-sports.ts")
    }

    @Test(
        arguments: [
            ("http://h/live/u/p/1.ts", -1.0, MediaKind.live),
            ("http://h/movie/u/p/1.mkv", 7200.0, MediaKind.movie),
            ("http://h/series/u/p/1.mkv", 1500.0, MediaKind.series),
            ("http://h/stream.ts", -1.0, MediaKind.live),
            ("http://h/stream.mkv", 5400.0, MediaKind.movie)
        ]
    )
    func `infers media kind`(url: String, duration: Double, expected: MediaKind) {
        #expect(M3UParser.inferKind(url: url, duration: duration) == expected)
    }

    @Test
    func `falls back to tvg-name when the display name is empty`() {
        let (entries, _) = parseAll(
            """
            #EXTM3U
            #EXTINF:-1 tvg-name="Fallback Name",
            http://example.com/live/1.ts
            """
        )

        #expect(entries[0].name == "Fallback Name")
    }

    @Test
    func `handles CRLF line endings`() {
        let (entries, _) = parseAll("#EXTM3U\r\n#EXTINF:-1,A\r\nhttp://e/1.ts\r\n")
        #expect(entries.count == 1)
        #expect(entries[0].name == "A")
        #expect(entries[0].url == "http://e/1.ts")
    }

    @Test
    func `emits a trailing entry that has no final newline`() {
        var parser = M3UParser()
        var entries = parser.consume(Array("#EXTM3U\n#EXTINF:-1,A\nhttp://e/1.ts".utf8))
        #expect(entries.isEmpty)
        entries += parser.finish()
        #expect(entries.count == 1)
    }
}

@Suite("M3U chunk boundaries")
struct M3UChunkBoundaryTests {
    private static let playlist = """
    #EXTM3U url-tvg="http://example.com/epg.xml"
    #EXTINF:-1 tvg-id="a.de" tvg-logo="http://img/a.png" group-title="Nachrichten, DE",Kanal Ä
    http://example.com/live/1.ts
    #EXTINF:-1 tvg-id="b.de" group-title="Sport",Kanal Ö
    http://example.com/live/2.ts
    #EXTINF:7200 tvg-id="" group-title="Filme",Ein Film
    http://example.com/movie/3.mkv

    """

    /// Chunk boundaries land wherever the network puts them, including inside a
    /// multi-byte character. Feeding every possible split must give one answer.
    @Test(arguments: [1, 2, 3, 7, 16, 64, 256, 4096])
    func `result is identical at every chunk size`(chunkSize: Int) {
        let bytes = Array(Self.playlist.utf8)

        var parser = M3UParser()
        var entries: [PlaylistEntry] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + chunkSize, bytes.count)
            entries += parser.consume(bytes[index ..< end])
            index = end
        }
        entries += parser.finish()

        #expect(entries.count == 3)
        #expect(entries[0].name == "Kanal Ä")
        #expect(entries[0].attributes.groupTitle == "Nachrichten, DE")
        #expect(entries[1].name == "Kanal Ö")
        #expect(entries[2].mediaKind == .movie)
        #expect(parser.header.epgURLs == ["http://example.com/epg.xml"])
    }
}

@Suite("M3U attribute scanning")
struct M3UAttributeTests {
    @Test
    func `parses quoted values`() {
        let result = M3UParser.parseAttributes(#"-1 tvg-id="a" tvg-name="B C" group-title="D, E""#[...])
        #expect(result["tvg-id"] == "a")
        #expect(result["tvg-name"] == "B C")
        #expect(result["group-title"] == "D, E")
    }

    @Test
    func `parses unquoted values`() {
        let result = M3UParser.parseAttributes("-1 tvg-id=abc group-title=News"[...])
        #expect(result["tvg-id"] == "abc")
        #expect(result["group-title"] == "News")
    }

    @Test
    func `survives an unterminated quote`() {
        let result = M3UParser.parseAttributes(#"-1 tvg-id="abc"#[...])
        #expect(result["tvg-id"] == "abc")
    }

    @Test
    func `lowercases keys so casing variation does not lose attributes`() {
        let result = M3UParser.parseAttributes(#"-1 TVG-ID="a" Group-Title="B""#[...])
        #expect(result["tvg-id"] == "a")
        #expect(result["group-title"] == "B")
    }

    @Test
    func `decodes Latin-1 bytes that are not valid UTF-8`() {
        // 0xE4 is "ä" in Latin-1 and an invalid UTF-8 lead byte.
        let bytes: [UInt8] = Array("Kanal ".utf8) + [0xE4]
        #expect(M3UParser.decode(bytes) == "Kanal ä")
    }
}
