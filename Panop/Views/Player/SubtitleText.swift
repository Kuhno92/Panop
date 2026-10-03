import SwiftUI

/// One subtitle as it is drawn, in the person's style. Shared by the player and the settings preview, so
/// what the preview shows is what the player draws.
struct SubtitleText: View {
    let text: String
    let style: SubtitleStyle

    private var baseSize: Double {
        #if os(tvOS)
            46
        #else
            22
        #endif
    }

    var body: some View {
        let color = style.tint.components
        Text(text)
            .font(.system(size: baseSize * style.size.scale, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(red: color.red, green: color.green, blue: color.blue))
            // Without a box the text needs an edge to stay readable over a bright picture.
            .shadow(color: .black.opacity(style.backdrop == .none ? 0.9 : 0), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(style.backdrop.opacity), in: RoundedRectangle(cornerRadius: 6))
    }
}
