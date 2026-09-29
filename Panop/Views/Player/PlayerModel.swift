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

    private let coordinator: PlaybackCoordinator
    private let request: PlaybackRequest
    private var listener: Task<Void, Never>?

    init(
        title: String,
        request: PlaybackRequest,
        preferred: PlaybackEngineKind?,
        makeEngine: @escaping PlaybackCoordinator.EngineFactory = { EngineRegistry.make($0) }
    ) {
        self.title = title
        self.request = request
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
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        await coordinator.stop()
        engine = nil
        status = .idle
    }

    private func apply(_ event: PlaybackCoordinatorEvent) {
        switch event {
        case let .status(new):
            status = new
            engine = coordinator.activeEngine
            // A notice is about the last change of engine; it goes once playing starts.
            if case .playing = new {
                scheduleNoticeClear()
            }
        case let .notice(notice):
            self.notice = PlaybackMessages.text(for: notice)
        case let .joined(_, seconds):
            joinTime = seconds
        case .position:
            break
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
