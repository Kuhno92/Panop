import PanopSports
import SwiftUI

/// One match in a list: status, the two teams with their crests, the score, and a button to watch it when a channel
/// of the person's playlist has it.
struct MatchRow: View {
    let fixture: Fixture
    var followed: Set<Int> = []
    var links: [MatchLink] = []
    var onOpen: () -> Void
    var onWatch: (MatchLink) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    statusColumn
                    VStack(alignment: .leading, spacing: 8) {
                        teamLine(
                            fixture.homeShort,
                            logo: fixture.homeLogo,
                            id: fixture.homeID,
                            goals: fixture.homeScore,
                            won: homeWon
                        )
                        teamLine(
                            fixture.awayShort,
                            logo: fixture.awayLogo,
                            id: fixture.awayID,
                            goals: fixture.awayScore,
                            won: awayWon
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            #if os(tvOS)
            .buttonStyle(.card)
            #else
            .buttonStyle(.plain)
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MatchText.spoken(fixture))
            if !links.isEmpty {
                WatchControl(links: links, onPick: onWatch)
            }
        }
        #if !os(tvOS)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
        #endif
        .opacity(fixture.status == .cancelled || fixture.status == .postponed ? 0.6 : 1)
    }

    private var homeWon: Bool? {
        winner(fixture.homeScore, fixture.awayScore)
    }

    private var awayWon: Bool? {
        winner(fixture.awayScore, fixture.homeScore)
    }

    /// Only a finished match has a winner worth drawing: a score still changing is not one.
    private func winner(_ mine: Int?, _ other: Int?) -> Bool? {
        guard fixture.status.isFinished, let mine, let other else { return nil }
        return mine > other
    }

    private var statusColumn: some View {
        VStack(spacing: 3) {
            if fixture.isLive {
                LiveDot()
            }
            Text(MatchText.status(fixture))
                .font(.subheadline.monospacedDigit().weight(fixture.isLive ? .bold : .regular))
                .foregroundStyle(fixture.isLive ? Color.liveGreen : .secondary)
        }
        .frame(width: 52)
    }

    /// Large enough to read the crest from the sofa on Apple TV.
    private static var crestSize: CGFloat {
        #if os(tvOS)
            46
        #else
            26
        #endif
    }

    private func teamLine(_ name: String, logo: String?, id: Int?, goals: Int?, won: Bool?) -> some View {
        HStack(spacing: 10) {
            TeamCrest(logo: logo, name: name, size: Self.crestSize)
            Text(name)
                .font(.body.weight(won == true || (id.map(followed.contains) ?? false) ? .semibold : .regular))
                .foregroundStyle(won == false ? .secondary : .primary)
                .lineLimit(1)
            if let id, followed.contains(id) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Spacer(minLength: 8)
            if fixture.hasScore {
                Text(MatchText.score(goals))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(won == false ? .secondary : .primary)
            }
        }
    }
}

/// The red dot of a match that is being played.
extension Color {
    /// What is on now: the live dot and the minute of a match.
    static let liveGreen = Color(red: 0.22, green: 0.86, blue: 0.45)
}

struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = true

    var body: some View {
        Circle()
            .fill(Color.liveGreen)
            .frame(width: 7, height: 7)
            .opacity(bright || reduceMotion ? 1 : 0.35)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bright = false }
            }
            .accessibilityHidden(true)
    }
}

/// "Watch" with the channel's name. When one channel is sure it is a button that starts it; when several could be the
/// match (or none is sure), it is a menu to choose from, each with what the guide says is on.
struct WatchControl: View {
    let links: [MatchLink]
    var onPick: (MatchLink) -> Void

    private var top: MatchLink? {
        links.first
    }

    var body: some View {
        if let top {
            if links.count == 1, top.score.tier >= .likely {
                Button { onPick(top) } label: { label(top) }
                    .buttonStyle(style)
                    .modifier(WatchTint(sure: top.score.tier == .watch))
                    .accessibilityLabel(Text("Watch on \(top.channel.name)"))
            } else {
                Menu {
                    ForEach(links) { link in
                        Button { onPick(link) } label: {
                            Text("\(link.channel.name) · \(link.programme.title)")
                        }
                    }
                } label: { label(top, many: true) }
                    .buttonStyle(style)
                    .modifier(WatchTint(sure: top.score.tier == .watch))
            }
        }
    }

    private var style: some PrimitiveButtonStyle {
        #if os(tvOS)
            .card
        #else
            .borderedProminent
        #endif
    }

    private func label(_ link: MatchLink, many: Bool = false) -> some View {
        VStack(spacing: 2) {
            Label(many ? String(localized: "Watch…") : String(localized: "Watch"), systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
            Text(link.channel.name)
                .font(.caption2)
                .lineLimit(1)
                .opacity(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 150)
    }
}

/// Green for a channel that is sure, grey for one to confirm. Not on Apple TV: a tinted card there is a bright slab
/// with
/// pale text on it, and the focus already says what is selected.
private struct WatchTint: ViewModifier {
    let sure: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
            content
        #else
            content.tint(sure ? .green : .gray)
        #endif
    }
}
