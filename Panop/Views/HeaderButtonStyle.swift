#if os(tvOS) || os(iOS)
    import SwiftUI

    /// The buttons in the row above a list (guide, sort, source, suggestions) and the category chips. The system's
    /// bordered look is a dark pane on a dark page, or blue on blue, and hardly there; this is a light pill, and on
    /// Apple
    /// TV it turns solid white when it has focus.
    struct HeaderButtonStyle: ButtonStyle {
        /// The chosen one of a row of choices: lighter than the rest, so it can be told at a glance.
        var isChosen = false

        @Environment(\.isFocused) private var isFocused

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Self.across)
                .padding(.vertical, Self.down)
                .foregroundStyle(isFocused || isChosen ? Color.black : Color.white)
                // Dark glass for the rest and white for the chosen one and the focused one: readable over a bright
                // picture as well as a dark page, where a light, see-through pill disappeared.
                .background {
                    Capsule().fill(isFocused || isChosen ? Color.white : Color.black.opacity(0.5))
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .environment(\.colorScheme, .dark)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(isFocused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }

        private static var across: CGFloat {
            #if os(tvOS)
                26
            #else
                12
            #endif
        }

        private static var down: CGFloat {
            #if os(tvOS)
                14
            #else
                8
            #endif
        }
    }
#endif
