import SwiftUI

extension EnvironmentValues {
    /// Where images come from. The app's own by default; a test supplies one that needs no
    /// network.
    @Entry var imagePipeline: ImagePipeline = .shared
}

/// A channel's logo at a fixed size, with a placeholder until it arrives and when it never
/// does. The image is decoded at the size drawn, not the size downloaded.
struct ChannelLogo: View {
    let address: String?
    var size: CGFloat = 44

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.1)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        // Re-runs when the row is reused for another channel, and stops when it scrolls away.
        .task(id: address) { await load() }
    }

    private func load() async {
        image = nil
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        image = await pipeline.image(for: url, maxPixel: Self.pixels(for: size * scale))
    }

    /// Sizes are rounded up to a few steps, so the same logo at slightly different sizes
    /// shares one cache entry and is decoded once.
    nonisolated static func pixels(for points: CGFloat) -> Int {
        let steps = [64, 128, 192, 256, 384, 512]
        return steps.first { CGFloat($0) >= points } ?? 512
    }
}
