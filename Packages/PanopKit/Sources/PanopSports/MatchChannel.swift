import Foundation

/// A match as the guide is searched for it.
public struct MatchSignature: Sendable, Equatable {
    public var home: TeamKey
    public var away: TeamKey
    public var league: LeagueKey
    public var kickoff: Date

    public init(home: TeamKey, away: TeamKey, league: LeagueKey, kickoff: Date) {
        self.home = home
        self.away = away
        self.league = league
        self.kickoff = kickoff
    }

    /// Nil for a match with no kick-off time, which cannot be placed in the guide.
    public init?(_ fixture: Fixture) {
        guard let kickoff = fixture.kickoff else { return nil }
        self.init(
            home: TeamKey(name: fixture.homeName, short: fixture.homeShort),
            away: TeamKey(name: fixture.awayName, short: fixture.awayShort),
            league: LeagueKey(name: fixture.leagueName),
            kickoff: kickoff
        )
    }

    /// From when a programme can be this match to when it surely is over: the pre-show, the match, extra time.
    var window: Range<Date> {
        kickoff.addingTimeInterval(-20 * 60) ..< kickoff.addingTimeInterval(150 * 60)
    }
}

/// A channel of the person's own playlist, as far as matching needs to know it. What the app knows beyond that stays
/// in the app: this is only what a score is made of.
public struct ChannelCandidate: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// The provider's category for it, such as "DE | SPORTS".
    public var group: String?
    /// Higher is better: UHD above FHD above HD above SD.
    public var qualityRank: Int
    public var isFavourite: Bool

    public init(id: String, name: String, group: String? = nil, qualityRank: Int = 0, isFavourite: Bool = false) {
        self.id = id
        self.name = name
        self.group = group
        self.qualityRank = qualityRank
        self.isFavourite = isFavourite
    }
}

/// A line of the guide.
public struct ProgrammeSnippet: Sendable, Equatable, Hashable {
    public var channelID: String
    public var start: Date
    public var stop: Date
    public var title: String
    public var subtitle: String?
    public var details: String?
    public var categories: [String]

    public init(
        channelID: String, start: Date, stop: Date, title: String,
        subtitle: String? = nil, details: String? = nil, categories: [String] = []
    ) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.categories = categories
    }
}

/// A line of the guide with its words read out once. The guide is long and the same line is looked at for every
/// match of the day, so the app keeps these.
public struct PreparedProgramme: Sendable, Equatable {
    public var snippet: ProgrammeSnippet
    /// Title and subtitle, which is where a guide says what is on.
    let headline: [String]
    /// The description. Only its start is read: the rest of a long text says little more.
    let body: [String]
    let categories: Set<String>

    public init(_ snippet: ProgrammeSnippet) {
        self.snippet = snippet
        headline = TeamNames.tokens(snippet.title) + ["|"] + TeamNames.tokens(snippet.subtitle ?? "")
        body = TeamNames.tokens(String((snippet.details ?? "").prefix(400)))
        categories = Set(snippet.categories.flatMap(TeamNames.tokens))
    }
}

public struct MatchScore: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case bothTeamsInTitle, bothTeamsInText, teamAndLeague, oneTeam
        /// A sport programme at the time, which names no one.
        case genericSport
    }

    /// How sure it is that this programme is the match: 0 to 100.
    public var value: Int
    public var reason: Reason

    public enum Tier: Int, Sendable, Comparable {
        case hidden, possible, likely, watch

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// "Watch" is for a programme that says both teams, "likely" for one that nearly does, "possible" for what the
    /// person has to choose among.
    public var tier: Tier {
        switch value {
        case 70...: .watch
        case 50 ..< 70: .likely
        case 30 ..< 50: .possible
        default: .hidden
        }
    }
}

/// A channel that is showing a match, or may be.
public struct MatchLink: Sendable, Equatable, Identifiable {
    public var channel: ChannelCandidate
    public var programme: ProgrammeSnippet
    public var score: MatchScore

    public var id: String {
        channel.id
    }

    public init(channel: ChannelCandidate, programme: ProgrammeSnippet, score: MatchScore) {
        self.channel = channel
        self.programme = programme
        self.score = score
    }
}
