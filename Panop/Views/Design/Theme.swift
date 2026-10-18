import SwiftUI

/// The look the app shares: one accent, one card, one pair of buttons. Everything here is a flat fill, a gradient or a
/// hairline, which cost nothing to scroll over: no blur and no shadow on anything that repeats down a list.
enum Theme {
    /// The accent, a blue that leans to violet. Not `Color.accentColor`, which is white on Apple TV.
    static let blue = Color(red: 0.30, green: 0.52, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.40, blue: 1.0)

    static var accent: LinearGradient {
        LinearGradient(colors: [blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The corner of a card, and of a poster.
    static var cardRadius: CGFloat {
        #if os(tvOS)
            24
        #else
            18
        #endif
    }

    static var posterRadius: CGFloat {
        #if os(tvOS)
            16
        #else
            14
        #endif
    }
}

/// A translucent card with a hairline that catches the light at its top edge: a surface on the page, not a box.
struct GlassCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(scheme == .dark ? 0.20 : 0.5), .white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

/// The two buttons of a hero and of a page's main choice: the accent gradient with white text, and the glass one. On
/// Apple TV the system's own styles are kept, since they carry the focus effect.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // A list row would show a button's icon alone.
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(prominent ? Color.white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if prominent {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().fill(.white.opacity(0.12)).overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

#if os(tvOS)
    /// A poster on Apple TV when the remote is on it: it rises, brightens a touch and glows in the accent. The system's
    /// card style gave a grey plate and a small lift; this is the app's own, and just as cheap: one scale and one
    /// shadow on the one card in focus.
    struct PosterFocusStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            PosterFocusLabel(label: configuration.label, pressed: configuration.isPressed)
        }
    }

    private struct PosterFocusLabel: View {
        let label: ButtonStyleConfiguration.Label
        let pressed: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            label
                .scaleEffect(pressed ? 1.02 : (focused ? 1.08 : 1))
                .brightness(focused ? 0.05 : 0)
                .shadow(color: focused ? Theme.violet.opacity(0.6) : .clear, radius: 28, y: 12)
                .animation(.spring(duration: 0.3, bounce: 0.25), value: focused)
                .focusEffectDisabled()
        }
    }
#endif

extension View {
    /// The main and the other choices on a page: Panop's pills, and on Apple TV the system's, which carry the focus
    /// effect.
    @ViewBuilder
    func pageButton(prominent: Bool = false) -> some View {
        #if os(tvOS)
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        #else
            buttonStyle(PillButtonStyle(prominent: prominent))
        #endif
    }
}
