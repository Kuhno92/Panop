import Foundation

/// Reads the service's replies. The client reads what it fetches with this, and the app reads a cached reply with it,
/// so both go the same way and a cache can keep the bytes exactly as they came.
public enum SportsParsing {
    public static func fixtures(_ data: Data) throws -> [Fixture] {
        try decode(Envelope<Lossy<Fixture>>.self, data).data?.elements ?? []
    }

    public static func fixture(_ data: Data) throws -> Fixture {
        guard let reply = try? JSONDecoder().decode(FixtureReply.self, from: data), let fixture = reply.fixture else {
            throw SportsError.undecodable
        }
        return fixture
    }

    public static func events(_ data: Data) throws -> [MatchEvent] {
        try decode(Envelope<Lossy<MatchEvent>>.self, data).data?.elements ?? []
    }

    /// Nil when the service has no teams for the match, which is common below the big leagues.
    public static func lineups(_ data: Data) throws -> Lineup? {
        let envelope = try decode(Envelope<LineupData>.self, data)
        guard envelope.available != false, let teams = envelope.data else { return nil }
        return Lineup(home: teams.home, away: teams.away)
    }

    public static func stats(_ data: Data) throws -> MatchStats? {
        let envelope = try decode(Envelope<StatsData>.self, data)
        guard envelope.available != false, let teams = envelope.data else { return nil }
        return MatchStats(home: teams.home, away: teams.away)
    }

    public static func leagues(_ data: Data) throws -> [LeagueGroup] {
        try decode(Envelope<Lossy<LeagueGroup>>.self, data).data?.elements ?? []
    }

    /// Ordered by position.
    public static func standings(_ data: Data) throws -> [StandingRow] {
        try (decode(Envelope<Lossy<StandingRow>>.self, data).data?.elements ?? []).sorted { $0.position < $1.position }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws -> Value {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw SportsError.undecodable }
        return value
    }
}

private struct FixtureReply: Decodable {
    var fixture: Fixture?

    private enum Keys: String, CodingKey { case fixture }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        fixture = try? container.decodeIfPresent(Fixture.self, forKey: .fixture)
    }
}

private struct LineupData: Decodable {
    var home: TeamLineup
    var away: TeamLineup

    private enum Keys: String, CodingKey { case home, away }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        home = (try? container.decodeIfPresent(TeamLineup.self, forKey: .home)) ?? TeamLineup(starters: [])
        away = (try? container.decodeIfPresent(TeamLineup.self, forKey: .away)) ?? TeamLineup(starters: [])
    }
}

private struct StatsData: Decodable {
    var home: TeamStats
    var away: TeamStats

    private enum Keys: String, CodingKey { case home, away }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        home = try container.decode(TeamStats.self, forKey: .home)
        away = try container.decode(TeamStats.self, forKey: .away)
    }
}
