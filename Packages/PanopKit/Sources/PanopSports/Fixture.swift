import Foundation

public enum FixtureStatus: Sendable, Equatable, Hashable {
    case scheduled, live, halfTime, finished, afterExtraTime, penalties, cancelled, postponed
    /// Anything the service writes that this app does not know. It is kept, not an error.
    case unknown(String)

    public init(_ raw: String) {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "scheduled", "ns", "tbd": self = .scheduled
        case "live", "1h", "2h", "et": self = .live
        case "ht": self = .halfTime
        case "ft": self = .finished
        case "aet": self = .afterExtraTime
        case "pens", "pen": self = .penalties
        case "cancelled", "canceled": self = .cancelled
        case "postponed", "ppd": self = .postponed
        default: self = .unknown(raw)
        }
    }

    public var isLive: Bool {
        self == .live || self == .halfTime
    }

    public var isFinished: Bool {
        self == .finished || self == .afterExtraTime || self == .penalties
    }
}

/// One match, as the day lists and the match call give it.
public struct Fixture: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: Int
    public var leagueID: Int?
    public var leagueName: String
    /// The country or region of the league, such as "England".
    public var leagueZone: String
    /// The round or phase: "League Stage", "Semi-finals". Empty for a plain league match.
    public var stage: String
    /// The kick-off in UTC. The one time to trust: the service's own `datetime` is in Central European time.
    public var kickoff: Date?
    public var status: FixtureStatus
    /// As the service writes it while the match is played: `"79'"`, or `"45+2'"`.
    public var minute: String?
    public var homeID: Int?
    public var awayID: Int?
    public var homeName: String
    public var awayName: String
    public var homeShort: String
    public var awayShort: String
    /// A file name, see ``SportsLogo``.
    public var homeLogo: String?
    public var awayLogo: String?
    public var homeScore: Int?
    public var awayScore: Int?
    public var penaltyHome: Int?
    public var penaltyAway: Int?
    /// Only in the answer of the single-match call.
    public var halfTimeHome: Int?
    public var halfTimeAway: Int?
    public var stadium: String?
    public var homeCoach: String?
    public var awayCoach: String?
    public var events: [MatchEvent]

    private enum Keys: String, CodingKey {
        case id, stage, status, minute, events, winner
        case leagueID = "league_id", leagueName = "league_name", leagueZone = "league_zone"
        case kickoff = "kickoff_utc"
        case homeID = "home_id", awayID = "away_id"
        case homeName = "home_team", awayName = "away_team", homeShort = "home_short", awayShort = "away_short"
        case homeLogo = "home_logo", awayLogo = "away_logo"
        case homeScore = "home_score", awayScore = "away_score"
        case penaltyHome = "penalty_home", penaltyAway = "penalty_away"
        case halfTimeHome = "ht_home", halfTimeAway = "ht_away"
        case stadium = "home_stadium", homeCoach = "home_coach", awayCoach = "away_coach"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        // Without an id a match cannot be told apart or asked about: that element is dropped.
        guard let id = container.int(.id) else {
            throw DecodingError.keyNotFound(Keys.id, .init(codingPath: [], debugDescription: "no id"))
        }
        self.id = id
        leagueID = container.int(.leagueID)
        leagueName = container.string(.leagueName) ?? ""
        leagueZone = container.string(.leagueZone) ?? ""
        stage = container.string(.stage) ?? ""
        kickoff = container.string(.kickoff).flatMap(SportsDate.parse)
        status = FixtureStatus(container.string(.status) ?? "")
        minute = container.string(.minute).flatMap { $0.isEmpty ? nil : $0 }
        homeID = container.int(.homeID)
        awayID = container.int(.awayID)
        homeName = container.string(.homeName) ?? ""
        awayName = container.string(.awayName) ?? ""
        homeShort = container.string(.homeShort).flatMap { $0.isEmpty ? nil : $0 } ?? homeName
        awayShort = container.string(.awayShort).flatMap { $0.isEmpty ? nil : $0 } ?? awayName
        homeLogo = container.string(.homeLogo).flatMap { $0.isEmpty ? nil : $0 }
        awayLogo = container.string(.awayLogo).flatMap { $0.isEmpty ? nil : $0 }
        homeScore = container.int(.homeScore)
        awayScore = container.int(.awayScore)
        penaltyHome = container.int(.penaltyHome)
        penaltyAway = container.int(.penaltyAway)
        halfTimeHome = container.int(.halfTimeHome)
        halfTimeAway = container.int(.halfTimeAway)
        stadium = container.string(.stadium).flatMap { $0.isEmpty ? nil : $0 }
        homeCoach = container.string(.homeCoach).flatMap { $0.isEmpty ? nil : $0 }
        awayCoach = container.string(.awayCoach).flatMap { $0.isEmpty ? nil : $0 }
        events = container.list(MatchEvent.self, .events)
    }

    /// Whether it is being played. A status this app does not know, with a minute on it, counts: better a live
    /// badge too many than a goal missed.
    public var isLive: Bool {
        if status.isLive {
            return true
        }
        if case .unknown = status {
            return minute != nil
        }
        return false
    }

    /// The minute as a number (`"79'"` is 79, `"45+2'"` is 45), for ordering and for a progress bar.
    public var minuteNumber: Int? {
        guard let minute else { return nil }
        let digits = minute.prefix { $0.isNumber }
        return Int(digits)
    }

    public var hasScore: Bool {
        homeScore != nil && awayScore != nil
    }

    /// Both team names, with what a person says: "Norwich v Southampton".
    public var title: String {
        "\(homeShort) v \(awayShort)"
    }
}

public enum EventKind: Sendable, Equatable, Hashable {
    case goal, ownGoal, penaltyGoal, assist, yellowCard, redCard, substitution
    case other(String)

    public init(_ raw: String) {
        switch raw.lowercased() {
        case "goal": self = .goal
        case "own_goal", "owngoal": self = .ownGoal
        case "penalty", "penalty_goal", "pen_goal": self = .penaltyGoal
        case "assist": self = .assist
        case "yellow_card", "yellowcard": self = .yellowCard
        case "red_card", "redcard", "yellow_red_card", "second_yellow": self = .redCard
        case "substitution", "sub": self = .substitution
        default: self = .other(raw)
        }
    }

    /// Whether it changes the score.
    public var isGoal: Bool {
        self == .goal || self == .ownGoal || self == .penaltyGoal
    }
}

public enum TeamSide: String, Sendable, Equatable, Hashable {
    case home, away
}

public struct MatchEvent: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: Int
    public var kind: EventKind
    public var side: TeamSide?
    public var player: String
    public var minute: String
    /// For a substitution, the player who came on.
    public var detail: String?

    private enum Keys: String, CodingKey {
        case id, minute
        case kind = "event_type", side = "team_side", player = "player_name", detail = "extra_info"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        kind = EventKind(container.string(.kind) ?? "")
        side = container.string(.side).flatMap { TeamSide(rawValue: $0.lowercased()) }
        player = container.string(.player) ?? ""
        minute = container.string(.minute) ?? ""
        detail = container.string(.detail).flatMap { $0.isEmpty ? nil : $0 }
        // An event without an id is still an event: it gets a stable one from what it says.
        id = container.int(.id) ?? "\(minute)|\(player)|\(kind)".hashValue
    }

    public var minuteNumber: Int {
        Int(minute.prefix { $0.isNumber }) ?? 0
    }
}
