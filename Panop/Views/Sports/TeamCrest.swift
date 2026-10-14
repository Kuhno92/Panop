import PanopSports
import SwiftUI

/// A team's crest: its logo from the service when there is one, and until it arrives (or when it never does, or the
/// team has none) its initials on a colour that is the team's own.
struct TeamCrest: View {
    let logo: String?
    let name: String
    var size: CGFloat = 36

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image = image ?? remembered {
                Circle().fill(.white.opacity(0.10))
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                Circle().fill(TeamTint.gradient(for: name))
                Text(TeamMonogram.initials(for: name))
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: logo) { await load() }
    }

    private var address: URL? {
        SportsLogo.url(file: logo)
    }

    private var remembered: CGImage? {
        guard let address else { return nil }
        return pipeline.cachedImage(for: address, maxPixel: ChannelLogo.pixels(for: size * scale))
    }

    private func load() async {
        guard let address else {
            image = nil
            return
        }
        if remembered != nil {
            image = nil
            return
        }
        image = nil
        image = await pipeline.image(for: address, maxPixel: ChannelLogo.pixels(for: size * scale))
    }
}

/// The colours a team is drawn in when it has no crest of its own.
enum TeamTint {
    static func color(for name: String, brightness: Double = 0.78) -> Color {
        Color(hue: TeamMonogram.hue(for: name), saturation: 0.62, brightness: brightness)
    }

    static func gradient(for name: String) -> LinearGradient {
        LinearGradient(
            colors: [color(for: name, brightness: 0.86), color(for: name, brightness: 0.52)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
