import Foundation

/// An episode's name, taken apart: which series, which season, which episode.
public struct ParsedEpisode: Equatable, Sendable {
    /// The series' name as written, tidied at the edges.
    public var series: String
    public var season: Int
    public var episode: Int
    /// What follows the numbers, if anything: the episode's own title.
    public var title: String?

    /// The series' name folded for comparing, so "Dark", "DARK" and "dark " are one series.
    public var seriesKey: String {
        series.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Reads series, season and episode out of a name such as `Dark S01E05`.
///
/// In an M3U file a `/series/` address is one *episode*, and a real file has hundreds of
/// thousands of them, so the Series screen needs them grouped under their shows. Providers write
/// the numbers a few ways and all of them are read here:
///
/// - `Dark S01E05`, `Dark - s1e5 - Title`, `Dark.S01.E05`, `Dark S01 E05`
/// - `Dark 1x05`
/// - `Dark Season 1 Episode 5`, `Dark - Season 01 - Ep 05`
///
/// One pass over the characters and no regular expression: this runs on every series entry of
/// every import, and a large playlist has more of them than a regex is cheap for.
public enum EpisodeTitle {
    /// nil when the name has no recognisable numbers, or nothing before them to call a series.
    public static func parse(_ name: String) -> ParsedEpisode? {
        let text = Array(name.unicodeScalars)
        var index = 0
        while index < text.count {
            if isBoundary(text, before: index),
               let match = seasonEpisodeCode(text, at: index)
               ?? crossForm(text, at: index)
               ?? wordForm(text, at: index)
            {
                let series = tidy(String(String.UnicodeScalarView(text[..<index])))
                guard !series.isEmpty else { return nil }
                let rest = tidy(String(String.UnicodeScalarView(text[match.end...])))
                return ParsedEpisode(
                    series: series,
                    season: match.season,
                    episode: match.episode,
                    title: rest.isEmpty ? nil : rest
                )
            }
            index += 1
        }
        return nil
    }

    // MARK: - The three forms

    private struct Match {
        var season: Int
        var episode: Int
        var end: Int
    }

    /// `S01E05`, with a separator or two allowed between the parts.
    private static func seasonEpisodeCode(_ text: [Unicode.Scalar], at start: Int) -> Match? {
        guard lower(text, start) == "s" else { return nil }
        guard let (season, afterSeason) = number(text, from: start + 1, maxDigits: 3) else { return nil }
        var index = skipSeparators(text, from: afterSeason, limit: 3)
        guard lower(text, index) == "e" else { return nil }
        index += 1
        guard let (episode, end) = number(text, from: index, maxDigits: 4), isBoundary(text, after: end) else {
            return nil
        }
        return Match(season: season, episode: episode, end: end)
    }

    /// `1x05`.
    private static func crossForm(_ text: [Unicode.Scalar], at start: Int) -> Match? {
        guard let (season, afterSeason) = number(text, from: start, maxDigits: 2),
              lower(text, afterSeason) == "x",
              let (episode, end) = number(text, from: afterSeason + 1, maxDigits: 3),
              end - (afterSeason + 1) >= 2,
              isBoundary(text, after: end)
        else { return nil }
        return Match(season: season, episode: episode, end: end)
    }

    /// `Season 1 Episode 5`, or `Ep 5`.
    private static func wordForm(_ text: [Unicode.Scalar], at start: Int) -> Match? {
        guard matches(text, "season", at: start) else { return nil }
        var index = skipSeparators(text, from: start + 6, limit: 3)
        guard let (season, afterSeason) = number(text, from: index, maxDigits: 3) else { return nil }
        index = skipSeparators(text, from: afterSeason, limit: 4)
        if matches(text, "episode", at: index) {
            index += 7
        } else if matches(text, "ep", at: index) {
            index += 2
        } else {
            return nil
        }
        index = skipSeparators(text, from: index, limit: 3)
        guard let (episode, end) = number(text, from: index, maxDigits: 4), isBoundary(text, after: end) else {
            return nil
        }
        return Match(season: season, episode: episode, end: end)
    }

    // MARK: - Scanning

    private static func lower(_ text: [Unicode.Scalar], _ index: Int) -> Unicode.Scalar? {
        guard index >= 0, index < text.count else { return nil }
        let scalar = text[index]
        if scalar.value >= 65, scalar.value <= 90 {
            return Unicode.Scalar(scalar.value + 32)
        }
        return scalar
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        isDigit(scalar) || scalar.properties.isAlphabetic
    }

    /// A number of up to `maxDigits` digits, and where it ends.
    private static func number(_ text: [Unicode.Scalar], from start: Int, maxDigits: Int) -> (Int, Int)? {
        var index = start
        var value = 0
        while index < text.count, isDigit(text[index]), index - start < maxDigits {
            value = value * 10 + Int(text[index].value - 48)
            index += 1
        }
        guard index > start else { return nil }
        return (value, index)
    }

    private static func skipSeparators(_ text: [Unicode.Scalar], from start: Int, limit: Int) -> Int {
        var index = start
        while index < text.count, index - start < limit, " ._-–".unicodeScalars.contains(text[index]) {
            index += 1
        }
        return index
    }

    private static func matches(_ text: [Unicode.Scalar], _ word: String, at start: Int) -> Bool {
        var index = start
        for expected in word.unicodeScalars {
            guard lower(text, index) == expected else { return false }
            index += 1
        }
        return true
    }

    /// Not in the middle of a word or a number: `Mars1x05` is not an episode, `Dark S01E05` is.
    private static func isBoundary(_ text: [Unicode.Scalar], before index: Int) -> Bool {
        index == 0 || !isAlphanumeric(text[index - 1])
    }

    private static func isBoundary(_ text: [Unicode.Scalar], after index: Int) -> Bool {
        index >= text.count || !isAlphanumeric(text[index])
    }

    /// Characters that only ever separate, wherever they sit at the edge of a name.
    private static let separators: Set<Unicode.Scalar> = Set(" \t\n-–—:|_,;\"'".unicodeScalars)

    /// Strips separators from both ends, but not what belongs to the name: a bracket that has
    /// its partner (`The Office (US)`), and a dot that ends an abbreviation (`S.H.I.E.L.D.`),
    /// where in `Dark.S01E05` the same dot is only a separator.
    private static func tidy(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)

        func isBalanced(_ open: Unicode.Scalar, _ close: Unicode.Scalar) -> Bool {
            scalars.contains(open) && scalars.contains(close)
        }

        var changed = true
        while changed, !scalars.isEmpty {
            changed = false
            if let last = scalars.last {
                let drop: Bool = if separators.contains(last) {
                    true
                } else if last == "." {
                    // "L.D." keeps its dot (a dot two characters back marks an abbreviation).
                    !(scalars.count >= 3 && scalars[scalars.count - 3] == ".")
                } else if last == ")" {
                    !isBalanced("(", ")")
                } else if last == "]" {
                    !isBalanced("[", "]")
                } else {
                    false
                }
                if drop {
                    scalars.removeLast()
                    changed = true
                }
            }
            if let first = scalars.first {
                let drop: Bool = if separators.contains(first) || first == "." {
                    true
                } else if first == "(" {
                    !isBalanced("(", ")")
                } else if first == "[" {
                    !isBalanced("[", "]")
                } else {
                    false
                }
                if drop {
                    scalars.removeFirst()
                    changed = true
                }
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
