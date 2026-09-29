/// What every playback engine adapter implements.
///
/// Deliberately contains no view type and no media-framework import, which is
/// what keeps this target portable. Presenting video is the app's concern: each
/// adapter exposes its own surface on the Apple side, and a future Android or
/// desktop UI would do the same, while everything above this protocol stays
/// shared.
///
/// Adapters live in the app target (`Panop/Views/Player/`), not here.
///
/// ## Adapters do not set policy
///
/// An engine reports what happened and nothing more. Reconnect, backoff and
/// falling through to another engine belong to the coordinator above, because
/// four engines report failure four different ways and duplicated policy drifts
/// apart. An adapter that retries on its own also hides the failure from the
/// coordinator, which then cannot fall back.
@MainActor
public protocol PlaybackEngine: AnyObject {
    /// Which engine this is. Used for settings, diagnostics and fallback order.
    static var kind: PlaybackEngineKind { get }

    /// Everything the engine reports. Finishes when the engine is torn down.
    var events: AsyncStream<PlaybackEvent> { get }

    var state: PlaybackState { get }
    /// Current position in seconds, or `nil` before playback starts.
    var position: Double? { get }
    /// Total duration, or `nil` for live streams and before it is known.
    var duration: Double? { get }

    var audioTracks: [TrackDescriptor] { get }
    var subtitleTracks: [TrackDescriptor] { get }

    /// Opens an item and prepares it for playback.
    ///
    /// Throws a ``PlaybackError`` the coordinator can act on. In particular,
    /// `.unsupportedFormat` means "try a different engine", not "retry me".
    func load(_ item: PlaybackItem) async throws

    func play()
    func pause()
    func seek(to seconds: Double)

    /// Selects a track, or passes `nil` to disable subtitles.
    func selectAudioTrack(id: String?)
    func selectSubtitleTrack(id: String?)

    /// Tears the engine down and releases its resources.
    ///
    /// Some engines cannot reopen a session, so switching channels means a full
    /// teardown and a fresh instance rather than loading a second item.
    func stop() async
}
