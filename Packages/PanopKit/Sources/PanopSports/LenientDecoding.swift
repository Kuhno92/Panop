import Foundation

/// The API is read leniently, the way the Simkl client reads its lists: a value that arrives as text instead of a
/// number, a field that is missing, or one odd element in a list costs that value, not the whole reply.
extension KeyedDecodingContainer {
    /// An integer however the API happened to write it: a number, or text holding one.
    func int(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key), number.isFinite {
            return Int(number)
        }
        return nil
    }

    /// Text, also when the API wrote a number where a name was expected.
    func string(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let number = try? decodeIfPresent(Int.self, forKey: key) {
            return String(number)
        }
        return nil
    }

    func bool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let number = try? decodeIfPresent(Int.self, forKey: key) {
            return number != 0
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "yes", "1"].contains(text.lowercased())
        }
        return nil
    }

    /// A list that drops what it cannot read; empty when it is missing or `null`.
    func list<Element: Decodable>(_ type: Element.Type, _ key: Key) -> [Element] {
        (try? decodeIfPresent(Lossy<Element>.self, forKey: key))?.elements ?? []
    }
}

/// A list whose unreadable elements are left out instead of failing the whole list.
struct Lossy<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                // A failed decode does not move on by itself: take the element out of the way.
                _ = try? container.decode(Skipped.self)
            }
        }
        elements = result
    }
}

private struct Skipped: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// `{"success": true, "data": ...}`, which most calls answer with. `data` is missing or `null` when there is none.
struct Envelope<Payload: Decodable>: Decodable {
    var success: Bool?
    var data: Payload?
    var available: Bool?

    private enum Keys: String, CodingKey { case success, data, available }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        success = container.bool(.success)
        available = container.bool(.available)
        data = try? container.decodeIfPresent(Payload.self, forKey: .data)
    }
}
