#if os(macOS)
    @testable import Panop
    import PanopCore
    import Testing

    @MainActor
    @Suite("Embedded playback")
    struct EmbeddedPlaybackTests {
        private func target(_ name: String) -> PlaybackTarget {
            PlaybackTarget(
                playlist: "p",
                entryID: name,
                kind: .live,
                name: name,
                streamURL: "http://127.0.0.1:9/\(name).ts"
            )
        }

        @Test
        func `nothing plays until a stream is started, and then it is in front`() {
            let playback = EmbeddedPlayback()
            #expect(!playback.isPlaying)
            #expect(!playback.isFront)

            playback.play(target("Arte"))

            #expect(playback.isPlaying)
            #expect(playback.isFront)
            #expect(playback.target?.name == "Arte")
        }

        @Test
        func `sending it back keeps it playing, and it can be brought forward again`() {
            let playback = EmbeddedPlayback()
            playback.play(target("Arte"))

            playback.sendToBack()
            #expect(playback.isPlaying, "going back to the app must not stop the stream")
            #expect(!playback.isFront)

            playback.bringToFront()
            #expect(playback.isFront)
        }

        @Test
        func `a second stream replaces the first and comes forward`() {
            let playback = EmbeddedPlayback()
            playback.play(target("Arte"))
            playback.sendToBack()

            playback.play(target("ZDF"))

            #expect(playback.target?.name == "ZDF")
            #expect(playback.isFront)
        }

        @Test
        func `asking for the guide goes back to the app and keeps the stream playing`() {
            let playback = EmbeddedPlayback()
            playback.play(target("Arte"))

            playback.showGuide()

            #expect(playback.guideRequested)
            #expect(!playback.isFront)
            #expect(playback.isPlaying, "the stream plays on behind the guide")
        }

        @Test
        func `stopping clears it, and there is nothing to bring forward`() {
            let playback = EmbeddedPlayback()
            playback.play(target("Arte"))

            playback.stop()
            playback.bringToFront()

            #expect(!playback.isPlaying)
            #expect(!playback.isFront)
        }
    }
#endif
