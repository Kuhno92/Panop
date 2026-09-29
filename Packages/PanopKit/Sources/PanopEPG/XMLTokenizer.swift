import Foundation

/// A small incremental XML tokenizer, fed chunks and returning complete events.
///
/// Written instead of using `XMLParser` because that is push-only (it cannot
/// let a slow consumer slow the download), lives in a separate module off-Apple,
/// and is slow enough to matter on a 100 MB guide. XMLTV needs a small, regular
/// subset of XML, so this handles exactly that: elements, attributes, text,
/// CDATA, comments, processing instructions, and a `<!DOCTYPE>` that is skipped.
/// It does not validate, resolve DTD entities, or handle namespaces.
///
/// Events are only ever produced for complete tokens. A tag or text run split
/// across chunks is held back until the rest arrives, so callers never see a
/// fragment.
struct XMLTokenizer {
    enum Failure: Error, Equatable {
        /// A single unfinished token grew past the sanity limit.
        case malformed
        /// The input ended inside a tag, comment or CDATA section.
        case truncated
    }

    struct Attribute: Equatable {
        var name: String
        var value: String
    }

    enum Event: Equatable {
        case start(name: String, attributes: [Attribute])
        case end(name: String)
        case text(String)
    }

    /// No legitimate XMLTV token is anywhere near this size. The cap stops a
    /// hostile or broken response from growing the buffer without bound.
    private static let maxPendingBytes = 4 * 1024 * 1024

    private static let lessThan = UInt8(ascii: "<")
    private static let greaterThan = UInt8(ascii: ">")
    private static let ampersand = UInt8(ascii: "&")

    private var buffer: [UInt8] = []
    private var cursor = 0

    mutating func consume(_ chunk: Data) throws -> [Event] {
        buffer.append(contentsOf: chunk)
        var events: [Event] = []
        scan(into: &events)
        if cursor > 0 {
            buffer.removeFirst(cursor)
            cursor = 0
        }
        if buffer.count > Self.maxPendingBytes {
            throw Failure.malformed
        }
        return events
    }

    /// Throws if the input stopped in the middle of a token.
    func finish() throws {
        if buffer[cursor...].contains(Self.lessThan) {
            throw Failure.truncated
        }
    }

    // MARK: - Scanning

    private mutating func scan(into events: inout [Event]) {
        while cursor < buffer.count {
            if buffer[cursor] != Self.lessThan {
                // Text runs to the next tag. Without one yet, wait for more.
                guard let next = buffer[cursor...].firstIndex(of: Self.lessThan) else { return }
                emitText(cursor ..< next, into: &events)
                cursor = next
                continue
            }
            guard cursor + 1 < buffer.count else { return }

            let complete: Bool = switch buffer[cursor + 1] {
            case UInt8(ascii: "!"): scanDeclaration(into: &events)
            case UInt8(ascii: "?"): skip(past: Array("?>".utf8), from: cursor + 2)
            case UInt8(ascii: "/"): scanEndTag(into: &events)
            default: scanStartTag(into: &events)
            }
            if !complete {
                return
            }
        }
    }

    private mutating func emitText(_ range: Range<Int>, into events: inout [Event]) {
        let slice = buffer[range]
        guard slice.contains(where: { !Self.isSpace($0) }) else { return }
        events.append(.text(Self.decode(slice)))
    }

    // MARK: - Tags

    private mutating func scanStartTag(into events: inout [Event]) -> Bool {
        // Find the closing '>', skipping any that sit inside a quoted value.
        var index = cursor + 1
        var quote: UInt8 = 0
        while index < buffer.count {
            let byte = buffer[index]
            if quote != 0 {
                if byte == quote {
                    quote = 0
                }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == Self.greaterThan {
                break
            }
            index += 1
        }
        guard index < buffer.count else { return false }

        let selfClosing = buffer[index - 1] == UInt8(ascii: "/") && index - 1 > cursor
        let (name, attributes) = parseTag(cursor + 1 ..< (selfClosing ? index - 1 : index))
        events.append(.start(name: name, attributes: attributes))
        if selfClosing {
            events.append(.end(name: name))
        }
        cursor = index + 1
        return true
    }

    private mutating func scanEndTag(into events: inout [Event]) -> Bool {
        guard let close = buffer[(cursor + 2)...].firstIndex(of: Self.greaterThan) else { return false }
        let name = Self.decode(trimmed(cursor + 2 ..< close))
        events.append(.end(name: name))
        cursor = close + 1
        return true
    }

    /// `<!-- -->`, `<![CDATA[ ]]>`, and declarations such as `<!DOCTYPE>`.
    private mutating func scanDeclaration(into events: inout [Event]) -> Bool {
        switch match("<!--") {
        case .partial: return false
        case .matches: return skip(past: Array("-->".utf8), from: cursor + 4)
        case .mismatch: break
        }
        switch match("<![CDATA[") {
        case .partial: return false
        case .matches:
            let start = cursor + 9
            guard let end = find(Array("]]>".utf8), from: start) else { return false }
            if end > start {
                events.append(.text(Self.utf8String(buffer[start ..< end])))
            }
            cursor = end + 3
            return true
        case .mismatch: break
        }

        // A declaration. Its internal subset can hold '>' inside brackets and
        // quotes, so track both.
        var depth = 0
        var quote: UInt8 = 0
        var index = cursor + 2
        while index < buffer.count {
            let byte = buffer[index]
            if quote != 0 {
                if byte == quote {
                    quote = 0
                }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "[") {
                depth += 1
            } else if byte == UInt8(ascii: "]") {
                depth -= 1
            } else if byte == Self.greaterThan, depth <= 0 {
                cursor = index + 1
                return true
            }
            index += 1
        }
        return false
    }

    // MARK: - Tag contents

    private func parseTag(_ range: Range<Int>) -> (String, [Attribute]) {
        var index = range.lowerBound
        let end = range.upperBound

        while index < end, !Self.isSpace(buffer[index]) {
            index += 1
        }
        let name = Self.decode(buffer[range.lowerBound ..< index])

        var attributes: [Attribute] = []
        while index < end {
            while index < end, Self.isSpace(buffer[index]) {
                index += 1
            }
            let nameStart = index
            while index < end, buffer[index] != UInt8(ascii: "="), !Self.isSpace(buffer[index]) {
                index += 1
            }
            let attributeName = Self.decode(buffer[nameStart ..< index])
            while index < end, Self.isSpace(buffer[index]) {
                index += 1
            }
            // A bare word with no value is not something XMLTV uses; skip it.
            guard index < end, buffer[index] == UInt8(ascii: "=") else { continue }
            index += 1
            while index < end, Self.isSpace(buffer[index]) {
                index += 1
            }
            guard index < end else { break }

            let valueStart: Int
            let valueEnd: Int
            let delimiter = buffer[index]
            if delimiter == UInt8(ascii: "\"") || delimiter == UInt8(ascii: "'") {
                valueStart = index + 1
                var close = valueStart
                while close < end, buffer[close] != delimiter {
                    close += 1
                }
                valueEnd = close
                index = min(close + 1, end)
            } else {
                valueStart = index
                while index < end, !Self.isSpace(buffer[index]) {
                    index += 1
                }
                valueEnd = index
            }
            if !attributeName.isEmpty {
                attributes.append(Attribute(name: attributeName, value: Self.decode(buffer[valueStart ..< valueEnd])))
            }
        }
        return (name, attributes)
    }

    // MARK: - Searching

    private enum Match { case matches, mismatch, partial }

    /// Whether the buffer at the cursor starts with `pattern`, or could once
    /// more bytes arrive.
    private func match(_ pattern: String) -> Match {
        let bytes = Array(pattern.utf8)
        for (offset, expected) in bytes.enumerated() {
            let index = cursor + offset
            if index >= buffer.count {
                return .partial
            }
            if buffer[index] != expected {
                return .mismatch
            }
        }
        return .matches
    }

    private func find(_ pattern: [UInt8], from start: Int) -> Int? {
        guard start + pattern.count <= buffer.count else { return nil }
        var index = start
        let last = buffer.count - pattern.count
        while index <= last {
            if buffer[index] == pattern[0], buffer[index ..< index + pattern.count].elementsEqual(pattern) {
                return index
            }
            index += 1
        }
        return nil
    }

    private mutating func skip(past pattern: [UInt8], from start: Int) -> Bool {
        guard let index = find(pattern, from: start) else { return false }
        cursor = index + pattern.count
        return true
    }

    private func trimmed(_ range: Range<Int>) -> ArraySlice<UInt8> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, Self.isSpace(buffer[lower]) {
            lower += 1
        }
        while upper > lower, Self.isSpace(buffer[upper - 1]) {
            upper -= 1
        }
        return buffer[lower ..< upper]
    }

    // MARK: - Decoding

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    /// Bytes to a string with XML entities resolved.
    private static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        guard bytes.contains(ampersand) else { return utf8String(bytes) }
        return utf8String(resolveEntities(bytes)[...])
    }

    /// UTF-8, falling back to Latin-1 for guides that are not valid UTF-8 (a
    /// declared `ISO-8859-1` encoding is common). Latin-1 maps every byte to
    /// a scalar, so this never fails and never drops text.
    static func utf8String(_ bytes: ArraySlice<UInt8>) -> String {
        // Nearly all guide text is ASCII, which is always valid UTF-8. Skipping
        // validation for it avoids the generic `String(validating:)` path, which
        // profiled at a fifth of the whole parse.
        if bytes.allSatisfy({ $0 < 0x80 }) {
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: bytes, as: UTF8.self)
        }
        if let text = String(validating: bytes, as: UTF8.self) {
            return text
        }
        return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    private static func resolveEntities(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = bytes.startIndex

        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte == ampersand,
                  let semicolon = bytes[index...].prefix(12).firstIndex(of: UInt8(ascii: ";")),
                  let replacement = entity(bytes[(index + 1) ..< semicolon])
            else {
                // Not a recognisable entity: keep the '&' literally.
                result.append(byte)
                index += 1
                continue
            }
            result.append(contentsOf: replacement)
            index = semicolon + 1
        }
        return result
    }

    private static func entity(_ name: ArraySlice<UInt8>) -> [UInt8]? {
        switch String(bytes: name, encoding: .ascii) {
        case "amp": return [UInt8(ascii: "&")]
        case "lt": return [UInt8(ascii: "<")]
        case "gt": return [UInt8(ascii: ">")]
        case "quot": return [UInt8(ascii: "\"")]
        case "apos": return [UInt8(ascii: "'")]
        case let text?:
            guard text.hasPrefix("#") else { return nil }
            let digits = text.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            return value.flatMap(Unicode.Scalar.init).map { Array(String($0).utf8) }
        case nil: return nil
        }
    }
}
