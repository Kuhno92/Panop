import Foundation

/// Reading titles, genres and cast lists the way providers write them.
public enum TitleText {
    /// A title without what a provider decorates it with: bracketed and parenthesised parts
    /// (`(2026)`, `(US)`, `[4K]`) and a short language tag in front (`DE - `, `DE-[4K] - `).
    ///
    ///     "DE - Backrooms (2026)"          -> "Backrooms"
    ///     "DE-[4K] - Lioness (2023) (US)"  -> "Lioness"
    public static func clean(_ name: String) -> String {
        var text = ""
        var depth = 0
        for character in name {
            if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth = Swift.max(0, depth - 1)
            } else if depth == 0 {
                text.append(character)
            }
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        // A language tag is a short first part before " - ": two or three letters and nothing else.
        if let range = trimmed.range(of: " - ") {
            let first = trimmed[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            if first.count <= 3, !first.isEmpty, first.allSatisfy(\.isLetter) {
                return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    /// What two entries of the same title share, so one can be told from a different version of the
    /// other: the cleaned, lower-cased name and the year.
    public static func sameTitleKey(name: String, year: Int?) -> String {
        "\(clean(name).lowercased())|\(year.map(String.init) ?? "")"
    }

    /// The part of a title shared by a film series: the cleaned name up to a colon or dash, without
    /// a trailing sequel number. `Toy Story 5` and `Toy Story` both give `toy story`; `Spider-Man:
    /// Brand New Day` gives `spider-man`. Nil when there is nothing distinctive to share.
    public static func stem(of name: String) -> String? {
        var text = clean(name)
        for separator in [":", " - "] {
            if let range = text.range(of: separator) {
                text = String(text[..<range.lowerBound])
            }
        }
        var words = text.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, isSequelMarker(last) {
            words.removeLast()
        }
        let stem = words.joined(separator: " ").lowercased().trimmingCharacters(in: .whitespaces)
        // Long enough to be distinctive, and not just a number ("2012" is a film, not a series).
        return stem.count >= 4 && stem.contains(where: \.isLetter) ? stem : nil
    }

    private static func isSequelMarker(_ word: String) -> Bool {
        if word.count <= 2, word.allSatisfy(\.isNumber) {
            return true
        }
        return ["ii", "iii", "iv", "vi", "vii", "viii", "ix"].contains(word.lowercased())
    }

    /// Genres from `Krimi / Drama`, `Action & Adventure, Drama`: split on slashes and commas, lower-cased.
    /// An ampersand is part of a genre's name ("Sci-Fi & Fantasy") and is kept.
    public static func genres(from text: String?, limit: Int = 6) -> Set<String> {
        names(from: text, separators: ["/", ","], limit: limit)
    }

    /// The leading cast from a comma-separated list, lower-cased.
    public static func people(from text: String?, limit: Int = 8) -> Set<String> {
        names(from: text, separators: [","], limit: limit)
    }

    private static func names(from text: String?, separators: Set<Character>, limit: Int) -> Set<String> {
        guard let text else { return [] }
        let parts = text.split { separators.contains($0) }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        return Set(parts.prefix(limit))
    }
}
