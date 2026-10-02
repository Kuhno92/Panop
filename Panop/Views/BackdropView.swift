import SwiftUI

/// Wide artwork behind or above content: a film's backdrop, or a blurred, enlarged logo or
/// poster used as a hero's background. Decoded by the image pipeline at the size shown, like the
/// posters and logos.
struct BackdropView: View {
    let address: String?
    /// Soft enough to sit behind text. For small artwork such as a logo, which would otherwise
    /// show its pixels.
    var blurred = false

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
                    .blur(radius: blurred ? 24 : 0)
                    .transition(.opacity)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: address) { await load() }
    }

    private func load() async {
        image = nil
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        // One size for every backdrop, so each is decoded once however it is shown.
        let loaded = await pipeline.image(for: url, maxPixel: Self.pixels)
        withAnimation(.easeIn(duration: 0.2)) { image = loaded }
    }

    private static let pixels = 1024
}
