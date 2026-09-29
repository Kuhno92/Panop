import Foundation
@testable import PanopXtream
import Testing

private func split(_ text: String, chunkSize: Int) throws -> [String] {
    var streamer = JSONArrayStreamer()
    let bytes = Array(text.utf8)
    var elements: [String] = []
    var offset = 0
    while offset < bytes.count {
        let end = min(offset + chunkSize, bytes.count)
        for element in try streamer.consume(Data(bytes[offset ..< end])) {
            let text = String(bytes: element, encoding: .utf8) ?? ""
            elements.append(text.trimmingCharacters(in: .whitespaces))
        }
        offset = end
    }
    try streamer.finish()
    return elements
}

@Suite("JSON array streaming")
struct JSONArrayStreamerTests {
    /// One-byte chunks are the harshest case: every boundary falls inside a
    /// token, an escape, or a string.
    static let chunkSizes = [1, 2, 3, 7, 64, 100_000]

    @Test(arguments: chunkSizes)
    func `splits objects at every chunk size`(chunkSize: Int) throws {
        let text = #"[{"a":1},{"b":[1,2,{"c":3}]}, {"d":"x"}]"#
        #expect(try split(text, chunkSize: chunkSize) == [#"{"a":1}"#, #"{"b":[1,2,{"c":3}]}"#, #"{"d":"x"}"#])
    }

    /// A naive brace counter miscounts on these, and channel names contain them.
    @Test(arguments: chunkSizes)
    func `ignores structural characters inside strings`(chunkSize: Int) throws {
        let text = #"[{"name":"Sport } { , ] ["},{"name":"He said \"}\" and \\"}]"#
        let elements = try split(text, chunkSize: chunkSize)
        #expect(elements.count == 2)
        #expect(elements[0] == #"{"name":"Sport } { , ] ["}"#)
        #expect(elements[1] == #"{"name":"He said \"}\" and \\"}"#)
    }

    @Test(arguments: chunkSizes)
    func `handles scalar and string elements`(chunkSize: Int) throws {
        #expect(try split(#"[1, 22 ,"a,b", true]"#, chunkSize: chunkSize) == ["1", "22", #""a,b""#, "true"])
    }

    @Test
    func `empty array yields nothing`() throws {
        #expect(try split("[]", chunkSize: 1).isEmpty)
        #expect(try split("  [ \n ]  ", chunkSize: 1).isEmpty)
    }

    /// Panels answer an empty category with these instead of `[]`.
    @Test
    func `null false and an empty body read as no elements`() throws {
        #expect(try split("null", chunkSize: 1).isEmpty)
        #expect(try split("false", chunkSize: 2).isEmpty)
        #expect(try split("", chunkSize: 1).isEmpty)
    }

    /// An auth failure or a rate limit arrives as an object with status 200.
    @Test
    func `an object is not an array`() {
        #expect(throws: JSONArrayStreamer.Failure.notAnArray) {
            _ = try split(#"{"user_info":{"auth":0}}"#, chunkSize: 5)
        }
    }

    @Test
    func `an unknown bare word is not an array`() {
        #expect(throws: JSONArrayStreamer.Failure.notAnArray) {
            _ = try split("error", chunkSize: 1)
        }
    }

    /// The failure that matters most: a cut-off download must never look like
    /// a complete catalog.
    @Test(arguments: [#"[{"a":1},{"b":"#, #"[{"a":1},"#, #"[{"a":1}"#, "["])
    func `a truncated body throws`(text: String) {
        #expect(throws: JSONArrayStreamer.Failure.truncated) {
            _ = try split(text, chunkSize: 3)
        }
    }

    @Test
    func `handles multibyte characters split across chunks`() throws {
        let text = #"[{"name":"Café ☕ 日本"}]"#
        #expect(try split(text, chunkSize: 1) == [#"{"name":"Café ☕ 日本"}"#])
    }
}
