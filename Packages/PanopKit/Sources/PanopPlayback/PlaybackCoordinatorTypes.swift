import Foundation
import PanopCore

/// How patient the coordinator is, and how hard it tries before moving on.
///
/// Defaults suit live IPTV: a channel that has not produced a picture in about
/// fifteen seconds is not going to, and every extra second of retrying is a
/// second the user stares at a spinner. Tests pass tiny values.
public struct PlaybackPolicy: Sendable, Equatable {
    /// How long `load` may take before it counts as a network failure.
    public var openTimeout: Duration
    /// How long after a successful load the first frame may take.
    public var startTimeout: Duration
    /// How long playback may sit stalled or buffering before reconnecting.
    public var stallTolerance: Duration
    /// Extra attempts per engine when opening fails in a way that could recover.
    public var maxOpenRetries: Int
    /// Mid-playback reconnects per engine before falling through to the next.
    public var maxReconnects: Int
    /// Delays before retry number 1, 2, 3, and so on. The last repeats.
    public var backoff: [Duration]
    /// Playing this long without a further failure refills the reconnect budget.
    public var reconnectBudgetResetAfter: Duration

    public init(
        openTimeout: Duration = .seconds(12),
        startTimeout: Duration = .seconds(15),
        stallTolerance: Duration = .seconds(8),
        maxOpenRetries: Int = 1,
        maxReconnects: Int = 4,
        backoff: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)],
        reconnectBudgetResetAfter: Duration = .seconds(60)
    ) {
        self.openTimeout = openTimeout
        self.startTimeout = startTimeout
        self.stallTolerance = stallTolerance
        self.maxOpenRetries = maxOpenRetries
        self.maxReconnects = maxReconnects
        self.backoff = backoff
        self.reconnectBudgetResetAfter = reconnectBudgetResetAfter
    }

    /// The wait before retry number `attempt` (1-based).
    func delay(forAttempt attempt: Int) -> Duration {
        guard !backoff.isEmpty else { return .zero }
        return backoff[Swift.min(Swift.max(attempt - 1, 0), backoff.count - 1)]
    }
}

/// What to play. The item is chosen **per engine**, because the right URL can
/// depend on who is playing it: an Xtream live channel is HLS for AVPlayer, which
/// cannot read a raw transport stream, and `.ts` for the FFmpeg-based engines.
public struct PlaybackRequest: Sendable {
    public var mediaKind: MediaKind
    public var item: @Sendable (PlaybackEngineKind) -> PlaybackItem

    public init(mediaKind: MediaKind, item: @escaping @Sendable (PlaybackEngineKind) -> PlaybackItem) {
        self.mediaKind = mediaKind
        self.item = item
    }

    /// The same item for every engine.
    public init(_ item: PlaybackItem) {
        self.init(mediaKind: item.mediaKind) { _ in item }
    }
}

/// One thing the coordinator tried, kept so a total failure can say what was
/// attempted and why each attempt ended.
public struct PlaybackAttempt: Sendable, Equatable {
    public var engine: PlaybackEngineKind
    /// Nil when the engine is not available in this build and was skipped.
    public var error: PlaybackError?

    public init(engine: PlaybackEngineKind, error: PlaybackError?) {
        self.engine = engine
        self.error = error
    }
}

public struct PlaybackFailure: Sendable, Equatable {
    public var attempts: [PlaybackAttempt]

    public init(attempts: [PlaybackAttempt]) {
        self.attempts = attempts
    }

    /// The last real error, which is usually the most useful one to show.
    public var lastError: PlaybackError? {
        attempts.reversed().lazy.compactMap(\.error).first
    }
}

public enum PlaybackStatus: Sendable, Equatable {
    case idle
    case connecting(PlaybackEngineKind)
    case buffering(PlaybackEngineKind)
    case playing(PlaybackEngineKind)
    case paused(PlaybackEngineKind)
    /// The connection dropped and the coordinator is bringing it back.
    case reconnecting(PlaybackEngineKind)
    case ended
    case failed(PlaybackFailure)
}

/// Things the UI may want to tell the user, beyond the status itself.
public enum PlaybackNotice: Sendable, Equatable {
    /// Moved to another engine, and why. Never silent.
    case fellBack(from: PlaybackEngineKind, to: PlaybackEngineKind, reason: PlaybackError)
    case reconnecting(engine: PlaybackEngineKind, reason: PlaybackError)
}

public enum PlaybackCoordinatorEvent: Sendable, Equatable {
    case status(PlaybackStatus)
    case notice(PlaybackNotice)
    /// Time from the request to the first frame. The number channel zapping is
    /// judged on.
    case joined(engine: PlaybackEngineKind, seconds: Double)
    case position(seconds: Double)
    /// The tracks the current engine offers. They arrive after the first frame and can
    /// change, and a new engine after a fallback starts with its own.
    case tracks(audio: [TrackDescriptor], subtitle: [TrackDescriptor])
}

public extension PlaybackEngineKind {
    /// The order to try engines in: the user's choice first, then the default
    /// order for the rest.
    static func order(preferred: PlaybackEngineKind?) -> [PlaybackEngineKind] {
        let rest = defaultPriority
        guard let preferred, rest.contains(preferred) else { return rest }
        return [preferred] + rest.filter { $0 != preferred }
    }

    /// Containers and playlists Apple's player reads. Anything else (Matroska above all, and raw transport streams) it
    /// refuses outright, which a real provider's films and live channels confirmed: AVPlayer failed every MKV and every
    /// raw MPEG-TS channel, and played every MP4.
    private static let appleContainers: Set<String> = ["mp4", "m4v", "mov", "m3u8", "m3u", "mp3", "m4a", "aac"]

    /// The default order for one request, from what each engine was measured to play on a real provider
    /// (docs/engine-matrix.md).
    ///
    /// - **Not an Apple container** (MKV films and episodes, raw MPEG-TS live): AVPlayer would refuse it, so it goes
    /// last
    ///   rather than first.
    /// - **AetherEngine comes after VLC.** It was only about half a second faster to a moving picture on films, and the
    /// same
    ///   deinterlacing code that crashed it on live channels runs for any interlaced source.
    /// - **KSPlayer comes after VLC and before AetherEngine.** It played all 17 streams tried on a real provider
    ///   (live raw TS, the `.m3u8` address that returns raw TS, MKV and MP4 films, MKV episodes), which the others did
    ///   not: it is never the fastest to a moving picture (live 2.8 to 4.8 s, MKV 1.8 to 4.1 s, MP4 2.3 to 11 s) but it
    ///   did not fail or crash once, and AetherEngine did.
    /// - **Live TV never offers AetherEngine on its own.** Version 7.27.2 crashed the whole process, inside its own
    ///   deinterlacing filter, on a real provider's live channels, with both of its deinterlacers. A person can still
    ///   choose it.
    /// - **Everything else**: the general order, system integration first.
    static func defaultPriority(for request: PlaybackRequest) -> [PlaybackEngineKind] {
        let address = request.item(.vlcKit).url
        let container = URL(string: address)?.pathExtension.lowercased() ?? ""
        let readByApple = container.isEmpty || appleContainers.contains(container)
        var order: [PlaybackEngineKind] = readByApple
            ? [.avPlayer, .lumeEngine, .vlcKit, .ksPlayer, .aetherEngine]
            : [.lumeEngine, .vlcKit, .ksPlayer, .aetherEngine, .avPlayer]
        if request.mediaKind == .live {
            order.removeAll { $0 == .aetherEngine }
        }
        return order.filter { available.contains($0) }
    }

    /// The user's choice first, then the default order for this request.
    static func order(preferred: PlaybackEngineKind?, for request: PlaybackRequest) -> [PlaybackEngineKind] {
        let rest = defaultPriority(for: request)
        guard let preferred, available.contains(preferred) else { return rest }
        return [preferred] + rest.filter { $0 != preferred }
    }
}
