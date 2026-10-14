import Foundation
@testable import PanopSports
import Testing

@Suite("what the hub shows")
struct HubLayoutTests {
    /// Saturday 2026-10-17 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_245_600)

    private func fixture(
        _ id: Int, league: Int, _ name: String = "League", home: Int, away: Int,
        minutes: Int, status: String = "Scheduled", minute: String? = nil
    ) throws -> Fixture {
        var json: [String: Any] = [
            "id": id, "league_id": league, "league_name": name, "league_zone": "Zone", "home_id": home, "away_id": away,
            "home_team": "Home \(home)", "away_team": "Away \(away)", "status": status,
            "kickoff_utc": ISO8601DateFormatter().string(from: now.addingTimeInterval(TimeInterval(minutes * 60)))
        ]
        if let minute {
            json["minute"] = minute
        }
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test
    func `only the leagues and teams the person follows are shown`() throws {
        let fixtures = try [
            fixture(1, league: 10, "A", home: 1, away: 2, minutes: 60),
            fixture(2, league: 20, "B", home: 3, away: 4, minutes: 60),
            fixture(3, league: 30, "C", home: 5, away: 6, minutes: 60),
            fixture(4, league: 30, "C", home: 7, away: 8, minutes: 90)
        ]
        let layout = HubLayout.make(fixtures: fixtures, leagues: [10, 20], teams: [5], now: now)
        // League 30 is not followed, but a team of it is: that match comes with it, the other of that league does not.
        #expect(Set(layout.sections.flatMap(\.fixtures).map(\.id)) == [1, 2, 3])
        #expect(layout.mine.map(\.id) == [3])
    }

    @Test
    func `nothing is shown for nothing followed`() throws {
        let layout = try HubLayout.make(
            fixtures: [fixture(1, league: 10, home: 1, away: 2, minutes: 60)], leagues: [], teams: [], now: now
        )
        #expect(layout == .empty)
    }

    @Test
    func `leagues with a match on come first, then in the order the person chose them`() throws {
        let fixtures = try [
            fixture(1, league: 10, "First", home: 1, away: 2, minutes: 60),
            fixture(2, league: 20, "Second", home: 3, away: 4, minutes: 60),
            fixture(3, league: 30, "Third", home: 5, away: 6, minutes: -30, status: "LIVE", minute: "30'")
        ]
        let layout = HubLayout.make(fixtures: fixtures, leagues: [10, 20, 30], teams: [], now: now)
        #expect(layout.sections.map(\.name) == ["Third", "First", "Second"])
        #expect(layout.sections.first?.liveCount == 1)
    }

    @Test
    func `in a league, what is on comes first, then what is coming, then what is over`() throws {
        let fixtures = try [
            fixture(1, league: 10, home: 1, away: 2, minutes: -240, status: "FT"),
            fixture(2, league: 10, home: 3, away: 4, minutes: 120),
            fixture(3, league: 10, home: 5, away: 6, minutes: -30, status: "LIVE", minute: "30'"),
            fixture(4, league: 10, home: 7, away: 8, minutes: 30),
            fixture(5, league: 10, home: 9, away: 10, minutes: 10, status: "Postponed")
        ]
        let layout = HubLayout.make(fixtures: fixtures, leagues: [10], teams: [], now: now)
        #expect(layout.sections.first?.fixtures.map(\.id) == [3, 5, 4, 2, 1].filter { $0 != 5 } + [5])
    }

    @Test
    func `the hero is the followed team's match that is on, else its next, else the biggest on`() throws {
        let live = try fixture(1, league: 10, home: 1, away: 2, minutes: -30, status: "LIVE", minute: "30'")
        let mineLive = try fixture(2, league: 10, home: 7, away: 8, minutes: -20, status: "LIVE", minute: "20'")
        let mineNext = try fixture(3, league: 10, home: 7, away: 9, minutes: 200)
        let other = try fixture(4, league: 10, home: 3, away: 4, minutes: 30)
        #expect(HubLayout.make(fixtures: [live, mineLive, mineNext, other], leagues: [10], teams: [7], now: now).hero?
            .id == 2)
        #expect(HubLayout.make(fixtures: [live, mineNext, other], leagues: [10], teams: [7], now: now).hero?.id == 3)
        #expect(HubLayout.make(fixtures: [live, other], leagues: [10], teams: [7], now: now).hero?.id == 1)
        #expect(HubLayout.make(fixtures: [other], leagues: [10], teams: [], now: now).hero?.id == 4)
    }

    @Test
    func `a day that is over has the latest result of a followed team as its hero`() throws {
        let early = try fixture(1, league: 10, home: 7, away: 8, minutes: -600, status: "FT")
        let late = try fixture(2, league: 10, home: 7, away: 9, minutes: -300, status: "FT")
        let layout = HubLayout.make(fixtures: [early, late], leagues: [10], teams: [7], now: now)
        #expect(layout.hero?.id == 2)
    }

    @Test
    func `the scoreboard has what is on, then what finished lately`() throws {
        let fixtures = try [
            fixture(1, league: 10, home: 1, away: 2, minutes: -150, status: "FT"),
            fixture(2, league: 10, home: 3, away: 4, minutes: -30, status: "LIVE", minute: "30'"),
            fixture(3, league: 10, home: 5, away: 6, minutes: -700, status: "FT"),
            fixture(4, league: 10, home: 7, away: 8, minutes: 100)
        ]
        let layout = HubLayout.make(fixtures: fixtures, leagues: [10], teams: [], now: now)
        #expect(layout.scoreboard.map(\.id) == [2, 1])
    }

    @Test
    func `the day's matches are found by the service's days, which are in Central European time`() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // 2026-10-17 12:00 UTC: Saturday everywhere.
        let noon = Date(timeIntervalSince1970: 1_792_238_400)
        #expect(SportsDate.serviceDayKeys(coveringLocalDayOf: noon, in: berlin) == ["2026-10-17"])
        // A day in Tokyo starts at 17:00 the day before in Berlin: it reaches into two of the service's days.
        #expect(SportsDate.serviceDayKeys(coveringLocalDayOf: noon, in: tokyo) == ["2026-10-16", "2026-10-17"])
        #expect(SportsDate.serviceDayKeys(coveringLocalDayOf: noon, in: newYork) == ["2026-10-17", "2026-10-18"])
    }

    @Test
    func `the change of the clocks does not lose or double a day`() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        // 2026-10-25 is the Sunday the clocks go back: a 25-hour day.
        let day = Date(timeIntervalSince1970: 1_792_925_000)
        #expect(SportsDate.serviceDayKeys(coveringLocalDayOf: day, in: berlin) == ["2026-10-25"])
        let spring = Date(timeIntervalSince1970: 1_774_700_000) // 2026-03-28
        #expect(SportsDate.serviceDayKeys(coveringLocalDayOf: spring, in: berlin).count == 1)
    }

    @Test
    func `a match is on the person's day by its own kick-off`() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let noon = Date(timeIntervalSince1970: 1_792_238_400)
        // 2026-10-17 18:00 UTC is 03:00 on the 18th in Tokyo.
        let kickoff = Date(timeIntervalSince1970: 1_792_260_000)
        #expect(!SportsDate.isOnLocalDay(kickoff, of: noon, in: tokyo))
        #expect(SportsDate.isOnLocalDay(kickoff, of: noon, in: TimeZone(identifier: "UTC") ?? .gmt))
        #expect(!SportsDate.isOnLocalDay(nil, of: noon))
    }
}
