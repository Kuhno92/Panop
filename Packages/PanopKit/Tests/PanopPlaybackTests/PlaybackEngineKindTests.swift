@testable import PanopPlayback
import Testing

@Suite("PlaybackEngineKind")
struct PlaybackEngineKindTests {
    /// This is a licensing invariant, not a preference. KSPlayer is GPL-3.0 and
    /// its dependency is deliberately not linked, so anything that offers it to
    /// the user would select an engine that cannot play. See docs/adr/0002.
    @Test
    func `available excludes KSPlayer unless the build opts in`() {
        #if PANOP_ENABLE_KSPLAYER
            #expect(PlaybackEngineKind.available.contains(.ksPlayer))
        #else
            #expect(!PlaybackEngineKind.available.contains(.ksPlayer))
            #expect(PlaybackEngineKind.available.count == 3)
        #endif
    }

    /// The case still exists so the adapter can compile under the flag.
    @Test
    func `the KSPlayer case is still declared`() {
        #expect(PlaybackEngineKind.allCases.contains(.ksPlayer))
    }

    @Test
    func `default priority offers exactly the available engines`() {
        #expect(Set(PlaybackEngineKind.defaultPriority) == Set(PlaybackEngineKind.available))
        #expect(PlaybackEngineKind.defaultPriority.count == PlaybackEngineKind.available.count)
    }

    /// AVPlayer leads because when it can open a stream it gives PiP, AirPlay
    /// and the best battery life. The FFmpeg-backed engines exist to catch what
    /// it cannot open.
    @Test
    func `AVPlayer is tried first`() {
        #expect(PlaybackEngineKind.defaultPriority.first == .avPlayer)
    }

    /// Raw values are persisted in user settings. Renaming one silently resets
    /// every existing user's engine choice back to the default.
    @Test
    func `raw values are stable`() {
        #expect(PlaybackEngineKind.avPlayer.rawValue == "avPlayer")
        #expect(PlaybackEngineKind.vlcKit.rawValue == "vlcKit")
        #expect(PlaybackEngineKind.lumeEngine.rawValue == "lumeEngine")
        #expect(PlaybackEngineKind.ksPlayer.rawValue == "ksPlayer")
    }

    @Test
    func `every engine has a display name`() {
        for kind in PlaybackEngineKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }
}

@Suite("PlaybackError")
struct PlaybackErrorTests {
    /// The coordinator uses this to decide between retrying the same engine and
    /// falling through to the next one. A format rejection never recovers, so
    /// retrying it only wastes the viewer's time.
    @Test(
        arguments: [
            (PlaybackError.Code.network, true),
            (.openFailed, true),
            (.unsupportedFormat, false),
            (.decodeFailed, false),
            (.cancelled, false),
            (.internalError, false)
        ]
    )
    func `retryable only for transient failures`(code: PlaybackError.Code, expected: Bool) {
        #expect(PlaybackError(code: code).isRetryable == expected)
    }
}
