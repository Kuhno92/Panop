import SwiftUI

/// Said once, the first time the app opens: Panop brings no channels, films or series of its own. Shown over whatever
/// screen the app opens on, and never again after it is closed. Not in a UI test, where it would sit over every screen.
struct FirstLaunchNotice: ViewModifier {
    @AppStorage("hasSeenContentNotice") private var hasSeen = false
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .task {
                if UITestMode.isActive {
                    return
                }
                isShowing = !hasSeen
            }
            .alert("Welcome to Panop", isPresented: $isShowing) {
                Button("OK") { hasSeen = true }
            } message: {
                Text("""
                Panop ships no content. It only plays the sources you add yourself: your own playlists and \
                provider logins.
                """)
            }
    }
}
