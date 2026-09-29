import Foundation

/// Splits a JSON document that is a top-level array into its elements without
/// ever holding the whole document.
///
/// `get_live_streams` on a large provider is tens of megabytes, and the
/// alternative (decode `[Stream]` in one call) needs the raw bytes, the decoded
/// array and the models resident at once. This tracks only string/escape/depth
/// state, so peak memory is one chunk plus one element.
///
/// It does not validate JSON. It finds element boundaries; each element's bytes
/// are then handed to a real decoder, which does the validating.
struct JSONArrayStreamer {
    enum Failure: Error, Equatable {
        /// The document is valid JSON that is not an array, such as an error
        /// object returned with a 200 status.
        case notAnArray
        case truncated
    }

    private enum Phase {
        case beforeArray
        case betweenElements
        case inElement
        case done
    }

    private var phase = Phase.beforeArray
    private var element: [UInt8] = []
    private var depth = 0
    private var inString = false
    private var escaped = false
    /// True once at least one byte of the current element was a non-space.
    private var elementStarted = false
    /// Letters seen where the array should start. A bare `null` or `false` is
    /// what some panels send for an empty category, and reads as no elements.
    private var wordProbe: [UInt8] = []

    /// Feeds a chunk and returns every element completed by it, as raw JSON.
    mutating func consume(_ chunk: Data) throws -> [Data] {
        var completed: [Data] = []
        for byte in chunk {
            switch phase {
            case .beforeArray:
                try startDocument(byte)
            case .betweenElements:
                try betweenElements(byte)
            case .inElement:
                if let finished = step(byte) {
                    completed.append(finished)
                }
            case .done:
                break
            }
        }
        return completed
    }

    /// Call after the last chunk. Throws if the array was cut off.
    mutating func finish() throws {
        switch phase {
        case .done:
            return
        case .beforeArray:
            // An empty body, `null` and `false` all mean "nothing here".
            if wordProbe.isEmpty {
                return
            }
            let word = String(bytes: wordProbe, encoding: .utf8)
            if word == "null" || word == "false" {
                return
            }
            throw Failure.notAnArray
        case .betweenElements, .inElement:
            throw Failure.truncated
        }
    }

    // MARK: - Phases

    private mutating func startDocument(_ byte: UInt8) throws {
        if Self.isSpace(byte) {
            return
        }
        if byte == UInt8(ascii: "[") {
            phase = .betweenElements
            return
        }
        // Bare words are judged in `finish()`. Anything else, an object most
        // likely, is an error response and fails immediately.
        guard (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte), wordProbe.count < 8 else {
            throw Failure.notAnArray
        }
        wordProbe.append(byte)
    }

    private mutating func betweenElements(_ byte: UInt8) throws {
        if Self.isSpace(byte) || byte == UInt8(ascii: ",") {
            return
        }
        if byte == UInt8(ascii: "]") {
            phase = .done
            return
        }
        phase = .inElement
        element.removeAll(keepingCapacity: true)
        depth = 0
        inString = false
        escaped = false
        elementStarted = false
        // The first byte of an element can never also end it: strings and
        // containers need a closer, and scalars end at the next separator.
        _ = step(byte)
    }

    /// Advances the element scanner by one byte. Returns the element when this
    /// byte ends it.
    private mutating func step(_ byte: UInt8) -> Data? {
        if inString {
            return stepInString(byte)
        }

        switch byte {
        case UInt8(ascii: "\""):
            inString = true
            elementStarted = true
            element.append(byte)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            depth += 1
            elementStarted = true
            element.append(byte)
        case UInt8(ascii: "}"), UInt8(ascii: "]"):
            return stepClosing(byte)
        case UInt8(ascii: ","):
            if depth == 0 {
                return closeElement()
            }
            element.append(byte)
        default:
            if !Self.isSpace(byte) {
                elementStarted = true
            }
            element.append(byte)
        }
        return nil
    }

    private mutating func stepInString(_ byte: UInt8) -> Data? {
        element.append(byte)
        if escaped {
            escaped = false
        } else if byte == UInt8(ascii: "\\") {
            escaped = true
        } else if byte == UInt8(ascii: "\"") {
            inString = false
            if depth == 0 {
                return closeElement()
            }
        }
        return nil
    }

    private mutating func stepClosing(_ byte: UInt8) -> Data? {
        if depth == 0 {
            // Only the array's own `]` can appear here in valid JSON, where it
            // ends a scalar element and the array with it.
            guard byte == UInt8(ascii: "]") else {
                element.append(byte)
                return nil
            }
            let finished = closeElement()
            phase = .done
            return finished
        }
        depth -= 1
        element.append(byte)
        return depth == 0 ? closeElement() : nil
    }

    private mutating func closeElement() -> Data? {
        defer {
            element.removeAll(keepingCapacity: true)
            if phase == .inElement {
                phase = .betweenElements
            }
        }
        guard elementStarted else { return nil }
        return Data(element)
    }

    // MARK: - Helpers

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }
}
