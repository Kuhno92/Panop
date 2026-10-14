import PanopSports
import SwiftUI

/// A row on Home with what is on today in the leagues and for the teams the person follows, live first. Home reads the
/// matches (see `TodaysMatches`), because a task on a view that draws nothing never runs: this only draws what it is
/// given,
/// and nothing when it is given none.
struct TodaysMatchesRail: View {
    let fixtures: [Fixture]
    var onOpen: () -> Void

    var body: some View {
        if !fixtures.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionHeading("Today's matches", live: fixtures.filter(\.isLive).count)
                    Button("See all", action: onOpen)
                        .font(.subheadline.weight(.semibold))
                        .padding(.trailing)
                }
                ScoreStrip(fixtures: fixtures, onOpen: { _ in onOpen() })
            }
        }
    }
}

/// The matches of today the person follows, from what is kept (refreshed at most every quarter of an hour), live first,
/// then what is to come, then what is over: at most ten.
@MainActor
enum TodaysMatches {
    static func load(
        feed: SportsFeed, sync: SportsSyncStore, profile: String, now: Date = .now, timeZone: TimeZone = .current
    ) async -> [Fixture] {
        let leagues = sync.leagues(profile: profile).map(\.id)
        let teams = sync.teams(profile: profile).map(\.id)
        guard !leagues.isEmpty || !teams.isEmpty else { return [] }
        var found: [Fixture] = []
        for key in SportsDate.serviceDayKeys(coveringLocalDayOf: now, in: timeZone) {
            found += await feed.fixtures(day: key, maxAge: 900).value ?? []
        }
        var seen = Set<Int>()
        let today = found
            .filter { SportsDate.isOnLocalDay($0.kickoff, of: now, in: timeZone) && seen.insert($0.id).inserted }
        let layout = HubLayout.make(fixtures: today, leagues: leagues, teams: teams, now: now)
        let all = layout.sections.flatMap(\.fixtures)
        let ordered = all.filter(\.isLive) + all.filter { $0.status == .scheduled } + all.filter(\.status.isFinished)
        return Array(ordered.prefix(10))
    }
}
