import PanopSports
import SwiftUI

/// One match in a list: status, the two teams with their crests, the score, and a button to watch it when a channel
/// of the person's playlist has it.
struct MatchRow: View {
    let fixture: Fixture
    var followed: Set<Int> = []
    var channel: MatchLink?
    var onOpen: () -> Void
    var onWatch: () -> Void = {}

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
            if let channel {
                WatchButton(link: channel, action: onWatch)
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
                .foregroundStyle(fixture.isLive ? Color.red : .secondary)
        }
        .frame(width: 52)
    }

    private func teamLine(_ name: String, logo: String?, id: Int?, goals: Int?, won: Bool?) -> some View {
        HStack(spacing: 10) {
            TeamCrest(logo: logo, name: name, size: 26)
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
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = true

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 7, height: 7)
            .opacity(bright || reduceMotion ? 1 : 0.35)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bright = false }
            }
            .accessibilityHidden(true)
    }
}

/// "Watch" with the channel's name: starts the channel that has the match.
struct WatchButton: View {
    let link: MatchLink
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Label("Watch", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                Text(link.channel.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 140)
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.borderedProminent)
        .tint(link.score.tier == .watch ? .green : .gray)
        #endif
        .accessibilityLabel(Text("Watch on \(link.channel.name)"))
    }
}
