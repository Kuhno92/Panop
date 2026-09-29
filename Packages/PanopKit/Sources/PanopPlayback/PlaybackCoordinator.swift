import Foundation
import PanopCore

/// Owns everything about playing a stream that is not specific to one engine:
/// which engine to try, how long to wait, when to retry, when to give up on an
/// engine and move to the next, and what to tell the user.
///
/// Engine adapters report and nothing more (see ``PlaybackEngine``). All policy
/// lives here, once, so four engines cannot drift into four behaviours.
///
/// **Rules it keeps**
///
/// - A format rejection is never retried. It moves to the next engine.
/// - A recoverable failure is retried with backoff, on a *fresh* engine instance:
///   some engines cannot reopen a session.
/// - Silence is a failure. A load that never returns, a first frame that never
///   arrives and a stall that never clears are all timed out and handled.
/// - Every fallback is reported with its reason. Nothing switches silently.
/// - Events from a superseded session are ignored, so zapping quickly cannot
///   let an old channel's error tear down the new one.
@MainActor
public final class PlaybackCoordinator {
    public typealias EngineFactory = @MainActor (PlaybackEngineKind) -> (any PlaybackEngine)?
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    public private(set) var status = PlaybackStatus.idle
    /// The engine currently playing, for a view to draw. Nil between engines.
    public private(set) var activeEngine: (any PlaybackEngine)?
    public private(set) var activeKind: PlaybackEngineKind?
    public let events: AsyncStream<PlaybackCoordinatorEvent>

    private let output: AsyncStream<PlaybackCoordinatorEvent>.Continuation
    private let policy: PlaybackPolicy
    private let priority: [PlaybackEngineKind]
    private let makeEngine: EngineFactory
    let sleep: Sleeper

    private var generation = 0
    private var request: PlaybackRequest?
    private var driver: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    private var attempts: [PlaybackAttempt] = []
    private var fallbackFrom: (engine: PlaybackEngineKind, reason: PlaybackError)?
    private var priorityIndex = 0
    private var reconnects = 0
    private var lastFailure: ContinuousClock.Instant?
    private var lastPosition: Double?
    private var requestedAt = ContinuousClock.now
    private var hasJoined = false

    /// - Parameters:
    ///   - priority: engines to try, in order. Use ``PlaybackEngineKind/order(preferred:)``.
    ///   - makeEngine: returns a **new** instance, or nil for an engine that is
    ///     not available in this build (which is skipped, not counted as a failure).
    ///   - sleep: injectable so tests do not wait in real time.
    public init(
        policy: PlaybackPolicy = PlaybackPolicy(),
        priority: [PlaybackEngineKind] = PlaybackEngineKind.defaultPriority,
        makeEngine: @escaping EngineFactory,
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.policy = policy
        self.priority = priority
        self.makeEngine = makeEngine
        self.sleep = sleep
        (events, output) = AsyncStream.makeStream()
    }

    // MARK: - Controls

    /// Starts playing, replacing whatever was playing. Returns immediately;
    /// progress arrives through ``events`` and ``status``.
    public func play(_ request: PlaybackRequest) {
        endSession()
        self.request = request
        attempts = []
        fallbackFrom = nil
        priorityIndex = 0
        reconnects = 0
        lastFailure = nil
        lastPosition = nil
        hasJoined = false
        requestedAt = .now

        let token = generation
        driver = Task { await connect(from: 0, resume: nil, generation: token) }
    }

    public func pause() {
        activeEngine?.pause()
    }

    public func resume() {
        activeEngine?.play()
    }

    public func seek(to seconds: Double) {
        activeEngine?.seek(to: seconds)
    }

    /// Stops playback and releases the engine.
    public func stop() async {
        let engine = activeEngine
        endSession()
        setStatus(.idle)
        await engine?.stop()
    }

    // MARK: - Opening and falling through

    /// Tries engines from `start` onwards until one starts playing.
    private func connect(from start: Int, resume: Double?, generation token: Int) async {
        var index = start
        while index < priority.count {
            let kind = priority[index]
            if await openEngine(kind, index: index, resume: resume, generation: token) {
                return
            }
            guard token == generation else { return }
            index += 1
        }
        guard token == generation else { return }
        setStatus(.failed(PlaybackFailure(attempts: attempts)))
    }

    /// Opens one engine, retrying recoverable failures. Returns true once the
    /// engine is playing, or when the session was superseded (nothing left to do).
    private func openEngine(
        _ kind: PlaybackEngineKind,
        index: Int,
        resume: Double?,
        generation token: Int
    ) async -> Bool {
        guard var engine = makeEngine(kind) else {
            attempts.append(PlaybackAttempt(engine: kind, error: nil))
            return false
        }
        var retries = 0
        while token == generation {
            setStatus(.connecting(kind))
            do {
                try await load(engine, item: item(for: kind, resume: resume))
                guard token == generation else {
                    retire(engine)
                    return true
                }
                adopt(engine, kind: kind, index: index, generation: token)
                return true
            } catch {
                retire(engine)
                guard token == generation, !(error is CancellationError) else { return true }

                let failure = (error as? PlaybackError) ?? PlaybackError(code: .internalError, message: "\(error)")
                attempts.append(PlaybackAttempt(engine: kind, error: failure))

                guard failure.isRetryable, retries < policy.maxOpenRetries else {
                    fallbackFrom = (kind, failure)
                    return false
                }
                retries += 1
                emit(.notice(.reconnecting(engine: kind, reason: failure)))
                try? await sleep(policy.delay(forAttempt: retries))
                guard token == generation, let fresh = makeEngine(kind) else { return token != generation }
                engine = fresh
            }
        }
        retire(engine)
        return true
    }

    private func item(for kind: PlaybackEngineKind, resume: Double?) -> PlaybackItem {
        var item = request?.item(kind) ?? PlaybackItem(url: "")
        if let resume {
            item.startPosition = resume
        }
        return item
    }

    /// `load`, raced against the open timeout. An engine that neither succeeds
    /// nor fails is not allowed to hang the coordinator.
    private func load(_ engine: any PlaybackEngine, item: PlaybackItem) async throws {
        let timeout = PlaybackError(code: .network, message: "The stream did not open in time.")
        try await Race.run(
            timeout: policy.openTimeout,
            timeoutError: timeout,
            sleep: sleep
        ) { try await engine.load(item) }
    }

    // MARK: - Playing

    private func adopt(_ engine: any PlaybackEngine, kind: PlaybackEngineKind, index: Int, generation token: Int) {
        activeEngine = engine
        activeKind = kind
        priorityIndex = index

        if let fallback = fallbackFrom {
            emit(.notice(.fellBack(from: fallback.engine, to: kind, reason: fallback.reason)))
            fallbackFrom = nil
        }

        listener = Task { [weak self] in
            for await event in engine.events {
                guard let self, token == generation, activeEngine === engine else { return }
                handle(event, engine: engine, kind: kind, generation: token)
            }
        }
        engine.play()
        setStatus(.buffering(kind))
        armWatchdog(
            policy.startTimeout,
            error: PlaybackError(code: .network, message: "The stream did not start in time.")
        )
    }

    private func handle(
        _ event: PlaybackEvent,
        engine: any PlaybackEngine,
        kind: PlaybackEngineKind,
        generation token: Int
    ) {
        switch event {
        case let .stateChanged(state):
            handleState(state, kind: kind)
        case let .positionChanged(seconds):
            lastPosition = seconds
            emit(.position(seconds: seconds))
            refillReconnectBudgetIfStable()
        case .stalled:
            armWatchdog(policy.stallTolerance, error: PlaybackError(code: .network, message: "Playback stalled."))
        case let .failed(error):
            recover(from: error, generation: token)
        case .ended:
            // A live stream has no end, so an end is a dropped connection.
            if engine.duration == nil {
                recover(
                    from: PlaybackError(code: .network, message: "The stream ended unexpectedly."),
                    generation: token
                )
            } else {
                setStatus(.ended)
            }
        case .ready, .tracksChanged:
            break
        }
    }

    private func handleState(_ state: PlaybackState, kind: PlaybackEngineKind) {
        switch state {
        case .playing:
            cancelWatchdog()
            setStatus(.playing(kind))
            if !hasJoined {
                hasJoined = true
                emit(.joined(engine: kind, seconds: elapsedSeconds(since: requestedAt)))
            }
        case .buffering:
            setStatus(.buffering(kind))
            if hasJoined {
                armWatchdog(policy.stallTolerance, error: PlaybackError(code: .network, message: "Playback stalled."))
            }
        case .paused:
            cancelWatchdog()
            setStatus(.paused(kind))
        case .idle, .opening, .ended, .failed:
            break
        }
    }

    // MARK: - Recovering

    /// The connection dropped or the engine failed while playing.
    ///
    /// A recoverable failure reconnects the same engine, within a budget. A
    /// format failure, or an exhausted budget, moves to the next engine. A
    /// video-on-demand stream resumes where it was; a live one rejoins the live edge.
    private func recover(from error: PlaybackError, generation token: Int) {
        guard token == generation, let kind = activeKind else { return }
        cancelWatchdog()
        lastFailure = .now
        attempts.append(PlaybackAttempt(engine: kind, error: error))

        let resume = activeEngine?.duration != nil ? lastPosition : nil
        let index = priorityIndex
        if let engine = activeEngine {
            retire(engine)
        }
        activeEngine = nil
        listener?.cancel()

        if error.isRetryable, reconnects < policy.maxReconnects {
            reconnects += 1
            setStatus(.reconnecting(kind))
            emit(.notice(.reconnecting(engine: kind, reason: error)))
            let wait = policy.delay(forAttempt: reconnects)
            driver = Task {
                try? await sleep(wait)
                guard token == generation else { return }
                await connect(from: index, resume: resume, generation: token)
            }
        } else {
            fallbackFrom = (kind, error)
            driver = Task { await connect(from: index + 1, resume: resume, generation: token) }
        }
    }

    private func refillReconnectBudgetIfStable() {
        guard reconnects > 0, let lastFailure else { return }
        if ContinuousClock.now - lastFailure >= policy.reconnectBudgetResetAfter {
            reconnects = 0
            self.lastFailure = nil
        }
    }

    private func armWatchdog(_ duration: Duration, error: PlaybackError) {
        watchdog?.cancel()
        let token = generation
        watchdog = Task {
            do { try await sleep(duration) } catch { return }
            guard token == generation, !Task.isCancelled else { return }
            recover(from: error, generation: token)
        }
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    // MARK: - Plumbing

    /// Ends the current session: invalidates in-flight work so nothing it does
    /// afterwards has any effect, and hands the engine off to be torn down.
    private func endSession() {
        generation += 1
        driver?.cancel()
        listener?.cancel()
        watchdog?.cancel()
        driver = nil
        listener = nil
        watchdog = nil
        if let engine = activeEngine {
            retire(engine)
        }
        activeEngine = nil
        activeKind = nil
    }

    /// Tears an engine down without making the caller wait for it. Waiting
    /// would add the old channel's teardown to the new channel's join time.
    private func retire(_ engine: any PlaybackEngine) {
        Task { await engine.stop() }
    }

    private func setStatus(_ new: PlaybackStatus) {
        guard new != status else { return }
        status = new
        emit(.status(new))
    }

    private func emit(_ event: PlaybackCoordinatorEvent) {
        output.yield(event)
    }

    private func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

/// Runs an operation against a timeout, whichever finishes first.
///
/// Both halves run on the main actor because the engine is main-actor isolated
/// and not `Sendable`; a task group's child tasks would have to send it across
/// isolation. The loser is cancelled. If the operation ignores cancellation it
/// simply finishes later and its result is discarded.
@MainActor
private enum Race {
    @MainActor
    final class Gate {
        private var continuation: CheckedContinuation<Void, any Error>?
        var onFinish: (() -> Void)?

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<Void, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            onFinish?()
            continuation.resume(with: result)
        }
    }

    /// Carries a cancellation to the gate from any thread, whichever of the two
    /// happens first: the gate being created, or the cancel arriving.
    private final class CancelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var gate: Gate?
        private var cancelled = false

        func set(_ gate: Gate) {
            lock.lock()
            let alreadyCancelled = cancelled
            self.gate = gate
            lock.unlock()
            if alreadyCancelled {
                fire(gate)
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let gate = gate
            lock.unlock()
            if let gate {
                fire(gate)
            }
        }

        private func fire(_ gate: Gate) {
            Task { @MainActor in gate.finish(.failure(CancellationError())) }
        }
    }

    static func run(
        timeout: Duration,
        timeoutError: PlaybackError,
        sleep: @escaping PlaybackCoordinator.Sleeper,
        operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let box = CancelBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = Gate(continuation)
                let work = Task { @MainActor in
                    do {
                        try await operation()
                        gate.finish(.success(()))
                    } catch {
                        gate.finish(.failure(error))
                    }
                }
                let timer = Task { @MainActor in
                    guard await (try? sleep(timeout)) != nil else { return }
                    gate.finish(.failure(timeoutError))
                }
                gate.onFinish = {
                    work.cancel()
                    timer.cancel()
                }
                box.set(gate)
            }
        } onCancel: {
            box.cancel()
        }
    }
}
