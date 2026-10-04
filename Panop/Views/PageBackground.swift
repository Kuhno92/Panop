import SwiftUI

/// The backdrop of the browsing screens: a deep, slightly blue ground with two soft glows, so the space between and
/// under the rows has some colour instead of flat grey. The hero's artwork fades into it. Drawn as plain gradients,
/// which cost nothing to scroll over.
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: ground, startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [glow(.indigo, 0.28), .clear],
                center: UnitPoint(x: 0.1, y: 0.62),
                startRadius: 10,
                endRadius: 520
            )
            RadialGradient(
                colors: [glow(.teal, 0.20), .clear],
                center: UnitPoint(x: 0.95, y: 0.88),
                startRadius: 10,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var ground: [Color] {
        scheme == .dark
            ? [Color(red: 0.06, green: 0.07, blue: 0.14), Color(red: 0.02, green: 0.02, blue: 0.05)]
            : [Color(red: 0.97, green: 0.97, blue: 1.0), Color(red: 0.92, green: 0.94, blue: 0.98)]
    }

    /// Lighter touch on a light page, where the same strength would look dirty.
    private func glow(_ color: Color, _ strength: Double) -> Color {
        color.opacity(scheme == .dark ? strength : strength * 0.55)
    }
}

extension View {
    /// The gradient page behind a list or form: the list's own background is hidden so it shows through (Apple TV
    /// has no way to hide it, and keeps its own).
    func pageBackdrop() -> some View {
        #if os(tvOS)
            background { PageBackground() }
        #else
            scrollContentBackground(.hidden).background { PageBackground() }
        #endif
    }
}
