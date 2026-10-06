import PanopPlayback

/// Which engines this build can actually run.
///
/// `PlaybackEngineKind.available` lists every engine that is *linked or
/// planned*; this lists the ones with a working adapter today. The coordinator
/// skips a kind that has none, and the settings picker offers only these, so
/// nothing can be selected that cannot play.
enum EngineRegistry {
    static func make(_ kind: PlaybackEngineKind) -> (any PlaybackEngine)? {
        #if DEBUG
            if UITestMode.isActive {
                guard kind == .avPlayer else { return nil }
                return UITestEngine()
            }
        #endif
        return switch kind {
        case .avPlayer: AVPlayerEngine()
        case .vlcKit: VLCEngine()
        case .lumeEngine: LumePlaybackEngine()
        // Nil if the engine cannot start (its FFmpeg could not be set up): the coordinator then skips it.
        case .aetherEngine: AetherPlaybackEngine()
        case .ksPlayer:
            #if os(iOS) || os(tvOS)
                KSPlayerEngine()
            #else
                nil
            #endif
        }
    }

    nonisolated static func isImplemented(_ kind: PlaybackEngineKind) -> Bool {
        switch kind {
        case .avPlayer, .vlcKit, .lumeEngine, .aetherEngine: true
        case .ksPlayer:
            #if os(iOS) || os(tvOS)
                true
            #else
                false
            #endif
        }
    }

    /// Engines to offer in settings.
    nonisolated static var selectable: [PlaybackEngineKind] {
        PlaybackEngineKind.available.filter(isImplemented)
    }
}
