import SwiftUI

extension EnvironmentValues {
    /// True while the app is laid over a stream playing behind it (a Mac's main window): the page backgrounds become
    /// see-through, so the picture shows.
    @Entry var overStream: Bool = false
}

/// The backdrop of the browsing screens: a deep, slightly blue ground with two soft glows, so the space between and
/// under the rows has some colour instead of flat grey. The hero's artwork fades into it. Drawn as plain gradients,
/// which cost nothing to scroll over.
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.overStream) private var overStream

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
        // Over a stream: enough of the page stays to read the text on, and the rest lets the picture through.
        .opacity(overStream ? 0.58 : 1)
        .background(overStream ? Color.black.opacity(0.2) : .clear)
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
    /// Apple TV: no navigation bar under the tab bar. Its title repeats the tab's own, and the bar's buttons sat
    /// between
    /// the tab bar and the content, taking the room (and the focus: Up from them did not reach the tab bar). A no-op
    /// elsewhere.
    func withoutTVTitleBar() -> some View {
        #if os(tvOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    /// The gradient page behind a list or form: the list's own background is hidden so it shows through (Apple TV
    /// has no way to hide it, and keeps its own).
    func pageBackdrop() -> some View {
        // Stretched to the whole area first: on a Mac a form takes only the room its content needs, and the gradient
        // would then fill that box with the window's plain grey showing around it.
        #if os(tvOS)
            frame(maxWidth: .infinity, maxHeight: .infinity).background { PageBackground() }
        #else
            scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { PageBackground() }
        #endif
    }
}

/// Panop's icon as a picture in the app, rounded the way the system rounds an app icon.
struct AppLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: size * 0.1, y: size * 0.04)
            .accessibilityHidden(true)
    }
}
