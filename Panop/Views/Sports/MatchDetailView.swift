import PanopSports
import SwiftUI

/// One match: the score, the events as they happened, the teams on a pitch, and the numbers.
struct MatchDetailView: View {
    let fixture: Fixture
    let model: SportsHubModel

    @Environment(\.sportsFeed) private var feed
    @Environment(SportsAccount.self) private var account
    @State private var detail: Fixture?
    @State private var lineup: Lineup?
    @State private var stats: MatchStats?
    @State private var asked = false
    @State private var playing: PlaybackTarget?

    private var shown: Fixture {
        detail ?? fixture
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroMatchCard(
                    fixture: shown, links: model.links[fixture.id] ?? [], showsOpen: false,
                    onOpen: {}, onWatch: { play($0) }
                )
                .padding(.horizontal)
                if !shown.events.isEmpty {
                    EventTimeline(fixture: shown)
                }
                if let lineup, !lineup.home.starters.isEmpty || !lineup.away.starters.isEmpty {
                    LineupSection(fixture: shown, lineup: lineup)
                } else if asked, !shown.status.isFinished || lineup == nil, shown.status == .scheduled {
                    Text("Line-ups appear shortly before the kick-off, where the service has them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                if let stats {
                    StatsSection(fixture: shown, stats: stats)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background { PageBackground() }
        .navigationTitle(shown.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .modifier(PlayerPresentation(target: $playing))
            .task { await run() }
    }

    private func play(_ link: MatchLink) {
        playing = model.target(for: link, in: fixture)
    }

    /// Reads the match, and while it is played reads it again every minute.
    private func run() async {
        while !Task.isCancelled {
            await load()
            guard shown.isLive else { return }
            let wait = account.quota?.refreshInterval(isLive: true) ?? 60
            guard wait.isFinite else { return }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func load() async {
        guard let feed else { return }
        let live = shown.isLive
        let finished = shown.status.isFinished
        let matchAge: TimeInterval = finished ? SportsFeed.Age.finishedMatch : (live ? 60 : 600)
        if let result = await feed.fixture(id: fixture.id, maxAge: matchAge).value {
            detail = result
        }
        if shown.status != .scheduled || (shown.kickoff.map { $0.timeIntervalSinceNow < 3600 } ?? false) {
            let lineupAge: TimeInterval = finished ? SportsFeed.Age.finishedMatch : SportsFeed.Age.lineupsBeforeKickoff
            let result = await feed.lineups(fixture: fixture.id, maxAge: lineupAge)
            if let value = result.value {
                lineup = value
            }
        }
        if shown.status != .scheduled {
            let statsAge: TimeInterval = finished ? SportsFeed.Age.finishedMatch : 120
            if let value = await feed.stats(fixture: fixture.id, maxAge: statsAge).value {
                stats = value
            }
        }
        asked = true
    }
}

// MARK: - Events

private struct EventTimeline: View {
    let fixture: Fixture

    /// A goal with the assist that went with it, as one line.
    private struct Line: Identifiable {
        var event: MatchEvent
        var assist: String?

        var id: Int {
            event.id
        }
    }

    private var lines: [Line] {
        let events = fixture.events.sorted { $0.minuteNumber < $1.minuteNumber }
        var result: [Line] = []
        for event in events {
            switch event.kind {
            case .goal, .ownGoal, .penaltyGoal, .yellowCard, .redCard, .substitution:
                result.append(Line(event: event))
            case .assist:
                if let index = result
                    .lastIndex(where: { $0.event.kind.isGoal && $0.event.side == event.side && $0.assist == nil })
                {
                    result[index].assist = event.player
                }
            case .other:
                break
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Timeline")
            VStack(spacing: 10) {
                ForEach(lines) { line in
                    HStack(spacing: 10) {
                        side(line, .home)
                        Text(line.event.minute)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 44)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        side(line, .away)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func side(_ line: Line, _ side: TeamSide) -> some View {
        if line.event.side == side {
            HStack(spacing: 8) {
                if side == .away {
                    icon(line.event.kind)
                }
                VStack(alignment: side == .home ? .trailing : .leading, spacing: 1) {
                    Text(line.event.player).font(.subheadline.weight(line.event.kind.isGoal ? .semibold : .regular))
                    if let assist = line.assist {
                        Text("Assist: \(assist)").font(.caption).foregroundStyle(.secondary)
                    }
                    if line.event.kind == .substitution, let incoming = line.event.detail {
                        Text("On: \(incoming)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(2)
                if side == .home {
                    icon(line.event.kind)
                }
            }
            .frame(maxWidth: .infinity, alignment: side == .home ? .trailing : .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func icon(_ kind: EventKind) -> some View {
        switch kind {
        case .goal, .penaltyGoal: Image(systemName: "soccerball").foregroundStyle(.primary)
        case .ownGoal: Image(systemName: "soccerball").foregroundStyle(.red)
        case .yellowCard: Image(systemName: "rectangle.portrait.fill").foregroundStyle(.yellow)
        case .redCard: Image(systemName: "rectangle.portrait.fill").foregroundStyle(.red)
        case .substitution: Image(systemName: "arrow.left.arrow.right").foregroundStyle(.green)
        default: EmptyView()
        }
    }
}

// MARK: - Statistics

private struct StatsSection: View {
    let fixture: Fixture
    let stats: MatchStats

    private struct Row: Identifiable {
        var label: LocalizedStringKey
        var home: Int?
        var away: Int?
        var percent = false

        var id: String {
            "\(label)"
        }
    }

    private var rows: [Row] {
        [
            Row(label: "Shots", home: stats.home.shots, away: stats.away.shots),
            Row(label: "Shots on target", home: stats.home.shotsOnTarget, away: stats.away.shotsOnTarget),
            Row(label: "Passes", home: stats.home.passes, away: stats.away.passes),
            Row(label: "Pass accuracy", home: stats.home.passAccuracy, away: stats.away.passAccuracy, percent: true),
            Row(label: "Fouls", home: stats.home.fouls, away: stats.away.fouls),
            Row(label: "Tackles", home: stats.home.tackles, away: stats.away.tackles),
            Row(label: "Saves", home: stats.home.saves, away: stats.away.saves),
            Row(label: "Yellow cards", home: stats.home.yellowCards, away: stats.away.yellowCards)
        ].filter { $0.home != nil || $0.away != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Statistics")
            VStack(spacing: 14) {
                ForEach(rows) { row in
                    VStack(spacing: 5) {
                        HStack {
                            Text(value(row.home, row.percent)).font(.subheadline.monospacedDigit().weight(.semibold))
                            Spacer()
                            Text(row.label).font(.footnote).foregroundStyle(.secondary)
                            Spacer()
                            Text(value(row.away, row.percent)).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        bar(row)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal)
        }
    }

    private func value(_ number: Int?, _ percent: Bool) -> String {
        guard let number else { return "–" }
        return percent ? "\(number)%" : String(number)
    }

    private func bar(_ row: Row) -> some View {
        let home = Double(row.home ?? 0)
        let away = Double(row.away ?? 0)
        let total = max(home + away, 1)
        return GeometryReader { geo in
            HStack(spacing: 3) {
                Capsule().fill(TeamTint.color(for: fixture.homeName)).frame(width: max(
                    4,
                    geo.size.width * home / total
                ))
                Capsule().fill(TeamTint.color(for: fixture.awayName)).frame(width: max(
                    4,
                    geo.size.width * away / total
                ))
            }
        }
        .frame(height: 6)
    }
}
