import Foundation

/// Reading names out of guide text. A guide says "FC Bayern München - Borussia Dortmund", "Bayern Munich v BVB" or
/// "Bayern gegen Dortmund" for one match; this turns each into the same words, so a team can be found in any of them.
public enum TeamNames {
    /// Words that only dress a club's name. They are left out of what a team is looked for by, not out of the text
    /// it is looked for in.
    static let noise: Set<String> = [
        "fc", "cf", "sc", "ac", "afc", "sv", "vfb", "vfl", "tsv", "ssc", "fk", "sk", "bk", "if", "cd", "ud", "rc", "as",
        "us", "ss", "club", "calcio", "de", "the", "ev", "fsv", "tsg", "rb", "cfc", "bsc"
    ]

    /// Words that name no one club: "United" alone would find half the league. A team is never looked for by one of
    /// these on its own, unless the alias table says so.
    static let ambiguous: Set<String> = [
        "united", "city", "town", "real", "inter", "athletic", "sporting", "dynamo", "olympic", "rangers", "rovers",
        "county", "wanderers", "albion", "borough", "north", "south", "west", "east", "st", "new", "madrid", "london",
        "milan", "munchen", "munich", "manchester", "sheffield", "glasgow", "birmingham", "borussia", "atletico",
        "racing", "deportivo", "olympique", "saint", "athletico", "hotspur", "forest", "palace", "park"
    ]

    /// The words of a text: lower case, without accents, and with the ways a guide writes "against" made the one
    /// word `vs`. "Ä", "Ö" and "Ü" are written "AE", "OE" and "UE" by some guides and not by others, so both end up
    /// the same.
    public static func tokens(_ text: String) -> [String] {
        var text = text.lowercased()
        for separator in [" - ", " – ", " — ", " : ", " / ", " | "] {
            text = text.replacingOccurrences(of: separator, with: " vs ")
        }
        for (letter, plain) in [("ß", "ss"), ("ø", "o"), ("æ", "ae"), ("œ", "oe"), ("ł", "l"), ("đ", "d"), (
            "þ",
            "th"
        )] {
            text = text.replacingOccurrences(of: letter, with: plain)
        }
        text = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        for (pair, plain) in [("ae", "a"), ("oe", "o"), ("ue", "u")] {
            text = text.replacingOccurrences(of: pair, with: plain)
        }
        return text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The words that identify a name: no dressing, no numbers ("1.", "04", "1899").
    public static func core(_ text: String) -> [String] {
        tokens(text).filter { !noise.contains($0) && $0.contains(where: \.isLetter) }
    }

    /// Whether one word is enough to look a team up by.
    static func isDistinctive(_ token: String) -> Bool {
        token.count >= 4 && !ambiguous.contains(token)
    }

    /// Where `phrase` appears in `tokens` as a run of words, or nil.
    static func range(of phrase: [String], in tokens: [String]) -> Range<Int>? {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return nil }
        for start in 0 ... (tokens.count - phrase.count) where tokens[start] == phrase[0] {
            if Array(tokens[start ..< start + phrase.count]) == phrase {
                return start ..< start + phrase.count
            }
        }
        return nil
    }
}

/// A team as it is looked for in a text: every run of words that stands for it.
public struct TeamKey: Sendable, Equatable, Hashable {
    public let phrases: [[String]]

    /// - Parameters:
    ///   - name: the team's name as the sports service gives it.
    ///   - short: its short name, when there is one.
    public init(name: String, short: String? = nil) {
        var found: [[String]] = []
        var cores: [[String]] = []
        for text in [name, short].compactMap(\.self) {
            let core = TeamNames.core(text)
            guard !core.isEmpty else { continue }
            cores.append(core)
            if core.count >= 2 || TeamNames.isDistinctive(core[0]), !found.contains(core) {
                found.append(core)
            }
        }
        // What the alias table knows of it is trusted as it is written, even a word like "Inter" that names no one.
        for alias in TeamAliases.phrases(forCores: cores) where !found.contains(alias) {
            found.append(alias)
        }
        phrases = found
    }

    /// Where the team is named in `tokens`, or nil.
    public func range(in tokens: [String]) -> Range<Int>? {
        for phrase in phrases {
            if let range = TeamNames.range(of: phrase, in: tokens) {
                return range
            }
        }
        return nil
    }

    public func isNamed(in tokens: [String]) -> Bool {
        range(in: tokens) != nil
    }
}

/// A league or cup as it is looked for in a text.
public struct LeagueKey: Sendable, Equatable, Hashable {
    public let phrases: [[String]]

    private static let tooGeneric: Set<String> = [
        "championship",
        "league",
        "cup",
        "division",
        "premier",
        "first",
        "second"
    ]

    public init(name: String) {
        let tokens = TeamNames.tokens(name)
        var found: [[String]] = []
        let core = TeamNames.core(name)
        if core.count >= 2 || (core.count == 1 && !Self.tooGeneric.contains(core[0]) && core[0].count >= 4) {
            found.append(core)
        }
        for alias in TeamAliases.leaguePhrases(containedIn: tokens) where !found.contains(alias) {
            found.append(alias)
        }
        phrases = found
    }

    public func isNamed(in tokens: [String]) -> Bool {
        phrases.contains { TeamNames.range(of: $0, in: tokens) != nil }
    }
}
