import PanopSports
import SwiftUI

/// The match to put first: both crests large, the score or the kick-off, and the way to watch it.
struct HeroMatchCard: View {
    let fixture: Fixture
    var links: [MatchLink] = []
    /// False on the match's own screen, where there is nowhere further to go.
    var showsOpen = true
    var onOpen: () -> Void
    var onWatch: (MatchLink) -> Void = { _ in }

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
                    .foregroundStyle(Color.liveGreen)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                team(fixture.homeShort)
                centre
                    .frame(minWidth: 96)
                team(fixture.awayShort)
            }
            HStack(spacing: 12) {
                if !links.isEmpty {
                    WatchControl(links: links, onPick: onWatch)
                        .accessibilityIdentifier("heroWatch")
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
                    .accessibilityIdentifier("heroMatch")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.10)))
        .accessibilityElement(children: .contain)
        // The buttons sit in the middle of a card that is as wide as the screen. Moving down from the day picker at its
        // left edge looked for a button straight below, found none, and jumped past the card to the scores. A section
        // takes the focus from anywhere above or below it.
        #if os(tvOS)
            .focusSection()
        #endif
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

    /// The name only: the crest is in the background, large, on this team's side of the card.
    private func team(_ name: String) -> some View {
        Text(name)
            .font(.title3.weight(.bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.5), radius: 6)
            .frame(maxWidth: .infinity, minHeight: Self.crestSize * 0.6)
    }

    private static var crestSize: CGFloat {
        #if os(tvOS)
            300
        #else
            190
        #endif
    }

    /// A crest drawn large and faded into the card at its edge, cropped by it, and thinning out towards the middle so
    /// the score reads over it.
    private func crest(_ logo: String?, name: String, towards edge: Edge) -> some View {
        TeamCrest(logo: logo, name: name, size: Self.crestSize, bare: true)
            .opacity(0.5)
            .offset(x: edge == .leading ? -Self.crestSize * 0.22 : Self.crestSize * 0.22)
            .mask(
                LinearGradient(
                    colors: [.black, .black.opacity(0.0)],
                    startPoint: edge == .leading ? .leading : .trailing,
                    endPoint: edge == .leading ? .trailing : .leading
                )
            )
            .allowsHitTesting(false)
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
            HStack(spacing: 0) {
                crest(fixture.homeLogo, name: fixture.homeName, towards: .leading)
                Spacer(minLength: 0)
                crest(fixture.awayLogo, name: fixture.awayName, towards: .trailing)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}
