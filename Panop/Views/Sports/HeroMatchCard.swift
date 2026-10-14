import PanopSports
import SwiftUI

/// The match to put first: both crests large, the score or the kick-off, and the way to watch it.
struct HeroMatchCard: View {
    let fixture: Fixture
    var channel: MatchLink?
    /// False on the match's own screen, where there is nowhere further to go.
    var showsOpen = true
    var onOpen: () -> Void
    var onWatch: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text(fixture.leagueName).font(.subheadline.weight(.semibold))
                if !fixture.stage.isEmpty {
                    Text("· \(fixture.stage)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if fixture.isLive {
                    HStack(spacing: 5) {
                        LiveDot()
                        Text(fixture.minute ?? String(localized: "LIVE"))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                    }
                    .foregroundStyle(.red)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                team(fixture.homeShort, logo: fixture.homeLogo)
                centre
                    .frame(minWidth: 96)
                team(fixture.awayShort, logo: fixture.awayLogo)
            }
            HStack(spacing: 12) {
                if let channel {
                    WatchButton(link: channel, prominent: true, action: onWatch)
                }
                if showsOpen {
                    Button(action: onOpen) {
                        Label("Match", systemImage: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.bordered)
                    #endif
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.10)))
        .accessibilityElement(children: .contain)
    }

    private var centre: some View {
        VStack(spacing: 4) {
            if fixture.hasScore {
                Text("\(MatchText.score(fixture.homeScore)) – \(MatchText.score(fixture.awayScore))")
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Text(MatchText.kickoff(fixture))
                    .font(.system(size: 36, weight: .heavy, design: .rounded).monospacedDigit())
            }
            if !fixture.isLive {
                Text(fixture.hasScore ? MatchText.status(fixture) : relativeStart)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 14)
    }

    private var relativeStart: String {
        guard let kickoff = fixture.kickoff else { return "" }
        return kickoff.formatted(.relative(presentation: .named))
    }

    private func team(_ name: String, logo: String?) -> some View {
        VStack(spacing: 10) {
            TeamCrest(logo: logo, name: name, size: 84)
            Text(name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    /// The two teams' colours meeting in the middle, kept dark so the text reads on them.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TeamTint.color(for: fixture.homeName, brightness: 0.55).opacity(0.75),
                    TeamTint.color(for: fixture.awayName, brightness: 0.55).opacity(0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}
