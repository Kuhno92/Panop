import Foundation

/// How sure a line of the guide is to be a match. Pure: it knows no database, only the words and the times.
enum MatchChannelScorer {
    /// What a programme can say that makes it not the live match: a look back, a preview, a talk about it.
    private static let notTheMatch: Set<String> = [
        "highlights", "highlight", "replay", "rewind", "relive", "zusammenfassung", "ruckblick", "vorbericht",
        "nachbericht", "vorschau", "preview", "review", "analysis", "analyse", "classic", "magazine", "magazin",
        "rueckblick", "recap", "archive", "archiv", "wiederholung", "repeat", "retro"
    ]

    private static let separators: Set<String> = ["vs", "v", "gegen", "contre", "contra", "x", "against", "e", "und"]

    /// Words of a provider's category for sport.
    static let sportWords: Set<String> = [
        "sport", "sports", "football", "fussball", "futbol", "calcio", "soccer", "foot", "fotbal", "voetbal",
        "deportes",
        "bein", "dazn", "eurosport", "espn", "sky"
    ]

    /// What a channel's name says about the league it shows.
    private static let broadcasterNames: [(league: [String], channels: [String])] = [
        (["bundesliga"], ["sky sport", "dazn", "sport1", "eurosport"]),
        (
            ["premier league"],
            [
                "sky sports",
                "tnt sports",
                "premier sports",
                "bt sport",
                "nbc",
                "peacock",
                "usa network",
                "espn",
                "supersport",
                "viaplay"
            ]
        ),
        (["la liga", "laliga"], ["laliga", "movistar", "dazn", "espn", "bein", "sky sport"]),
        (["serie a"], ["dazn", "sky sport", "cbs", "paramount", "bein", "sportitalia"]),
        (["ligue 1"], ["bein", "canal", "dazn", "prime"]),
        (
            ["champions league", "europa league", "conference league"],
            ["sky sport", "dazn", "tnt sports", "prime", "paramount", "cbs", "canal", "bein"]
        )
    ]

    /// The table above, read into words once.
    private static let broadcasters: [(league: [[String]], channels: [[String]])] = broadcasterNames.map {
        (league: $0.league.map(TeamNames.tokens), channels: $0.channels.map(TeamNames.tokens))
    }

    /// What is known of a channel without looking at a programme: read once per channel, not once per programme.
    struct ChannelFacts {
        let isSportGroup: Bool
        private let nameTokens: [String]
        let isFavourite: Bool

        init(_ channel: ChannelCandidate) {
            isSportGroup = TeamNames.tokens(channel.group ?? "").contains { MatchChannelScorer.sportWords.contains($0) }
            nameTokens = TeamNames.tokens(channel.name)
            isFavourite = channel.isFavourite
        }

        /// Whether the channel's name says it shows this match's league ("Sky Sport" for the Bundesliga).
        func showsLeague(of match: MatchSignature) -> Bool {
            for entry in MatchChannelScorer.broadcasters {
                let isLeague = entry.league.contains { hint in
                    match.league.phrases.contains(hint) || match.league.isNamed(in: hint)
                }
                guard isLeague else { continue }
                if entry.channels.contains(where: { TeamNames.range(of: $0, in: nameTokens) != nil }) {
                    return true
                }
            }
            return false
        }

        func bonus(for match: MatchSignature, remembered: Bool, showsLeague: Bool) -> Int {
            (isSportGroup ? 5 : 0) + (showsLeague ? 5 : 0) + (remembered ? 15 : 0) + (isFavourite ? 5 : 0)
        }
    }

    private enum Where {
        case headline, body, nowhere
    }

    /// What a programme says of the match, before anything about its channel: a score and why.
    struct Base: Equatable {
        var value: Int
        var reason: MatchScore.Reason
    }

    /// Nil when the programme is not on at the time of the match, or names neither team. This is run for every line of
    /// the guide, so it does no more than the words need.
    static func base(_ match: MatchSignature, programme: PreparedProgramme) -> Base? {
        guard overlap(of: programme.snippet, with: match.window) >= 5 * 60 else { return nil }

        let home = place(match.home, in: programme)
        let away = place(match.away, in: programme)
        var value: Int
        let reason: MatchScore.Reason
        switch (home, away) {
        case (.nowhere, .nowhere):
            return nil
        case (.headline, .headline):
            value = 80
            reason = .bothTeamsInTitle
            if isSeparated(match, in: programme.headline) {
                value += 10
            }
        case (.headline, .body), (.body, .headline), (.body, .body):
            value = 60
            reason = .bothTeamsInText
        default:
            // One team only.
            let leagueNamed = match.league.isNamed(in: programme.headline) || match.league.isNamed(in: programme.body)
            value = leagueNamed ? 55 : 35
            reason = leagueNamed ? .teamAndLeague : .oneTeam
        }
        let lead = abs(programme.snippet.start.timeIntervalSince(match.kickoff))
        value += lead <= 15 * 60 ? 10 : (lead <= 45 * 60 ? 5 : 0)
        if !notTheMatch.isDisjoint(with: programme.headline) {
            value -= 40
        }
        return Base(value: value, reason: reason)
    }

    /// The score of a programme once its channel is known.
    static func finish(_ base: Base, bonus: Int) -> MatchScore {
        // A programme that names one team can be another match of it, so it is never "watch" on its own: it is what
        // the person is shown to confirm.
        let ceiling = switch base.reason {
        case .bothTeamsInTitle, .bothTeamsInText: 100
        case .teamAndLeague: 69
        case .oneTeam, .genericSport: 49
        }
        return MatchScore(value: max(0, min(ceiling, base.value + bonus)), reason: base.reason)
    }

    /// Whether a programme at the time is sport that names no team: a channel to choose among, never one to start
    /// without asking.
    static func isGeneric(_ match: MatchSignature, programme: PreparedProgramme) -> Bool {
        overlap(of: programme.snippet, with: match.window) >= 20 * 60
            && notTheMatch.isDisjoint(with: programme.headline)
            && isSport(programme)
    }

    // MARK: - Pieces

    private static func place(_ team: TeamKey, in programme: PreparedProgramme) -> Where {
        if team.isNamed(in: programme.headline) {
            return .headline
        }
        return team.isNamed(in: programme.body) ? .body : .nowhere
    }

    private static func overlap(of snippet: ProgrammeSnippet, with window: Range<Date>) -> TimeInterval {
        max(0, min(snippet.stop, window.upperBound).timeIntervalSince(max(snippet.start, window.lowerBound)))
    }

    /// "Home v Away": the two names with nothing between them but a word for "against".
    private static func isSeparated(_ match: MatchSignature, in tokens: [String]) -> Bool {
        guard let home = match.home.range(in: tokens), let away = match.away.range(in: tokens) else { return false }
        let (first, second) = home.lowerBound < away.lowerBound ? (home, away) : (away, home)
        guard first.upperBound <= second.lowerBound else { return false }
        let between = tokens[first.upperBound ..< second.lowerBound]
        return between.count <= 2 && between.contains { separators.contains($0) }
    }

    private static func isSport(_ programme: PreparedProgramme) -> Bool {
        if !programme.categories.isDisjoint(with: sportWords) {
            return true
        }
        let live = programme.headline.contains { liveWords.contains($0) }
        let sport = programme.headline.contains { titleSportWords.contains($0) }
        return live && sport
    }

    private static let liveWords: Set<String> = ["live", "ubertragung", "direct", "directo", "diretta", "vivo"]
    private static let titleSportWords = sportWords.subtracting(["bein", "dazn", "espn", "sky", "eurosport"])
}
