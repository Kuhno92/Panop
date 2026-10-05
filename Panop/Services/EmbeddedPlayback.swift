#if os(macOS)
    import Observation

    /// The stream playing inside the Mac's main window, so the rest of the app can be used over it.
    ///
    /// Playing is not a screen the person is sent to and must come back from: the stream is a layer under the whole
    /// app.
    /// In front it is the window's picture with its controls; at the back it keeps playing and the app, made
    /// see-through,
    /// is drawn over it.
    @MainActor
    @Observable
    final class EmbeddedPlayback {
        private(set) var target: PlaybackTarget?
        /// True while the stream is what is on top; false while the app is laid over it.
        private(set) var isFront = false

        var isPlaying: Bool {
            target != nil
        }

        /// Starts a stream (replacing one that is playing) and brings it forward.
        func play(_ target: PlaybackTarget) {
            self.target = target
            isFront = true
        }

        func bringToFront() {
            if target != nil {
                isFront = true
            }
        }

        func sendToBack() {
            isFront = false
        }

        func stop() {
            target = nil
            isFront = false
        }
    }
#endif
