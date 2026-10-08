import SwiftUI

/// Full screen where the platform has it; a window of its own on the Mac.
struct PlayerPresentation: ViewModifier {
    @Binding var target: PlaybackTarget?

    #if os(macOS) || os(tvOS)
        @Environment(EmbeddedPlayback.self) private var embedded
    #endif
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        /// Off by default: a stream plays in the main window, with the rest of the app usable over it. On, it opens in
        /// a
        /// window of its own that can be moved, resized and put on another display.
        @AppStorage("playsInSeparateWindow") private var separateWindow = false
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
            // In the screen under the app, as on a Mac: Menu sends the stream to the back and it plays on.
            content.onChange(of: target) {
                if let target {
                    embedded.play(target)
                    self.target = nil
                }
            }
        #elseif os(macOS)
            // In the main window unless the person asked for a window of its own (a window that can be moved,
            // resized, put on another display and taken full screen). Opening the same item again in its own
            // window brings that window forward instead of making a second one.
            content.onChange(of: target) {
                if let target {
                    if separateWindow {
                        openWindow(id: PlayerWindow.id, value: PlayerWindowRequest(target))
                    } else {
                        embedded.play(target)
                    }
                    self.target = nil
                }
            }
        #else
            content.fullScreenCover(item: $target) { target in
                PlayerScreen(target: target)
            }
        #endif
    }
}
