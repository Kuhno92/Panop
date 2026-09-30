import Foundation
import PanopCore
import PanopPlayback
import VLCKit

#if os(macOS)
    import AppKit

    typealias PlatformView = NSView
#else
    import UIKit

    typealias PlatformView = UIView
#endif

/// The view libVLC draws into. It reports when it enters or leaves a window, because
/// libVLC's OpenGL video output crashes the whole process if it renders into a view
/// that is not on screen (an assertion in `vout_display_opengl_Prepare`, found by a test
/// that played video into a detached view). `nonisolated` is not needed: a view is
/// main-thread only anyway.
final class VLCSurfaceView: PlatformView {
    /// Called on the main thread with whether the view is now in a window.
    var onWindowChange: ((Bool) -> Void)?

    #if os(macOS)
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window != nil)
        }
    #else
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window != nil)
        }
    #endif
}

/// The VLCKit engine adapter.
///
/// **It reports; it does not decide.** No retry, no backoff, no fallback: those
/// belong to `PlaybackCoordinator` (docs/adr/0002).
///
/// libVLC opens a stream when it is told to play, and has no "opened, not yet
/// playing" state. So `load` prepares the media and returns, and any failure to
/// open arrives as a `.failed` event once `play()` runs. The coordinator handles
/// that the same as a failure inside `load`: its start timeout and its
/// mid-stream recovery both apply.
///
/// libVLC cannot say *why* it failed, only that it did. A failure before the first
/// picture is reported as `.openFailed` and one after it as `.network`; both are
/// retried once by the coordinator and then passed on, which is the right
/// behaviour for an engine of last resort.
@MainActor
final class VLCEngine: PlaybackEngine {
    static var kind: PlaybackEngineKind {
        .vlcKit
    }

    /// Where the video is drawn. Owned by the engine, so each engine instance has a
    /// surface of its own and a view is never in two places.
    let surface = VLCSurfaceView()

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation

    private(set) var state = PlaybackState.idle
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []

    private let holder = VLCPlayerHolder()
    private var player: VLCMediaPlayer {
        holder.player
    }

    private let bridge = VLCDelegateBridge()
    private var hasPlayed = false
    private var wantsPlayback = false
    private var isStopping = false
    private var lastPositionReport = -1.0
    /// Seconds to jump to once the first frame is up. See `load`.
    private var pendingStart: Double?
    /// `play()` was asked for before the surface was on screen; it runs once it is.
    private var pendingPlay = false

    init() {
        (events, output) = AsyncStream.makeStream()
        player.drawable = surface
        // One position report a second is plenty for a scrubber.
        player.timeChangeUpdateInterval = 1
        bridge.owner = self
        player.delegate = bridge
        surface.onWindowChange = { [weak self] attached in
            MainActor.assumeIsolated { self?.surfaceWindowChanged(attached: attached) }
        }
    }

    var position: Double? {
        let milliseconds = player.time.value?.doubleValue ?? 0
        return milliseconds > 0 ? milliseconds / 1000 : nil
    }

    /// Nil for a live stream, where libVLC reports a length of zero.
    var duration: Double? {
        let milliseconds = player.media?.length.value?.doubleValue ?? 0
        return milliseconds > 0 ? milliseconds / 1000 : nil
    }

    // MARK: - Loading

    func load(_ item: PlaybackItem) async throws {
        guard let url = URL(string: item.url), url.scheme != nil, let media = VLCMedia(url: url) else {
            throw PlaybackError(code: .invalidAddress, message: "That is not a valid stream address.")
        }

        // Some providers reject requests without their expected User-Agent or Referer.
        let userAgent = item.userAgent ?? item.headers
            .first { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }?.value
        if let userAgent {
            media.addOption(":http-user-agent=\(userAgent)")
        }
        if let referer = item.headers.first(where: { $0.key.caseInsensitiveCompare("Referer") == .orderedSame })?
            .value
        {
            media.addOption(":http-referrer=\(referer)")
        }
        // A resume position is applied on the first frame, by seeking. The natural
        // way is a `:start-time` media option, and the protocol prefers it (seeking a
        // running IPTV connection can make a provider drop it), but VLCKit 4
        // ignores that option: measured, every spelling behaves as if it were absent.
        // Only video on demand resumes, and a range seek there is ordinary.
        pendingStart = item.startPosition.flatMap { $0 > 0 ? $0 : nil }

        player.media = media
        setState(.opening)
    }

    // MARK: - Controls

    func play() {
        wantsPlayback = true
        // libVLC must not render before the surface is on screen. Waiting costs
        // nothing in the normal case, where the view attaches within a frame or two;
        // if it never does, the coordinator's start timeout takes over.
        guard surface.window != nil else {
            pendingPlay = true
            return
        }
        player.play()
    }

    private func surfaceWindowChanged(attached: Bool) {
        guard !isStopping else { return }
        if attached {
            player.drawable = surface
            if pendingPlay {
                pendingPlay = false
                player.play()
            }
        } else {
            // Leaving the screen mid-playback (the player was dismissed): stop
            // drawing now rather than wait for `stop()` to arrive.
            player.drawable = nil
        }
    }

    func pause() {
        wantsPlayback = false
        guard player.canPause else {
            // A live stream that cannot be paused: stopping is the closest
            // honest thing, and resuming will reopen it at the live edge.
            player.stop()
            setState(.paused)
            return
        }
        player.pause()
        setState(.paused)
    }

    func seek(to seconds: Double) {
        guard player.isSeekable else { return }
        player.time = VLCTime(number: NSNumber(value: Int(seconds * 1000)))
    }

    func selectAudioTrack(id: String?) {
        guard let id, let index = player.audioTracks.firstIndex(where: { $0.trackId == id }) else { return }
        player.selectTrack(at: index, type: .audio)
    }

    func selectSubtitleTrack(id: String?) {
        guard let id, let index = player.textTracks.firstIndex(where: { $0.trackId == id }) else {
            player.deselectAllTextTracks()
            return
        }
        player.selectTrack(at: index, type: .text)
    }

    /// Stops playback and releases the player.
    ///
    /// libVLC's `stop` can take a noticeable moment, and this runs on every
    /// channel change, so it is done off the main thread: the next channel starts
    /// without waiting for the old one to finish tearing down.
    func stop() async {
        isStopping = true
        wantsPlayback = false
        bridge.owner = nil
        player.delegate = nil
        let player = UncheckedBox(player)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                player.value.stop()
                player.value.drawable = nil
                player.value.media = nil
                continuation.resume()
            }
        }
        state = .idle
        output.finish()
    }

    // MARK: - Events from libVLC

    fileprivate func stateChanged(_ new: VLCMediaPlayerState) {
        guard !isStopping else { return }
        switch new {
        case .opening:
            setState(.opening)
        case .playing:
            if !hasPlayed {
                hasPlayed = true
                if let start = pendingStart, player.isSeekable {
                    player.time = VLCTime(number: NSNumber(value: Int(start * 1000)))
                }
                pendingStart = nil
                output.yield(.ready(duration: duration))
                reportTracks()
            }
            setState(.playing)
        case .paused:
            setState(.paused)
        case .stopped:
            // Only news if it was not asked for: a video ran out, or a live
            // connection closed. The coordinator tells those apart by duration.
            if wantsPlayback, hasPlayed {
                setState(.ended)
                output.yield(.ended)
            }
        case .error:
            guard state != .failed else { return }
            setState(.failed)
            output.yield(.failed(PlaybackError(
                code: hasPlayed ? .network : .openFailed,
                message: hasPlayed ? "The stream stopped unexpectedly." : "VLC could not open this stream."
            )))
        case .nothingSpecial, .stopping:
            break
        @unknown default:
            break
        }
    }

    /// `progress` is in [0.0, 1.0], and 1.0 means buffering is complete and playback
    /// can proceed. (Comparing against 100 instead, as this once did, left every
    /// stream stuck in `.buffering` after its first report, which the coordinator
    /// reads as a stall and answers by reconnecting.)
    fileprivate func bufferingChanged(_ progress: Float) {
        guard !isStopping, hasPlayed, wantsPlayback else { return }
        if progress < 1, state == .playing {
            setState(.buffering)
        } else if progress >= 1, state == .buffering {
            setState(.playing)
        }
    }

    fileprivate func timeChanged() {
        guard !isStopping, state == .playing, let seconds = position else { return }
        // libVLC reports several times a second whatever the interval; whole seconds only.
        guard seconds.rounded(.down) != lastPositionReport else { return }
        lastPositionReport = seconds.rounded(.down)
        output.yield(.positionChanged(seconds: seconds))
    }

    fileprivate func tracksChanged() {
        guard !isStopping else { return }
        reportTracks()
    }

    private func reportTracks() {
        audioTracks = player.audioTracks.map(Self.descriptor)
        subtitleTracks = player.textTracks.map(Self.descriptor)
        output.yield(.tracksChanged(audio: audioTracks, subtitle: subtitleTracks))
    }

    nonisolated static func descriptor(_ track: VLCMediaPlayer.Track) -> TrackDescriptor {
        TrackDescriptor(id: track.trackId, label: track.trackName, languageCode: track.language)
    }

    private func setState(_ new: PlaybackState) {
        guard new != state else { return }
        state = new
        output.yield(.stateChanged(new))
    }
}

/// Owns the libVLC player and makes sure its last release never happens on the main thread.
///
/// Releasing a `VLCMediaPlayer` runs libVLC's `vlc_player_Delete`, which joins the
/// player's own thread, and that thread can be waiting on the main queue. Freed on
/// the main thread it deadlocks and the whole app freezes (found by a test host
/// that hung inside `VLCEngine.deinit`). So when this holder goes away, wherever
/// that is, it passes the player to a background queue to stop and release.
///
/// `nonisolated`, and not `final`, for the same modifier-order reason as the bridge.
nonisolated class VLCPlayerHolder {
    let player: VLCMediaPlayer

    init(_ player: VLCMediaPlayer = VLCMediaPlayer()) {
        self.player = player
    }

    deinit {
        let handoff = UncheckedBox(player)
        DispatchQueue.global(qos: .userInitiated).async {
            handoff.value.stop()
            handoff.value.delegate = nil
            handoff.value.drawable = nil
            handoff.value.media = nil
            // `handoff` is released as this closure ends, on this queue.
        }
    }
}

/// Carries libVLC's callbacks onto the main actor, in order.
///
/// libVLC calls its delegate from its own threads. `DispatchQueue.main` preserves
/// the order events were raised in; hopping with unstructured tasks does not
/// promise to.
///
/// `nonisolated`, and not `private`, on purpose. The project defaults every type
/// to the main actor, and Swift then asserts the main queue on entry to each
/// delegate method, which traps the moment libVLC calls one from its own thread.
/// (`nonisolated` cannot be combined with `private` here without SwiftFormat and
/// SwiftLint disagreeing about the modifier order.)
nonisolated class VLCDelegateBridge: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    /// Set and cleared on the main actor only.
    nonisolated(unsafe) weak var owner: VLCEngine?

    private func onMain(_ work: @escaping @MainActor (VLCEngine) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                if let engine = self?.owner {
                    work(engine)
                }
            }
        }
    }

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        onMain { $0.stateChanged(newState) }
    }

    func mediaPlayerBufferingChanged(_ progress: Float) {
        onMain { $0.bufferingChanged(progress) }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        onMain { $0.timeChanged() }
    }

    func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        onMain { $0.tracksChanged() }
    }

    func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        onMain { $0.tracksChanged() }
    }
}

/// Moves a non-`Sendable` reference to another queue when the caller guarantees
/// nothing else touches it meanwhile.
nonisolated class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
