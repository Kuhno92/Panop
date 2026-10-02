import Foundation

/// What can be read from a title's own text and from its category's name, for the entries whose
/// provider does not say it outright.
public enum TitleMetadata {
    /// The release year in a title written like `Backrooms (2026)` or `Widow's Bay (2026) (US)`: the
    /// last parenthesised four-digit year, if it is a plausible one.
    public static func year(fromTitle title: String) -> Int? {
        var found: Int?
        var rest = Substring(title)
        while let open = rest.firstIndex(of: "(") {
            guard let close = rest[open...].firstIndex(of: ")") else { break }
            let inside = rest[rest.index(after: open) ..< close]
            if inside.count == 4, let year = Int(inside), plausible(year) {
                found = year
            }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    /// The year at the start of a date written `2026`, `2026-05-01` or `2026/05/01`.
    public static func year(fromDate date: String?) -> Int? {
        guard let date else { return nil }
        let digits = date.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        guard digits.count == 4, let year = Int(digits), plausible(year) else { return nil }
        return year
    }

    private static func plausible(_ year: Int) -> Bool {
        (1888 ... 2100).contains(year)
    }

    /// Whether a category is named as adult content: `VOD - ADULT +18`, `FOR ADULTS`, `XXX`.
    ///
    /// Only for sources that do not flag it themselves, and deliberately about the category's name
    /// rather than any title's. "Adult Swim" is cartoons and is not caught.
    public static func isAdultCategory(_ name: String?) -> Bool {
        guard let name else { return false }
        let text = name.lowercased()
        if text.contains("adult swim") {
            return false
        }
        if text.contains("+18") || text.contains("18+") || text.contains("xxx") || text.contains("for adults") {
            return true
        }
        // The word on its own, as "ADULT" or "ADULTS", but not inside another word.
        let words = text.split { !$0.isLetter }
        return words.contains("adult") || words.contains("adults") || words.contains("porn")
            || words.contains("erotic") || words.contains("erotik")
    }
}
