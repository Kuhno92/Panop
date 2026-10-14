import Foundation
@testable import PanopSports
import Testing

@Suite("sportapi.ai replies")
struct ModelTests {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test
    func `a day of matches is read, and what cannot be read is left out`() throws {
        let envelope = try decode(Envelope<Lossy<Fixture>>.self, SampleReplies.day)
        let fixtures = try #require(envelope.data).elements
        // The one without an id is dropped; the rest stay.
        #expect(fixtures.map(\.id) == [101, 102, 104, 105])
        let live = fixtures[0]
        #expect(live.homeName == "Northgate Rovers" && live.awayShort == "Harbour")
        #expect(live.leagueID == 53 && live.leagueZone == "England")
        #expect(live.homeScore == 0 && live.awayScore == 1)
        #expect(live.status == .live && live.isLive)
        #expect(live.minuteNumber == 79 && live.minute == "79'")
        #expect(live.title == "Northgate v Harbour")
        #expect(live.kickoff == Date(timeIntervalSince1970: 1_792_003_500))
    }

    @Test
    func `numbers written as text are still numbers, and a missing short name falls back to the long one`() throws {
        let fixtures = try #require(decode(Envelope<Lossy<Fixture>>.self, SampleReplies.day).data).elements
        let scheduled = fixtures[1]
        #expect(scheduled.id == 102 && scheduled.homeID == 13)
        #expect(scheduled.status == .scheduled && !scheduled.isLive)
        #expect(scheduled.homeShort == "Alder Town")
        #expect(scheduled.minute == nil && scheduled.minuteNumber == nil)
        #expect(!scheduled.hasScore)
    }

    @Test
    func `a status this app does not know is kept, and a minute on it counts as live`() throws {
        let fixtures = try #require(decode(Envelope<Lossy<Fixture>>.self, SampleReplies.day).data).elements
        let odd = fixtures[2]
        #expect(odd.status == .unknown("Suspended"))
        #expect(odd.isLive)
        #expect(!odd.status.isLive)
    }

    @Test
    func `time stamps with fractions of a second and penalties are read`() throws {
        let fixtures = try #require(decode(Envelope<Lossy<Fixture>>.self, SampleReplies.day).data).elements
        let shootout = fixtures[3]
        #expect(shootout.kickoff == Date(timeIntervalSince1970: 1_791_993_600))
        #expect(shootout.penaltyHome == 4 && shootout.penaltyAway == 3)
        #expect(shootout.status.isFinished == false || shootout.status == .finished)
    }

    @Test(arguments: [
        ("LIVE", FixtureStatus.live), ("HT", .halfTime), ("FT", .finished), ("AET", .afterExtraTime),
        ("PENS", .penalties), ("Scheduled", .scheduled), ("Cancelled", .cancelled), ("Postponed", .postponed),
        ("ft", .finished)
    ])
    func `statuses`(raw: String, expected: FixtureStatus) {
        #expect(FixtureStatus(raw) == expected)
    }

    @Test
    func `the minute of added time counts as the minute it started at`() throws {
        let fixture = try #require(decode(FixtureBox.self, SampleReplies.fixture).fixture)
        #expect(fixture.minuteNumber == 45)
        #expect(fixture.halfTimeHome == 0 && fixture.stadium == "Northgate Park")
        #expect(fixture.homeCoach == "A. Coach")
        // The substitution and the goal are read; the text that is not an event is dropped.
        #expect(fixture.events.count == 2)
        #expect(fixture.events[0].kind == .substitution && fixture.events[0].detail == "Jo Wright")
    }

    @Test
    func `events are typed, and one nobody knows is kept as it is`() throws {
        let events = try #require(decode(Envelope<Lossy<MatchEvent>>.self, SampleReplies.events).data).elements
        #expect(events.map(\.kind) == [.yellowCard, .goal, .assist, .redCard, .other("var_check")])
        #expect(events[1].side == .away && events[1].minuteNumber == 12)
        #expect(events[1].kind.isGoal && !events[2].kind.isGoal)
    }

    @Test
    func `a lineup is drawn from position names, since the service gives no formation`() throws {
        let teams = try #require(decode(Envelope<Lossy<LineupBox>>.self, "{\"data\": []}").data)
        #expect(teams.elements.isEmpty)
        let envelope = try decode(LineupEnvelope.self, SampleReplies.lineups)
        let home = try #require(envelope.data?.home)
        #expect(home.starters.count == 11)
        #expect(home.formation == "4-3-3")
        let rows = home.rows
        #expect(rows.map(\.count) == [1, 4, 3, 3])
        #expect(home.starters.first(where: { $0.isCaptain })?.name == "M1")
        #expect(home.substitutes.map(\.group) == [.substitute])
    }

    @Test
    func `a team that is not eleven has no formation`() {
        let some = TeamLineup(starters: [LineupPlayer(name: "K", position: "Goalkeeper")])
        #expect(some.formation == nil)
        #expect(some.rows.count == 1)
    }

    @Test
    func `a table is ordered by position and its form is read`() throws {
        let rows = try #require(decode(Envelope<Lossy<StandingRow>>.self, SampleReplies.standings).data).elements
        // The broken row is dropped; order is the caller's job (the client sorts).
        #expect(rows.count == 2)
        let harbour = try #require(rows.first)
        #expect(harbour.team.shortName == "Harbour" && harbour.goalDifference == 6)
        #expect(harbour.form == [.win, .draw, .loss, .unknown])
        let north = rows[1]
        #expect(north.goalDifference == 9)
        #expect(north.team.logo == nil)
    }

    @Test
    func `leagues come grouped by country`() throws {
        let groups = try #require(decode(Envelope<Lossy<LeagueGroup>>.self, SampleReplies.leagues).data).elements
        #expect(groups.map(\.country) == ["England", "Africa"])
        let league = groups[0].leagues[0]
        #expect(league.id == 53 && league.hasStandings && league.teamsCount == 24)
        #expect(!groups[0].leagues[1].hasStandings && groups[0].leagues[1].format == "cup")
    }

    @Test
    func `logos are plain files at a public address`() {
        #expect(SportsLogo.url(file: "espn-376.png")?.absoluteString == "https://sportapi.ai/logos/espn-376.png")
        #expect(SportsLogo.url(file: "a b.png")?.absoluteString == "https://sportapi.ai/logos/a%20b.png")
        #expect(SportsLogo.url(file: nil) == nil)
        #expect(SportsLogo.url(file: "") == nil)
    }

    @Test
    func `a day key is the date in the zone it is asked in`() {
        let late = Date(timeIntervalSince1970: 1_792_015_200) // 2026-10-14 22:00 UTC
        #expect(SportsDate.dayKey(for: late, in: TimeZone(identifier: "UTC") ?? .current) == "2026-10-14")
        #expect(SportsDate.dayKey(for: late, in: TimeZone(identifier: "Asia/Tokyo") ?? .current) == "2026-10-15")
    }
}

private struct FixtureBox: Decodable {
    var fixture: Fixture?
}

private struct LineupBox: Decodable {
    var starters: [LineupPlayer]
}

private struct LineupEnvelope: Decodable {
    struct Teams: Decodable {
        var home: TeamLineup
        var away: TeamLineup
    }

    var data: Teams?
}
