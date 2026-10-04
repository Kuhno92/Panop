import Foundation

/// What kind of programme something is, in a handful of kinds, so a guide can colour it.
///
/// A guide writes its categories in its own words and language ("News", "Nachrichten", "Spielfilm",
/// "Talk-Show"), and some write none. So the kind is read from those words, and failing that from the
/// title, and anything it cannot place is `other`, which is drawn plainly rather than guessed at.
nonisolated enum ProgrammeCategory: String, CaseIterable, Sendable {
    case news, sport, film, series, kids, documentary, music, entertainment, other

    /// Words that mark each kind, lower-case, matched anywhere in a category or in a title. Ordered by how
    /// specific they are: a "sport documentary" is sport, a "kids film" is for kids.
    private static let words: [(ProgrammeCategory, [String])] = [
        (.kids, ["kids", "children", "kinder", "cartoon", "animation", "zeichentrick", "junior", "jugend"]),
        (.sport, ["sport", "fußball", "fussball", "football", "soccer", "bundesliga", "formel 1", "formula 1",
                  "tennis", "basketball", "handball", "olympi", "nfl", "nba"]),
        (.news, ["news", "nachrichten", "weather", "wetter", "current affairs", "politik", "politics", "aktuell"]),
        (.documentary, ["documentary", "dokumentation", "doku", "reportage", "wissen", "science",
                        "nature", "natur", "history", "geschichte", "factual", "magazin", "magazine"]),
        (.music, ["music", "musik", "concert", "konzert", "oper", "opera", "musical", "charts"]),
        (.film, ["movie", "film", "spielfilm", "kino", "cinema", "thriller", "western", "fernsehfilm", "tv movie"]),
        (.series, ["series", "serie", "soap", "krimi", "crime", "drama", "sitcom", "episode", "telenovela", "staffel"]),
        (.entertainment, ["entertainment", "unterhaltung", "show", "comedy", "talk", "quiz", "game", "spiel",
                          "reality", "casting", "variety", "satire"])
    ]

    /// Words in a title that mean one thing whatever the guide says: a news bulletin or a big competition.
    /// Few and unambiguous on purpose, since a title is a poor witness ("Game of Thrones" is not a quiz).
    private static let titleWords: [(ProgrammeCategory, [String])] = [
        (.news, ["tagesschau", "tagesthemen", "heute journal", "nachrichten", "newsroom", "news"]),
        (.sport, ["bundesliga", "champions league", "formel 1", "formula 1", "länderspiel", "sportschau"])
    ]

    static func classify(categories: [String], title: String = "") -> ProgrammeCategory {
        // What the guide says wins over a guess from the title.
        let said = categories.joined(separator: " ").lowercased()
        if !said.isEmpty {
            for (kind, words) in Self.words where words.contains(where: { said.contains($0) }) {
                return kind
            }
        }
        let named = title.lowercased()
        for (kind, words) in Self.titleWords where words.contains(where: { named.contains($0) }) {
            return kind
        }
        return .other
    }
}
