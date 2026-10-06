@testable import PanopPlayback
import Testing

@Suite("PlaybackEngineKind")
struct PlaybackEngineKindTests {
    /// KSPlayer is linked (iOS, tvOS), so it is offered like the others; the app's registry hides it where
    /// there is no adapter (macOS). See docs/adr/0010.
    @Test
    func `available includes every engine`() {
        #expect(PlaybackEngineKind.available.contains(.ksPlayer))
        #expect(PlaybackEngineKind.available.count == 5)
    }

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
