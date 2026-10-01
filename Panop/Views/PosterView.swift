import SwiftUI

/// A film or series poster, portrait, filled and cropped to its frame. Like `ChannelLogo` it is
/// decoded at the size shown by the image pipeline, never at the size downloaded.
struct PosterView: View {
    let address: String?
    var symbol = "film"

    @Environment(\.imagePipeline) private var pipeline
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: address) { await load() }
    }

    private func load() async {
        image = nil
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        image = await pipeline.image(for: url, maxPixel: Self.pixels)
    }

    /// Posters are drawn about this wide at most, so one size serves every card and a poster is
    /// decoded once however it is shown.
    private static let pixels = 512
}
