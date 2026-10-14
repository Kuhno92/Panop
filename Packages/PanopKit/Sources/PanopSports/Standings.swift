import Foundation

/// A league as the picker lists it: from `/leagues`, which groups them by country.
public struct League: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: Int
    public var name: String
    /// `cup` for a knock-out competition, which has no table.
    public var format: String
    public var hasStandings: Bool
    public var hasFixtures: Bool
    public var fixturesCount: Int
    public var teamsCount: Int

    private enum Keys: String, CodingKey {
        case id, name, format
        case hasStandings = "has_standings", hasFixtures = "has_fixtures"
        case fixturesCount = "fixtures_count", teamsCount = "teams_count"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let id = container.int(.id) else {
            throw DecodingError.keyNotFound(Keys.id, .init(codingPath: [], debugDescription: "no id"))
        }
        self.id = id
        name = container.string(.name) ?? ""
        format = container.string(.format) ?? ""
        hasStandings = container.bool(.hasStandings) ?? false
        hasFixtures = container.bool(.hasFixtures) ?? true
        fixturesCount = container.int(.fixturesCount) ?? 0
        teamsCount = container.int(.teamsCount) ?? 0
    }

    public init(id: Int, name: String, format: String = "league", hasStandings: Bool = true) {
        self.id = id
        self.name = name
        self.format = format
        self.hasStandings = hasStandings
        hasFixtures = true
        fixturesCount = 0
        teamsCount = 0
    }
}

/// The leagues of one country, or of a region (the international competitions).
public struct LeagueGroup: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var country: String
    public var leagues: [League]

    public var id: String {
        country
    }

    private enum Keys: String, CodingKey { case country, leagues }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        country = container.string(.country) ?? ""
        leagues = container.list(League.self, .leagues)
    }

    public init(country: String, leagues: [League]) {
        self.country = country
        self.leagues = leagues
    }
}

public struct TeamRef: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var id: Int
    public var name: String
    public var shortName: String
    public var logo: String?

    private enum Keys: String, CodingKey {
        case id, name, logo
        case shortName = "short_name"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        guard let id = container.int(.id) else {
            throw DecodingError.keyNotFound(Keys.id, .init(codingPath: [], debugDescription: "no id"))
        }
        self.id = id
        name = container.string(.name) ?? ""
        shortName = container.string(.shortName).flatMap { $0.isEmpty ? nil : $0 } ?? name
        logo = container.string(.logo).flatMap { $0.isEmpty ? nil : $0 }
    }

    public init(id: Int, name: String, shortName: String? = nil, logo: String? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? name
        self.logo = logo
    }
}

public enum FormResult: String, Sendable, Equatable, Hashable {
    case win = "W", draw = "D", loss = "L", unknown
}

/// One result in a team's form, as the table lists it: the rest of the entry (the match) is not needed here.
private struct FormEntry: Decodable {
    var result: FormResult

    private enum Keys: String, CodingKey { case result }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        result = FormResult(rawValue: (container.string(.result) ?? "").uppercased()) ?? .unknown
    }
}

/// One line of a table.
public struct StandingRow: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public var position: Int
    public var team: TeamRef
    public var played: Int
    public var won: Int
    public var drawn: Int
    public var lost: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var goalDifference: Int
    public var points: Int
    /// The latest results, oldest first as the service lists them.
    public var form: [FormResult]

    public var id: Int {
        team.id
    }

    private enum Keys: String, CodingKey {
        case position, team, played, won, draw, lost, points, form
        case goalsFor = "goals_for", goalsAgainst = "goals_against", goalDifference = "goal_difference"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        team = try container.decode(TeamRef.self, forKey: .team)
        position = container.int(.position) ?? 0
        played = container.int(.played) ?? 0
        won = container.int(.won) ?? 0
        drawn = container.int(.draw) ?? 0
        lost = container.int(.lost) ?? 0
        goalsFor = container.int(.goalsFor) ?? 0
        goalsAgainst = container.int(.goalsAgainst) ?? 0
        goalDifference = container.int(.goalDifference) ?? goalsFor - goalsAgainst
        points = container.int(.points) ?? 0
        form = container.list(FormEntry.self, .form).map(\.result)
    }

    public init(
        position: Int, team: TeamRef, played: Int, won: Int, drawn: Int, lost: Int,
        goalsFor: Int, goalsAgainst: Int, points: Int, form: [FormResult] = []
    ) {
        self.position = position
        self.team = team
        self.played = played
        self.won = won
        self.drawn = drawn
        self.lost = lost
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        goalDifference = goalsFor - goalsAgainst
        self.points = points
        self.form = form
    }
}
