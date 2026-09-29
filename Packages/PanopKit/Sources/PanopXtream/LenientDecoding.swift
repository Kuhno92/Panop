import Foundation

/// Xtream panels are wildly inconsistent about JSON types. The same field
/// arrives as `"12"`, `12`, `12.0` or `null` depending on the panel and its
/// version, and an "empty object" is often `[]`. These helpers accept every
/// shape seen in the wild, and return `nil` rather than throw, so one odd field
/// costs one value instead of a whole row.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value.isEmpty ? nil : value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
                ?? Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? Int($0) : nil }
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Accepts `1`, `0`, `"1"`, `"0"`, `true`, `false`.
    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        return lenientInt(key).map { $0 != 0 }
    }

    /// Unix timestamps arrive as strings or numbers; `0` and negatives mean
    /// "unknown" on every panel seen, so they read as `nil`.
    func lenientDate(_ key: Key) -> Date? {
        guard let seconds = lenientInt(key), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// A list that some panels send as a bare string, or as `[]`/`null`.
    func lenientStrings(_ key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.filter { !$0.isEmpty }
        }
        if let value = lenientString(key) {
            return [value]
        }
        return []
    }
}
