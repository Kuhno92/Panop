import SwiftUI

extension View {
    /// A plain button, and on Apple TV one without the system's focus effect: a large white rounded block with dark
    /// text
    /// that spilled out of a channel's cell, and a lift that covered its neighbours. The focus is a ring, drawn here.
    @ViewBuilder
    func guideButtonStyle(cornerRadius: CGFloat, onFocus: (() -> Void)? = nil) -> some View {
        #if os(tvOS)
            buttonStyle(GuideFocusStyle(cornerRadius: cornerRadius, onFocus: onFocus)).focusEffectDisabled()
        #else
            buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
    private struct GuideFocusStyle: ButtonStyle {
        let cornerRadius: CGFloat
        var onFocus: (() -> Void)?

        func makeBody(configuration: Configuration) -> some View {
            GuideFocusRing(cornerRadius: cornerRadius, onFocus: onFocus) { configuration.label }
        }
    }

    private struct GuideFocusRing<Content: View>: View {
        let cornerRadius: CGFloat
        var onFocus: (() -> Void)?
        @ViewBuilder let content: () -> Content
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            content()
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: isFocused ? 5 : 0)
                }
                .brightness(isFocused ? 0.12 : 0)
                .animation(.easeOut(duration: 0.12), value: isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        onFocus?()
                    }
                }
        }
    }
#endif
