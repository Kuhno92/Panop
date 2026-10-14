import PanopSports
import SwiftUI

/// The tables of the leagues the person follows: position, club, played, goal difference, points and the last results.
/// Followed teams are marked. A cup has no table, and says so.
struct StandingsView: View {
    let leagues: [SportsLeagueChoice]
    let followedTeams: Set<Int>

    @Environment(\.sportsFeed) private var feed
    @State private var selected: Int?
    @State private var rows: [StandingRow] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading, ready, empty, failed
    }

    private var current: SportsLeagueChoice? {
        leagues.first { $0.id == selected } ?? leagues.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if leagues.count > 1 {
                leaguePicker
            } else if let current {
                SectionHeading(LocalizedStringKey(current.name), detail: current.country)
            }
            content
        }
        .task(id: current?.id) { await load() }
    }

    private var leaguePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(leagues) { league in
                    Button { selected = league.id } label: {
                        Text(league.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                league.id == current?.id ? Color.accentColorOrWhite.opacity(0.9) : Color.gray
                                    .opacity(0.22),
                                in: Capsule()
                            )
                            .foregroundStyle(league.id == current?.id ? Color.black : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(league.id == current?.id ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            SportsSkeleton().frame(maxHeight: 280)
        case .failed:
            Text("The table could not be loaded.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await load(force: true) } }.padding(.horizontal)
        case .empty:
            Text("This competition has no table.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        case .ready:
            table
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            header
            ForEach(rows) { row in
                line(row)
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 24, alignment: .trailing)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34)
            Text("P").frame(width: 28)
            Text("GD").frame(width: 34)
            Text("Pts").frame(width: 34)
            Text("Form").frame(width: 70)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func line(_ row: StandingRow) -> some View {
        let followed = followedTeams.contains(row.team.id)
        return HStack(spacing: 6) {
            Text("\(row.position)").frame(width: 24, alignment: .trailing).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TeamCrest(logo: row.team.logo, name: row.team.name, size: 26)
                Text(row.team.shortName).lineLimit(1)
                if followed {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.played)").frame(width: 28)
            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)").frame(width: 34)
            Text("\(row.points)").frame(width: 34).fontWeight(.bold)
            FormDots(results: Array(row.form.suffix(5))).frame(width: 70)
        }
        .font(.subheadline.monospacedDigit().weight(followed ? .semibold : .regular))
        .padding(.vertical, 9)
        .background(followed ? Color.yellow.opacity(0.08) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.position). \(row.team.name), \(row.points) \(String(localized: "points")), \(row.played) \(String(localized: "played"))"
        )
    }

    private func load(force: Bool = false) async {
        guard let feed, let league = current else { return }
        phase = .loading
        let result = await feed.standings(league: league.id, force: force)
        if let value = result.value {
            rows = value
            phase = value.isEmpty ? .empty : .ready
        } else {
            rows = []
            phase = .failed
        }
    }
}

/// The last results of a team as small dots: win, draw, loss. Colour and a letter, so colour alone says nothing.
struct FormDots: View {
    let results: [FormResult]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Text(letter(result))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(colour(result), in: Circle())
            }
        }
        .accessibilityHidden(true)
    }

    private func letter(_ result: FormResult) -> String {
        switch result {
        case .win: "W"
        case .draw: "D"
        case .loss: "L"
        case .unknown: "·"
        }
    }

    private func colour(_ result: FormResult) -> Color {
        switch result {
        case .win: .green
        case .draw: .gray
        case .loss: .red
        case .unknown: .gray.opacity(0.5)
        }
    }
}

private extension Color {
    /// The accent, except on Apple TV where it resolves to white and is wanted as a plain choice anyway.
    static var accentColorOrWhite: Color {
        #if os(tvOS)
            .white
        #else
            .accentColor
        #endif
    }
}
