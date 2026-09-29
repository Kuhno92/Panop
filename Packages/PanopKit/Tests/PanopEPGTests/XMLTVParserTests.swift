import Foundation
@testable import PanopEPG
import Testing

private func parse(
    _ text: String,
    chunkSize: Int = 1_000_000,
    window: ClosedRange<Date>? = nil
) throws -> (elements: [EPGElement], parser: XMLTVParser) {
    var parser = XMLTVParser(window: window)
    let bytes = Array(text.utf8)
    var elements: [EPGElement] = []
    var offset = 0
    while offset < bytes.count {
        let end = min(offset + chunkSize, bytes.count)
        elements += try parser.consume(Data(bytes[offset ..< end]))
        offset = end
    }
    try parser.finish()
    return (elements, parser)
}

private func programmes(_ elements: [EPGElement]) -> [EPGProgramme] {
    elements.compactMap {
        if case let .programme(programme) = $0 {
            programme
        } else {
            nil
        }
    }
}

private func channels(_ elements: [EPGElement]) -> [EPGChannel] {
    elements.compactMap {
        if case let .channel(channel) = $0 {
            channel
        } else {
            nil
        }
    }
}

private let sample = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">
<tv generator-info-name="test">
  <channel id="ard.de">
    <display-name lang="de">Das Erste</display-name>
    <display-name>ARD</display-name>
    <icon src="http://img/ard.png"/>
  </channel>
  <channel id="zdf.de"><display-name>ZDF</display-name></channel>
  <programme start="20260929180000 +0200" stop="20260929190000 +0200" channel="ard.de">
    <title lang="de">Tagesschau</title>
    <title lang="en">Daily News</title>
    <sub-title>Ausgabe &amp; Wetter</sub-title>
    <desc lang="de">Nachrichten.</desc>
    <category lang="de">Nachrichten</category>
    <category>Info</category>
    <icon src="http://img/ts.png"/>
    <episode-num system="xmltv_ns">0.4.</episode-num>
    <episode-num system="onscreen">S01E05</episode-num>
    <rating system="FSK"><value>0</value><icon src="http://img/rating.png"/></rating>
  </programme>
</tv>
"""

@Suite("XMLTV parsing")
struct XMLTVParserTests {
    static let chunkSizes = [1, 2, 7, 64, 1_000_000]

    @Test
    func `parses channels and programmes`() throws {
        let (elements, _) = try parse(sample)

        #expect(channels(elements) == [
            EPGChannel(id: "ard.de", displayNames: ["Das Erste", "ARD"], iconURL: "http://img/ard.png"),
            EPGChannel(id: "zdf.de", displayNames: ["ZDF"])
        ])

        let programme = try #require(programmes(elements).first)
        #expect(programme.channelID == "ard.de")
        #expect(programme.title == "Tagesschau")
        #expect(programme.language == "de")
        #expect(programme.subtitle == "Ausgabe & Wetter")
        #expect(programme.details == "Nachrichten.")
        #expect(programme.categories == ["Nachrichten", "Info"])
        #expect(programme.stop.timeIntervalSince(programme.start) == 3600)
    }

    @Test(arguments: chunkSizes)
    func `result is identical at every chunk size`(chunkSize: Int) throws {
        let whole = try parse(sample).elements
        #expect(try parse(sample, chunkSize: chunkSize).elements == whole)
    }

    @Test
    func `the first title wins`() throws {
        let programme = try #require(programmes(parse(sample).elements).first)
        #expect(programme.title == "Tagesschau")
    }

    @Test
    func `the onscreen episode number wins over other systems`() throws {
        let programme = try #require(programmes(parse(sample).elements).first)
        #expect(programme.episodeNumber == "S01E05")
    }

    /// `<rating>` carries its own `<icon>`. Reading it as the programme's
    /// artwork would put a rating badge where a poster belongs.
    @Test
    func `an icon nested inside another element is not the programme icon`() throws {
        let programme = try #require(programmes(parse(sample).elements).first)
        #expect(programme.iconURL == "http://img/ts.png")
    }

    @Test
    func `a missing stop time reads as the start`() throws {
        let text = #"<tv><programme start="20260929180000 +0000" channel="a"><title>T</title></programme></tv>"#
        let programme = try #require(programmes(parse(text).elements).first)
        #expect(programme.stop == programme.start)
    }

    @Test
    func `programmes that cannot be used are counted not emitted`() throws {
        let text = """
        <tv>
          <programme start="garbage" channel="a"><title>Bad time</title></programme>
          <programme start="20260929180000 +0000"><title>No channel</title></programme>
          <programme start="20260929180000 +0000" channel="a"></programme>
          <programme start="20260929180000 +0000" channel="a"><title>Good</title></programme>
        </tv>
        """
        let (elements, parser) = try parse(text)
        #expect(programmes(elements).map(\.title) == ["Good"])
        #expect(parser.invalidProgrammes == 3)
    }

    @Test
    func `a channel without an id is ignored`() throws {
        let text = #"<tv><channel><display-name>Orphan</display-name></channel><channel id="a"/></tv>"#
        #expect(try channels(parse(text).elements) == [EPGChannel(id: "a")])
    }

    // MARK: - Rolling window

    @Test
    func `the window keeps only overlapping programmes`() throws {
        func item(_ start: String, _ stop: String, _ title: String) -> String {
            #"<programme start="\#(start) +0000" stop="\#(stop) +0000" channel="a"><title>\#(title)</title></programme>"#
        }
        let text = "<tv>" + [
            item("20260929100000", "20260929110000", "ends before"),
            item("20260929113000", "20260929123000", "straddles the start"),
            item("20260929130000", "20260929140000", "inside"),
            item("20260929143000", "20260929153000", "straddles the end"),
            item("20260929160000", "20260929170000", "starts after")
        ].joined() + "</tv>"

        let from = XMLTVDate.parse("20260929120000 +0000") ?? .distantPast
        let until = XMLTVDate.parse("20260929150000 +0000") ?? .distantFuture
        let (elements, parser) = try parse(text, chunkSize: 9, window: from ... until)

        #expect(programmes(elements).map(\.title) == ["straddles the start", "inside", "straddles the end"])
        #expect(parser.programmesOutsideWindow == 2)
    }

    @Test
    func `channels are never filtered by the window`() throws {
        let from = Date(timeIntervalSince1970: 0)
        let (elements, _) = try parse(sample, window: from ... from)
        #expect(channels(elements).count == 2)
        #expect(programmes(elements).isEmpty)
    }

    // MARK: - Robustness

    /// An HTML error page with status 200 is the common real failure.
    @Test(arguments: [
        "<html><body>Rate limited</body></html>",
        "{\"error\":\"nope\"}x",
        "just text"
    ])
    func `a document that is not XMLTV is rejected`(text: String) {
        #expect(throws: EPGError.notXMLTV) {
            _ = try parse(text, chunkSize: 5)
        }
    }

    @Test
    func `an empty body is rejected`() {
        #expect(throws: EPGError.notXMLTV) {
            _ = try parse("")
        }
    }

    /// A cut-off guide must not look like a shorter one. If it did, replacing
    /// stored listings with it would erase everything past the cut.
    @Test(arguments: [
        "<tv><programme start=\"20260929180000\" channel=\"a\"><title>T</title></programme>",
        "<tv><programme start=\"20260929180000\" chan",
        "<tv>"
    ])
    func `a guide that never closes is truncated`(text: String) {
        #expect(throws: EPGError.truncated) {
            _ = try parse(text, chunkSize: 4)
        }
    }

    @Test
    func `a very long text field is capped not accumulated`() throws {
        let long = String(repeating: "x", count: 500_000)
        let text = #"<tv><programme start="20260929180000" channel="a"><title>T</title><desc>\#(long)</desc></programme></tv>"#
        let programme = try #require(programmes(parse(text, chunkSize: 4096).elements).first)
        #expect((programme.details?.count ?? 0) < 200_000)
    }

    @Test
    func `ignores unknown elements and deeper nesting`() throws {
        let text = """
        <tv>
          <programme start="20260929180000" channel="a">
            <title>T</title>
            <credits><actor>Someone</actor><director>Other</director></credits>
            <video><present>yes</present></video>
            <new/>
          </programme>
        </tv>
        """
        #expect(try programmes(parse(text, chunkSize: 3).elements).map(\.title) == ["T"])
    }
}
