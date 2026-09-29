import Foundation
import PanopCore
import PanopPlayback

/// An engine whose behaviour is scripted, and which records what it was asked.
@MainActor
final class FakeEngine: PlaybackEngine {
    enum LoadBehavior {
        case succeed
        case fail(PlaybackError)
        /// Never finishes on its own, but ends when cancelled.
        case hang
    }

    struct Script {
        var load = LoadBehavior.succeed
        /// Whether `play()` produces a first frame. False simulates a stream
        /// that opens and then never shows anything.
        var startsPlaying = true
        var duration: Double?

        static let ok = Script()
        static func fail(_ code: PlaybackError.Code) -> Script {
            Script(load: .fail(PlaybackError(code: code, message: "scripted \(code.rawValue)")))
        }
    }

    static var kind: PlaybackEngineKind {
        .avPlayer
    }

    let events: AsyncStream<PlaybackEvent>
    private let output: AsyncStream<PlaybackEvent>.Continuation
    private let script: Script

    private(set) var state = PlaybackState.idle
    private(set) var position: Double?
    var duration: Double? {
        script.duration
    }

    let audioTracks: [TrackDescriptor] = []
    let subtitleTracks: [TrackDescriptor] = []

    private(set) var loadedItems: [PlaybackItem] = []
    private(set) var playCalls = 0
    private(set) var pauseCalls = 0
    private(set) var seeks: [Double] = []
    private(set) var stopCalls = 0

    init(script: Script) {
        self.script = script
        (events, output) = AsyncStream.makeStream()
    }

    func load(_ item: PlaybackItem) async throws {
        loadedItems.append(item)
        state = .opening
        switch script.load {
        case .succeed:
            state = .buffering
            output.yield(.ready(duration: script.duration))
        case let .fail(error):
            state = .failed
            throw error
        case .hang:
            try await Task.sleep(for: .seconds(3600))
        }
    }

    func play() {
        playCalls += 1
        if script.startsPlaying {
            state = .playing
            output.yield(.stateChanged(.playing))
        }
    }

    func pause() {
        pauseCalls += 1
        state = .paused
    }

    func seek(to seconds: Double) {
        seeks.append(seconds)
    }

    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    func stop() async {
        stopCalls += 1
        output.finish()
    }

    /// Simulates the engine reporting something mid-playback.
    func report(_ event: PlaybackEvent) {
        output.yield(event)
    }
}

/// Hands out engines from per-kind scripts, in order, and remembers them.
@MainActor
final class EngineFactory {
    private var scripts: [PlaybackEngineKind: [FakeEngine.Script]]
    private var unavailable: Set<PlaybackEngineKind>
    private(set) var created: [(kind: PlaybackEngineKind, engine: FakeEngine)] = []

    init(_ scripts: [PlaybackEngineKind: [FakeEngine.Script]], unavailable: Set<PlaybackEngineKind> = []) {
        self.scripts = scripts
        self.unavailable = unavailable
    }

    func make(_ kind: PlaybackEngineKind) -> (any PlaybackEngine)? {
        guard !unavailable.contains(kind) else { return nil }
        var queue = scripts[kind] ?? [.ok]
        // Scripts run out to the last one, so "always fails" is one entry.
        let script = queue.count > 1 ? queue.removeFirst() : (queue.first ?? .ok)
        scripts[kind] = queue
        let engine = FakeEngine(script: script)
        created.append((kind, engine))
        return engine
    }

    func engines(_ kind: PlaybackEngineKind) -> [FakeEngine] {
        created.filter { $0.kind == kind }.map(\.engine)
    }

    var lastEngine: FakeEngine? {
        created.last?.engine
    }
}

/// A sleeper that returns at once for short waits and hangs (until cancelled)
/// for long ones. Tests pick which timeout fires by choosing its duration.
final class TestSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private let onceKinds: Set<Duration>
    private var stillToFire: Set<Duration>

    /// - Parameter firesOnce: durations that return immediately the first time
    ///   they are requested and hang afterwards. For a timeout that should hit
    ///   the first engine and leave the fallback alone.
    init(firesOnce: Set<Duration> = []) {
        onceKinds = firesOnce
        stillToFire = firesOnce
    }

    var durations: [Duration] {
        lock.withLock { recorded }
    }

    func sleep(_ duration: Duration) async throws {
        let returnsNow = lock.withLock {
            if stillToFire.remove(duration) != nil {
                return true
            }
            return duration < .seconds(100) && !onceKinds.contains(duration)
        }
        guard returnsNow else {
            try await Task.sleep(for: .seconds(3600))
            return
        }
        lock.withLock { recorded.append(duration) }
    }
}

/// A policy where nothing times out unless a test asks it to, and retries are
/// instant.
func testPolicy(
    open: Duration = .seconds(1000),
    start: Duration = .seconds(1000),
    stall: Duration = .seconds(1000),
    openRetries: Int = 1,
    reconnects: Int = 2,
    resetAfter: Duration = .seconds(1000)
) -> PlaybackPolicy {
    PlaybackPolicy(
        openTimeout: open,
        startTimeout: start,
        stallTolerance: stall,
        maxOpenRetries: openRetries,
        maxReconnects: reconnects,
        backoff: [.milliseconds(1), .milliseconds(2), .milliseconds(3)],
        reconnectBudgetResetAfter: resetAfter
    )
}

/// Records a coordinator's events in the background and lets a test wait for one.
@MainActor
final class EventLog {
    private(set) var events: [PlaybackCoordinatorEvent] = []
    private var collector: Task<Void, Never>?

    init(_ coordinator: PlaybackCoordinator) {
        let stream = coordinator.events
        collector = Task { [weak self] in
            for await event in stream {
                self?.events.append(event)
            }
        }
    }

    deinit {
        collector?.cancel()
    }

    /// Polls until an event matches, and returns it, or nil after three seconds.
    /// Polling rather than blocking on the stream, so a missing event fails the
    /// test instead of hanging it.
    @discardableResult
    func wait(for matches: (PlaybackCoordinatorEvent) -> Bool) async -> PlaybackCoordinatorEvent? {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let found = events.first(where: matches) {
                return found
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    /// Gives already-scheduled work a chance to run, then returns. For asserting
    /// that something did *not* happen.
    func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(30))
    }

    func waitForStatus(_ status: PlaybackStatus) async -> Bool {
        await wait { $0 == .status(status) } != nil
    }

    var notices: [PlaybackNotice] {
        events.compactMap {
            if case let .notice(notice) = $0 {
                notice
            } else {
                nil
            }
        }
    }

    var statuses: [PlaybackStatus] {
        events.compactMap {
            if case let .status(status) = $0 {
                status
            } else {
                nil
            }
        }
    }
}
