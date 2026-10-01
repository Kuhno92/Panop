import Foundation
import Observation
import PanopPlayback

/// Observable state for the player screen, driven by a `PlaybackCoordinator`.
///
/// The coordinator is deliberately plain (it is portable), so this is the layer
/// that turns its event stream into something SwiftUI can watch.
@MainActor
@Observable
final class PlayerModel {
    let title: String
    private(set) var status = PlaybackStatus.idle
    /// A short note for the user, such as "switched to another player".
    private(set) var notice: String?
    /// Seconds from asking to play until the first frame.
    private(set) var joinTime: Double?
    /// The engine to draw, or nil between engines.
    private(set) var engine: (any PlaybackEngine)?

    private(set) var position: Double = 0
    /// Nil for a live stream, and before the engine knows.
    private(set) var duration: Double?
    private(set) var audioTracks: [TrackDescriptor] = []
    private(set) var subtitleTracks: [TrackDescriptor] = []
    /// What the user picked. Engines do not report their own choice, and nil is the
    /// stream's default for audio and "off" for subtitles.
    private(set) var selectedAudioID: String?
    private(set) var selectedSubtitleID: String?
    private(set) var controlsVisible = true
    /// Set while something in the controls has focus. The controls do not hide under it.
    private(set) var controlsHeld = false

    private let coordinator: PlaybackCoordinator
    private let request: PlaybackRequest
    private var listener: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// How long the controls stay up once playing with nothing touched.
    private let controlsTimeout: Duration
    private let nowPlaying: (any NowPlayingPublishing)?
    /// Told how far a film or episode has got, now and then and when it stops. Not called for
    /// a live channel, which has nowhere to resume.
    private let onProgress: ((_ position: Double, _ duration: Double?) -> Void)?
    private var lastReportedProgress: Double

    init(
        title: String,
        request: PlaybackRequest,
        preferred: PlaybackEngineKind?,
        controlsTimeout: Duration = .seconds(4),
        nowPlaying: (any NowPlayingPublishing)? = nil,
        startPosition: Double = 0,
        onProgress: ((_ position: Double, _ duration: Double?) -> Void)? = nil,
        makeEngine: @escaping PlaybackCoordinator.EngineFactory = { EngineRegistry.make($0) }
    ) {
        self.title = title
        self.request = request
        self.controlsTimeout = controlsTimeout
        self.nowPlaying = nowPlaying
        self.onProgress = onProgress
        lastReportedProgress = startPosition
        position = startPosition
        coordinator = PlaybackCoordinator(
            priority: PlaybackEngineKind.order(preferred: preferred),
            makeEngine: makeEngine
        )
    }

    var engineName: String? {
        coordinator.activeKind?.displayName
    }

    var isPaused: Bool {
        if case .paused = status {
            true
        } else {
            false
        }
    }

    /// Whether to show a spinner: anything between asking and seeing a picture.
    var isWorking: Bool {
        switch status {
        case .connecting, .buffering, .reconnecting: true
        default: false
        }
    }

    /// Whether the stream can be scrubbed: video on demand, not a live channel.
    var canSeek: Bool {
        duration != nil
    }

    /// AirPlay is the system's, so only the engine that plays through AVFoundation can
    /// send its video there. Not offered on tvOS.
    var supportsAirPlay: Bool {
        #if os(tvOS)
            false
        #else
            engine is AVPlayerEngine
        #endif
    }

    var supportsPictureInPicture: Bool {
        (engine as? AVPlayerEngine)?.supportsPictureInPicture ?? false
    }

    func togglePictureInPicture() {
        (engine as? AVPlayerEngine)?.togglePictureInPicture()
    }

    /// Controls stay up while paused or failed: there is nothing to see behind them.
    var showsControls: Bool {
        controlsVisible || isPaused || failureText != nil
    }

    var failureText: String? {
        if case let .failed(failure) = status {
            PlaybackMessages.text(for: failure)
        } else {
            nil
        }
    }

    func start() {
        guard listener == nil else { return }
        let events = coordinator.events
        nowPlaying?.begin { [weak self] command in self?.handle(command) }
        listener = Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
        coordinator.play(request)
    }

    func play() {
        if isPaused {
            togglePause()
        }
    }

    func pause() {
        if !isPaused {
            togglePause()
        }
    }

    /// A command from the system's media controls.
    func handle(_ command: RemoteCommand) {
        switch command {
        case .play: play()
        case .pause: pause()
        case .toggle: togglePause()
        case let .skip(seconds): skip(by: seconds)
        case let .seek(seconds): seek(to: seconds)
        }
    }

    func togglePause() {
        if isPaused {
            coordinator.resume()
        } else {
            coordinator.pause()
        }
        showControls()
    }

    func seek(to seconds: Double) {
        let target = clamp(seconds)
        coordinator.seek(to: target)
        position = target
        showControls()
        publishNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    /// Passing nil returns to the stream's default track.
    func selectAudio(id: String?) {
        selectedAudioID = id
        coordinator.selectAudioTrack(id: id)
        showControls()
    }

    /// Passing nil turns subtitles off.
    func selectSubtitle(id: String?) {
        selectedSubtitleID = id
        coordinator.selectSubtitleTrack(id: id)
        showControls()
    }

    func toggleControls() {
        if controlsVisible {
            hideTask?.cancel()
            controlsVisible = false
        } else {
            showControls()
        }
    }

    /// Brings the controls up and starts the countdown to hide them again.
    func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        guard !controlsHeld else { return }
        hideTask = Task { [weak self, controlsTimeout] in
            try? await Task.sleep(for: controlsTimeout)
            guard !Task.isCancelled else { return }
            self?.controlsVisible = false
        }
    }

    /// Keeps the controls up while a person is working them, then starts the countdown
    /// from the moment they let go. On Apple TV the remote moves focus between controls,
    /// and a bar that vanished under it would take the focus with it.
    func holdControls(_ held: Bool) {
        guard held != controlsHeld else { return }
        controlsHeld = held
        if held {
            hideTask?.cancel()
            controlsVisible = true
        } else {
            showControls()
        }
    }

    private func clamp(_ seconds: Double) -> Double {
        let lower = max(0, seconds)
        return duration.map { min(lower, $0) } ?? lower
    }

    /// How often progress is handed on while playing. A write per position tick would be a write
    /// a second for the length of a film.
    static let progressInterval = 15.0

    private func reportProgressIfDue(at seconds: Double) {
        guard duration != nil, abs(seconds - lastReportedProgress) >= Self.progressInterval else { return }
        lastReportedProgress = seconds
        onProgress?(seconds, duration)
    }

    func stop() async {
        // Where it was left, so the next play can pick up there. Only once something has played.
        if duration != nil, position > 0 {
            onProgress?(position, duration)
        }
        listener?.cancel()
        listener = nil
        hideTask?.cancel()
        hideTask = nil
        await coordinator.stop()
        nowPlaying?.end()
        engine = nil
        status = .idle
    }

    private func apply(_ event: PlaybackCoordinatorEvent) {
        switch event {
        case let .status(new):
            status = new
            engine = coordinator.activeEngine
            duration = engine?.duration
            if case .connecting = new {
                // A new engine starts with its own tracks and none of the old choices.
                audioTracks = []
                subtitleTracks = []
                selectedAudioID = nil
                selectedSubtitleID = nil
            }
            publishNowPlaying()
            // A notice is about the last change of engine; it goes once playing starts.
            if case .playing = new {
                scheduleNoticeClear()
                // Start the countdown once, at the first picture. Not on every rebuffer,
                // which would bring the controls back up each time.
                if hideTask == nil {
                    showControls()
                }
            }
        case let .notice(notice):
            self.notice = PlaybackMessages.text(for: notice)
        case let .joined(_, seconds):
            joinTime = seconds
        case let .position(seconds):
            position = seconds
            let known = duration
            duration = coordinator.activeEngine?.duration
            reportProgressIfDue(at: seconds)
            if duration != known {
                publishNowPlaying()
            }
        case let .tracks(audio, subtitle):
            audioTracks = audio
            subtitleTracks = subtitle
        }
    }

    private func publishNowPlaying() {
        guard let nowPlaying else { return }
        switch status {
        case .idle, .failed, .ended:
            return
        default:
            break
        }
        let playing = switch status {
        case .playing, .buffering: true
        default: false
        }
        nowPlaying.update(NowPlayingInfo(title: title, position: position, duration: duration, isPlaying: playing))
    }

    private func scheduleNoticeClear() {
        guard notice != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.notice = nil
        }
    }
}
