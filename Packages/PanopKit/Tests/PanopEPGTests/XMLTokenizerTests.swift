import Foundation
@testable import PanopEPG
import Testing

private func tokenize(_ text: String, chunkSize: Int) throws -> [XMLTokenizer.Event] {
    var tokenizer = XMLTokenizer()
    let bytes = Array(text.utf8)
    var events: [XMLTokenizer.Event] = []
    var offset = 0
    while offset < bytes.count {
        let end = min(offset + chunkSize, bytes.count)
        events += try tokenizer.consume(Data(bytes[offset ..< end]))
        offset = end
    }
    try tokenizer.finish()
    return events
}

private func start(_ name: String, _ attributes: [(String, String)] = []) -> XMLTokenizer.Event {
    .start(name: name, attributes: attributes.map { XMLTokenizer.Attribute(name: $0.0, value: $0.1) })
}

@Suite("XML tokenizing")
struct XMLTokenizerTests {
    static let chunkSizes = [1, 2, 3, 5, 11, 1_000_000]

    @Test(arguments: chunkSizes)
    func `emits elements attributes and text`(chunkSize: Int) throws {
        let events = try tokenize(#"<a x="1" y='two'><b>hi</b><c/></a>"#, chunkSize: chunkSize)
        #expect(events == [
            start("a", [("x", "1"), ("y", "two")]),
            start("b"), .text("hi"), .end(name: "b"),
            start("c"), .end(name: "c"),
            .end(name: "a")
        ])
    }

    @Test(arguments: chunkSizes)
    func `resolves the predefined and numeric entities`(chunkSize: Int) throws {
        let events = try tokenize(
            #"<a t="&quot;q&quot; &amp; &apos;s&apos;">&lt;x&gt; &#65;&#x42; &#x1F600;</a>"#,
            chunkSize: chunkSize
        )
        #expect(events == [
            start("a", [("t", #""q" & 's'"#)]),
            .text("<x> AB \u{1F600}"),
            .end(name: "a")
        ])
    }

    /// Titles such as "Tom & Jerry" appear unescaped in careless guides.
    @Test
    func `keeps an ampersand that is not an entity`() throws {
        let events = try tokenize("<a>Tom & Jerry &bogus; AT&T</a>", chunkSize: 4)
        #expect(events == [start("a"), .text("Tom & Jerry &bogus; AT&T"), .end(name: "a")])
    }

    @Test(arguments: chunkSizes)
    func `passes CDATA through untouched`(chunkSize: Int) throws {
        let events = try tokenize("<a><![CDATA[<b> & </b>]]></a>", chunkSize: chunkSize)
        #expect(events == [start("a"), .text("<b> & </b>"), .end(name: "a")])
    }

    @Test(arguments: chunkSizes)
    func `skips comments processing instructions and doctype`(chunkSize: Int) throws {
        let text = """
        <?xml version="1.0"?>
        <!DOCTYPE tv SYSTEM "xmltv.dtd" [ <!ENTITY x "a>b"> ]>
        <!-- a comment with <tags> and > inside -->
        <a>ok</a>
        """
        #expect(try tokenize(text, chunkSize: chunkSize) == [start("a"), .text("ok"), .end(name: "a")])
    }

    /// A '>' inside a quoted attribute must not end the tag.
    @Test(arguments: chunkSizes)
    func `a greater-than inside an attribute does not end the tag`(chunkSize: Int) throws {
        let events = try tokenize(#"<a href="x>y" n='a"b'/>"#, chunkSize: chunkSize)
        #expect(events == [start("a", [("href", "x>y"), ("n", #"a"b"#)]), .end(name: "a")])
    }

    @Test
    func `drops whitespace between elements`() throws {
        let events = try tokenize("<a>\n  <b>x</b>\n</a>", chunkSize: 3)
        #expect(events == [start("a"), start("b"), .text("x"), .end(name: "b"), .end(name: "a")])
    }

    @Test
    func `tolerates whitespace around names and attributes`() throws {
        let events = try tokenize(#"<a  x = "1"  ></a >"#, chunkSize: 2)
        #expect(events == [start("a", [("x", "1")]), .end(name: "a")])
    }

    @Test(arguments: chunkSizes)
    func `handles multibyte text split across chunks`(chunkSize: Int) throws {
        let events = try tokenize("<a>Café ☕ 日本</a>", chunkSize: chunkSize)
        #expect(events == [start("a"), .text("Café ☕ 日本"), .end(name: "a")])
    }

    /// Latin-1 guides are common and are not valid UTF-8.
    @Test
    func `falls back to Latin-1 for invalid UTF-8`() throws {
        var tokenizer = XMLTokenizer()
        var bytes = Array("<a>caf".utf8)
        bytes.append(0xE9)
        bytes += Array("</a>".utf8)
        let events = try tokenizer.consume(Data(bytes))
        #expect(events == [start("a"), .text("café"), .end(name: "a")])
    }

    @Test(arguments: ["<a", "<a x=\"1", "<!-- open", "<![CDATA[ open", "<a></a", "<!DOCTYPE tv ["])
    func `input that stops inside a token is truncated`(text: String) {
        #expect(throws: XMLTokenizer.Failure.truncated) {
            _ = try tokenize(text, chunkSize: 3)
        }
    }

    /// Streaming must not degrade into buffering the whole document.
    @Test
    func `a huge unterminated token is rejected`() {
        var tokenizer = XMLTokenizer()
        #expect(throws: XMLTokenizer.Failure.malformed) {
            _ = try tokenizer.consume(Data("<a ".utf8))
            for _ in 0 ..< 5 {
                _ = try tokenizer.consume(Data(repeating: UInt8(ascii: "x"), count: 1_000_000))
            }
        }
    }
}
