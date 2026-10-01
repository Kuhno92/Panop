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

    private let coordinator: PlaybackCoordinator
    private let request: PlaybackRequest
    private var listener: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// How long the controls stay up once playing with nothing touched.
    private let controlsTimeout: Duration

    init(
        title: String,
        request: PlaybackRequest,
        preferred: PlaybackEngineKind?,
        controlsTimeout: Duration = .seconds(4),
        makeEngine: @escaping PlaybackCoordinator.EngineFactory = { EngineRegistry.make($0) }
    ) {
        self.title = title
        self.request = request
        self.controlsTimeout = controlsTimeout
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
        listener = Task { [weak self] in
            for await event in events {
                self?.apply(event)
            }
        }
        coordinator.play(request)
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
        hideTask = Task { [weak self, controlsTimeout] in
            try? await Task.sleep(for: controlsTimeout)
            guard !Task.isCancelled else { return }
            self?.controlsVisible = false
        }
    }

    private func clamp(_ seconds: Double) -> Double {
        let lower = max(0, seconds)
        return duration.map { min(lower, $0) } ?? lower
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        hideTask?.cancel()
        hideTask = nil
        await coordinator.stop()
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
            duration = coordinator.activeEngine?.duration
        case let .tracks(audio, subtitle):
            audioTracks = audio
            subtitleTracks = subtitle
        }
    }

    private func scheduleNoticeClear() {
        guard notice != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.notice = nil
        }
    }
}
