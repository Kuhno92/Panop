import PanopSports
import SwiftUI

/// The two teams on a pitch, and the substitutes under it.
struct LineupSection: View {
    let fixture: Fixture
    let lineup: Lineup

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Line-ups")
            HStack {
                label(fixture.homeShort, formation: lineup.home.formation, side: fixture.homeName)
                Spacer()
                label(fixture.awayShort, formation: lineup.away.formation, side: fixture.awayName)
            }
            .padding(.horizontal)
            PitchView(fixture: fixture, lineup: lineup)
                .padding(.horizontal)
            HStack(alignment: .top, spacing: 16) {
                substitutes(lineup.home.substitutes, title: fixture.homeShort)
                substitutes(lineup.away.substitutes, title: fixture.awayShort)
            }
            .padding(.horizontal)
        }
    }

    private func label(_ name: String, formation: String?, side: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(TeamTint.color(for: side)).frame(width: 10, height: 10)
            Text(name).font(.subheadline.weight(.semibold))
            if let formation {
                Text(formation).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func substitutes(_ players: [LineupPlayer], title: String) -> some View {
        if players.isEmpty {
            Color.clear.frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Substitutes · \(title)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                    HStack(spacing: 6) {
                        Text(player.shirt.map(String.init) ?? "").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        Text(player.name).font(.caption).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A pitch seen from above, the home team at the bottom and the away team at the top, each player where their position
/// puts them. The service gives no formation, so rows come from the position names (see `TeamLineup.rows`).
struct PitchView: View {
    let fixture: Fixture
    let lineup: Lineup

    var body: some View {
        GeometryReader { geo in
            ZStack {
                pitch
                players(lineup.home.rows, color: TeamTint.color(for: fixture.homeName), size: geo.size, isHome: true)
                players(lineup.away.rows, color: TeamTint.color(for: fixture.awayName), size: geo.size, isHome: false)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Line-ups"))
    }

    private var pitch: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.42, blue: 0.20), Color(red: 0.07, green: 0.33, blue: 0.16)],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { context, size in
                let line = GraphicsContext.Shading.color(.white.opacity(0.35))
                let inset = size.width * 0.04
                let box = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
                context.stroke(Path(box), with: line, lineWidth: 1.5)
                var middle = Path()
                middle.move(to: CGPoint(x: box.minX, y: box.midY))
                middle.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                context.stroke(middle, with: line, lineWidth: 1.5)
                let circle = CGRect(
                    x: box.midX - size.width * 0.14,
                    y: box.midY - size.width * 0.14,
                    width: size.width * 0.28,
                    height: size.width * 0.28
                )
                context.stroke(Path(ellipseIn: circle), with: line, lineWidth: 1.5)
                for top in [true, false] {
                    let height = size.height * 0.13
                    let area = CGRect(
                        x: box.midX - size.width * 0.22,
                        y: top ? box.minY : box.maxY - height,
                        width: size.width * 0.44,
                        height: height
                    )
                    context.stroke(Path(area), with: line, lineWidth: 1.5)
                }
            }
        }
    }

    private func players(_ rows: [[LineupPlayer]], color: Color, size: CGSize, isHome: Bool) -> some View {
        let count = max(rows.count, 1)
        return ZStack {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                // Goalkeeper nearest the goal line, forwards nearest the middle.
                let depth = count > 1 ? Double(rowIndex) / Double(count - 1) : 0
                let y = isHome ? 0.93 - depth * 0.38 : 0.07 + depth * 0.38
                ForEach(Array(row.enumerated()), id: \.offset) { index, player in
                    marker(player, color: color)
                        .position(x: size.width * Double(index + 1) / Double(row.count + 1), y: size.height * y)
                }
            }
        }
    }

    private func marker(_ player: LineupPlayer, color: Color) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(color).overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                Text(player.shirt.map(String.init) ?? "").font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                if player.isCaptain {
                    Text("C").font(.system(size: 8, weight: .heavy)).foregroundStyle(.yellow).offset(x: 12, y: -12)
                }
            }
            .frame(width: 28, height: 28)
            Text(surname(player.name))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 64)
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
    }

    private func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}
