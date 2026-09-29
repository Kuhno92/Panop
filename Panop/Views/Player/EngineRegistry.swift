import PanopPlayback

/// Which engines this build can actually run.
///
/// `PlaybackEngineKind.available` lists every engine that is *linked or
/// planned*; this lists the ones with a working adapter today. The coordinator
/// skips a kind that has none, and the settings picker offers only these, so
/// nothing can be selected that cannot play.
enum EngineRegistry {
    static func make(_ kind: PlaybackEngineKind) -> (any PlaybackEngine)? {
        switch kind {
        case .avPlayer: AVPlayerEngine()
        case .vlcKit, .lumeEngine, .ksPlayer: nil
        }
    }

    nonisolated static func isImplemented(_ kind: PlaybackEngineKind) -> Bool {
        switch kind {
        case .avPlayer: true
        case .vlcKit, .lumeEngine, .ksPlayer: false
        }
    }

    /// Engines to offer in settings.
    nonisolated static var selectable: [PlaybackEngineKind] {
        PlaybackEngineKind.available.filter(isImplemented)
    }
}
