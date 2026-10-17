import PanopSports
import SwiftUI

/// What is on now and what finished lately, as small scoreboards in a row.
struct ScoreStrip: View {
    let fixtures: [Fixture]
    var onOpen: (Fixture) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: RailMetrics.spacing) {
                ForEach(fixtures) { fixture in
                    Button { onOpen(fixture) } label: { chip(fixture) }
                    #if os(tvOS)
                        .buttonStyle(.card)
                    #else
                        .buttonStyle(.plain)
                    #endif
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(MatchText.spoken(fixture))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, RailMetrics.verticalRoom)
        }
        .scrollClipDisabled()
    }

    private func chip(_ fixture: Fixture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if fixture.isLive {
                    LiveDot()
                }
                Text(MatchText.status(fixture))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(fixture.isLive ? Color.liveGreen : .secondary)
                Spacer(minLength: 0)
            }
            line(fixture.homeShort, logo: fixture.homeLogo, goals: fixture.homeScore, fixture: fixture)
            line(fixture.awayShort, logo: fixture.awayLogo, goals: fixture.awayScore, fixture: fixture)
        }
        .padding(12)
        .frame(width: 168)
        #if !os(tvOS)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        #endif
    }

    private func line(_ name: String, logo: String?, goals: Int?, fixture: Fixture) -> some View {
        HStack(spacing: 8) {
            TeamCrest(logo: logo, name: name, size: 20)
            Text(name).font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            if fixture.hasScore {
                Text(MatchText.score(goals)).font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
    }
}
