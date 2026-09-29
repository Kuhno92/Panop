import PanopCore

/// What an engine has been asked to play.
public struct PlaybackItem: Sendable, Equatable {
    public var url: String
    public var title: String?
    /// Some providers reject requests without a matching User-Agent or Referer.
    public var headers: [String: String]
    public var userAgent: String?
    /// Resume point, in seconds.
    ///
    /// Passed at load time rather than applied as a seek afterwards. Seeking an
    /// in-flight connection makes some providers drop the stream entirely.
    public var startPosition: Double?
    public var mediaKind: MediaKind

    public init(
        url: String,
        title: String? = nil,
        headers: [String: String] = [:],
        userAgent: String? = nil,
        startPosition: Double? = nil,
        mediaKind: MediaKind = .unknown
    ) {
        self.url = url
        self.title = title
        self.headers = headers
        self.userAgent = userAgent
        self.startPosition = startPosition
        self.mediaKind = mediaKind
    }
}

public enum PlaybackState: String, Sendable, Equatable, Codable {
    case idle
    case opening
    case buffering
    case playing
    case paused
    case ended
    case failed
}

/// An audio or subtitle track.
public struct TrackDescriptor: Sendable, Equatable, Identifiable, Hashable {
    /// Engine-specific identifier. Opaque; never parse it.
    public var id: String
    public var label: String
    /// ISO language code where the engine reports one.
    public var languageCode: String?
    public var isForced: Bool

    public init(id: String, label: String, languageCode: String? = nil, isForced: Bool = false) {
        self.id = id
        self.label = label
        self.languageCode = languageCode
        self.isForced = isForced
    }
}

/// What an engine reports back.
///
/// Engines must surface failure as an event. Silence is not an acceptable
/// failure mode: a stream that never starts and never errors is indistinguishable
/// from one still buffering, and the fallback coordinator cannot act on it.
public enum PlaybackEvent: Sendable, Equatable {
    case stateChanged(PlaybackState)
    case ready(duration: Double?)
    case positionChanged(seconds: Double)
    /// Playback stopped progressing. The coordinator decides whether to wait,
    /// reconnect, or fall through to the next engine.
    case stalled(seconds: Double)
    case tracksChanged(audio: [TrackDescriptor], subtitle: [TrackDescriptor])
    case failed(PlaybackError)
    case ended
}

public struct PlaybackError: Error, Sendable, Equatable, Hashable {
    public enum Code: String, Sendable, Codable {
        /// The engine could not open the URL at all.
        case openFailed
        case network
        /// The engine understood the container or codec and refused it. This is
        /// the signal to try the next engine rather than retry this one.
        case unsupportedFormat
        case decodeFailed
        case cancelled
        case internalError
    }

    public var code: Code
    public var message: String?

    public init(code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// Whether retrying the same engine could plausibly help.
    ///
    /// Format rejections never recover, so retrying wastes the user's time; the
    /// coordinator should move to the next engine instead.
    public var isRetryable: Bool {
        switch code {
        case .network, .openFailed: true
        case .unsupportedFormat, .decodeFailed, .cancelled, .internalError: false
        }
    }
}
