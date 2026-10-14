import Foundation

/// What the sports hub shows for a day, worked out from the day's matches and what the person follows. Pure: no screen,
/// no clock of its own, so every rule here is tested.
public struct HubLayout: Sendable, Equatable {
    /// The match to put first: one of a followed team that is on, else the next of theirs, else the biggest on.
    public var hero: Fixture?
    /// What is on now, and what finished within the last hours: the scoreboard strip.
    public var scoreboard: [Fixture]
    /// The matches of the person's leagues and teams by league, leagues with a match on first.
    public var sections: [Section]
    /// The matches of followed teams, soonest first.
    public var mine: [Fixture]

    public struct Section: Sendable, Equatable, Identifiable {
        public var leagueID: Int?
        public var name: String
        public var zone: String
        public var fixtures: [Fixture]

        public var id: String {
            leagueID.map(String.init) ?? name
        }

        public var liveCount: Int {
            fixtures.filter(\.isLive).count
        }
    }

    public static let empty = HubLayout(hero: nil, scoreboard: [], sections: [], mine: [])

    /// - Parameters:
    ///   - fixtures: the day's matches, from every league.
    ///   - leagues: the ids of the leagues the person follows, in the order they chose them.
    ///   - teams: the ids of the teams they follow.
    ///   - now: for what is on, what is next and what finished a while ago.
    public static func make(fixtures: [Fixture], leagues: [Int], teams: [Int], now: Date) -> HubLayout {
        let leagueOrder = Dictionary(leagues.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let teamSet = Set(teams)
        let followed = fixtures.filter { fixture in
            fixture.leagueID.map { leagueOrder[$0] != nil } == true
                || fixture.homeID.map(teamSet.contains) == true
                || fixture.awayID.map(teamSet.contains) == true
        }
        let involvesTeam = { (fixture: Fixture) in
            fixture.homeID.map(teamSet.contains) == true || fixture.awayID.map(teamSet.contains) == true
        }

        let mine = followed.filter(involvesTeam).sorted(by: byKickoff)
        let scoreboard = followed
            .filter { $0.isLive || isRecentlyFinished($0, now: now) }
            .sorted { ($0.isLive ? 0 : 1, $0.kickoff ?? .distantFuture) < (
                $1.isLive ? 0 : 1,
                $1.kickoff ?? .distantFuture
            ) }

        return HubLayout(
            hero: hero(in: followed, involvesTeam: involvesTeam, now: now),
            scoreboard: scoreboard,
            sections: sections(of: followed, leagueOrder: leagueOrder),
            mine: mine
        )
    }

    // MARK: - Pieces

    private static func hero(in fixtures: [Fixture], involvesTeam: (Fixture) -> Bool, now: Date) -> Fixture? {
        let mine = fixtures.filter(involvesTeam)
        if let live = mine.filter(\.isLive).min(by: byKickoff) {
            return live
        }
        if let next = upcoming(in: mine, now: now).first {
            return next
        }
        if let live = fixtures.filter(\.isLive).min(by: byKickoff) {
            return live
        }
        if let next = upcoming(in: fixtures, now: now).first {
            return next
        }
        // A day that is over: the latest result of a followed team.
        return mine.filter(\.status.isFinished).max(by: byKickoff)
    }

    private static func upcoming(in fixtures: [Fixture], now: Date) -> [Fixture] {
        fixtures
            .filter { $0.status == .scheduled && ($0.kickoff ?? .distantPast) > now.addingTimeInterval(-15 * 60) }
            .sorted(by: byKickoff)
    }

    private static func isRecentlyFinished(_ fixture: Fixture, now: Date) -> Bool {
        guard fixture.status.isFinished, let kickoff = fixture.kickoff else { return false }
        // A match lasts under two hours; "recent" is within three hours of its end.
        return kickoff.addingTimeInterval(5 * 3600) > now
    }

    private static func sections(of fixtures: [Fixture], leagueOrder: [Int: Int]) -> [Section] {
        var grouped: [String: Section] = [:]
        var order: [String] = []
        for fixture in fixtures {
            let key = fixture.leagueID.map(String.init) ?? fixture.leagueName
            if grouped[key] == nil {
                grouped[key] = Section(
                    leagueID: fixture.leagueID,
                    name: fixture.leagueName,
                    zone: fixture.leagueZone,
                    fixtures: []
                )
                order.append(key)
            }
            grouped[key]?.fixtures.append(fixture)
        }
        var sections = order.compactMap { grouped[$0] }
        for index in sections.indices {
            sections[index].fixtures.sort(by: byPhase)
        }
        // A league with a match on goes first; then the order the person chose their leagues in; then the rest by name.
        return sections.sorted { lhs, rhs in
            if (lhs.liveCount > 0) != (rhs.liveCount > 0) {
                return lhs.liveCount > 0
            }
            let (left, right) = (lhs.leagueID.flatMap { leagueOrder[$0] }, rhs.leagueID.flatMap { leagueOrder[$0] })
            switch (left, right) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
    }

    private static func byKickoff(_ lhs: Fixture, _ rhs: Fixture) -> Bool {
        (lhs.kickoff ?? .distantFuture, lhs.id) < (rhs.kickoff ?? .distantFuture, rhs.id)
    }

    /// Within a league: what is on, then what is coming, then what is over, then what will not be played.
    private static func byPhase(_ lhs: Fixture, _ rhs: Fixture) -> Bool {
        let (left, right) = (rank(lhs), rank(rhs))
        return left != right ? left < right : byKickoff(lhs, rhs)
    }

    private static func rank(_ fixture: Fixture) -> Int {
        if fixture.isLive {
            return 0
        }
        switch fixture.status {
        case .scheduled: return 1
        case .finished, .afterExtraTime, .penalties: return 2
        default: return 3
        }
    }
}

public extension SportsDate {
    /// The service counts a match's day in Central European time. A person's own day starts and ends at other moments,
    /// so
    /// it can span two of the service's days: these are the day keys to ask for, to have all of theirs.
    static func serviceDayKeys(coveringLocalDayOf date: Date, in timeZone: TimeZone = .current) -> [String] {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let start = local.startOfDay(for: date)
        let end = local.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        let service = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        var keys = [dayKey(for: start, in: service)]
        let last = dayKey(for: end, in: service)
        if last != keys[0] {
            keys.append(last)
        }
        return keys
    }

    /// Whether a match kicks off on the person's day of `date`.
    static func isOnLocalDay(_ kickoff: Date?, of date: Date, in timeZone: TimeZone = .current) -> Bool {
        guard let kickoff else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(kickoff, inSameDayAs: date)
    }
}
