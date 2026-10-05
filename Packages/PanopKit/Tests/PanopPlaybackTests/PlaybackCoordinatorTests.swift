import Foundation
import PanopCore
@testable import PanopPlayback
import Testing

private let avAndVLC: [PlaybackEngineKind] = [.avPlayer, .vlcKit]

@MainActor
private func makeCoordinator(
    _ factory: EngineFactory,
    policy: PlaybackPolicy = testPolicy(),
    priority: [PlaybackEngineKind] = avAndVLC,
    sleeper: TestSleeper = TestSleeper()
) -> PlaybackCoordinator {
    PlaybackCoordinator(
        policy: policy,
        priority: priority,
        makeEngine: { factory.make($0) },
        sleep: { try await sleeper.sleep($0) }
    )
}

private let stream = PlaybackRequest(PlaybackItem(url: "http://host/live/1.ts", mediaKind: .live))

@Suite("Playback coordinator", .serialized)
@MainActor
struct PlaybackCoordinatorTests {
    // MARK: - Opening

    @Test
    func `plays with the first engine and reports how long it took`() async {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let joined = await log.wait {
            if case .joined = $0 {
                true
            } else {
                false
            }
        }
        guard case let .joined(engine, seconds)? = joined else {
            Issue.record("no join time was reported")
            return
        }
        #expect(engine == .avPlayer)
        #expect(seconds >= 0)
        #expect(factory.created.count == 1)
        #expect(log.notices.isEmpty)
        #expect(coordinator.activeKind == .avPlayer)
    }

    /// The URL can depend on the engine: HLS for AVPlayer, a raw stream for the rest.
    @Test
    func `each engine is given the item chosen for it`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.unsupportedFormat)]])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        let request = PlaybackRequest(mediaKind: .live) { kind in
            PlaybackItem(url: kind == .avPlayer ? "http://h/1.m3u8" : "http://h/1.ts", mediaKind: .live)
        }

        coordinator.play(request)
        #expect(await log.waitForStatus(.playing(.vlcKit)))

        #expect(factory.engines(.avPlayer).first?.loadedItems.first?.url == "http://h/1.m3u8")
        #expect(factory.engines(.vlcKit).first?.loadedItems.first?.url == "http://h/1.ts")
    }

    // MARK: - Falling through

    /// A format rejection will never succeed on this engine. Retrying wastes the
    /// user's time.
    @Test
    func `a format rejection moves on without retrying`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.unsupportedFormat)]])
        let sleeper = TestSleeper()
        let coordinator = makeCoordinator(factory, sleeper: sleeper)
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        #expect(factory.engines(.avPlayer).count == 1, "the failing engine must not be retried")
        #expect(sleeper.durations.isEmpty, "a format failure must not back off")
        guard case let .fellBack(from, to, reason)? = log.notices.first else {
            Issue.record("the fallback was silent")
            return
        }
        #expect(from == .avPlayer)
        #expect(to == .vlcKit)
        #expect(reason.code == .unsupportedFormat)
    }

    @Test
    func `a network failure retries on a fresh engine then succeeds`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.network), .ok]])
        let sleeper = TestSleeper()
        let coordinator = makeCoordinator(factory, sleeper: sleeper)
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.avPlayer)))
        #expect(factory.engines(.avPlayer).count == 2, "a retry needs a new engine instance")
        #expect(sleeper.durations == [.milliseconds(1)])
        #expect(factory.engines(.avPlayer)[0].stopCalls >= 1, "the failed engine must be torn down")
        #expect(factory.engines(.vlcKit).isEmpty)
    }

    @Test
    func `retries run out and the next engine takes over`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.network)]])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        // One attempt plus the single configured retry.
        #expect(factory.engines(.avPlayer).count == 2)
        #expect(log.notices.contains {
            if case .fellBack = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test
    func `total failure lists every attempt and why`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.unsupportedFormat)], .vlcKit: [.fail(.decodeFailed)]])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)

        coordinator.play(stream)

        let failed = await log.wait {
            if case .status(.failed) = $0 {
                true
            } else {
                false
            }
        }
        guard case let .status(.failed(report))? = failed else {
            Issue.record("expected a failed status")
            return
        }
        #expect(report.attempts.map(\.engine) == [.avPlayer, .vlcKit])
        #expect(report.attempts.map { $0.error?.code } == [.unsupportedFormat, .decodeFailed])
        #expect(report.lastError?.code == .decodeFailed)
    }

    @Test
    func `an engine that is not in this build is skipped and noted`() async {
        let factory = EngineFactory([.avPlayer: [.fail(.unsupportedFormat)]], unavailable: [.vlcKit])
        let coordinator = makeCoordinator(factory, priority: [.vlcKit, .avPlayer])
        let log = EventLog(coordinator)

        coordinator.play(stream)

        let failed = await log.wait {
            if case .status(.failed) = $0 {
                true
            } else {
                false
            }
        }
        guard case let .status(.failed(report))? = failed else {
            Issue.record("expected a failed status")
            return
        }
        #expect(report.attempts == [
            PlaybackAttempt(engine: .vlcKit, error: nil),
            PlaybackAttempt(
                engine: .avPlayer,
                error: PlaybackError(code: .unsupportedFormat, message: "scripted unsupportedFormat")
            )
        ])
        #expect(factory.created.count == 1, "an unavailable engine is never instantiated")
    }

    // MARK: - Silence is a failure

    @Test
    func `an engine that never finishes loading is timed out`() async {
        let factory = EngineFactory([.avPlayer: [FakeEngine.Script(load: .hang)]])
        let coordinator = makeCoordinator(factory, policy: testPolicy(open: .milliseconds(1), openRetries: 0))
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        guard case let .fellBack(_, _, reason)? = log.notices.first else {
            Issue.record("expected a fallback notice")
            return
        }
        #expect(reason.code == .network)
        #expect(factory.engines(.avPlayer).first?.stopCalls ?? 0 >= 1, "the hung engine must be torn down")
    }

    @Test
    func `a stream that opens but never shows a frame is timed out`() async {
        let factory = EngineFactory([.avPlayer: [FakeEngine.Script(startsPlaying: false)]])
        // The start timeout fires for the first engine only; the fallback plays.
        let start = Duration.milliseconds(7)
        let coordinator = makeCoordinator(
            factory,
            policy: testPolicy(start: start, reconnects: 0),
            sleeper: TestSleeper(firesOnce: [start])
        )
        let log = EventLog(coordinator)

        coordinator.play(stream)

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        #expect(factory.engines(.avPlayer).count == 1)
    }

    // MARK: - Recovering mid-playback

    @Test
    func `a live connection that drops is reconnected on the same engine`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.failed(PlaybackError(code: .network, message: "reset")))

        #expect(await log.waitForStatus(.reconnecting(.avPlayer)))
        #expect(await log.wait {
            if case .notice(.reconnecting) = $0 {
                true
            } else {
                false
            }
        } != nil)
        try await waitForEngines(factory, .avPlayer, count: 2)
        #expect(factory.engines(.avPlayer)[0].stopCalls >= 1)
        #expect(factory.engines(.vlcKit).isEmpty)
    }

    @Test
    func `a format failure mid-stream skips reconnecting`() async {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.failed(PlaybackError(code: .decodeFailed)))

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        #expect(factory.engines(.avPlayer).count == 1)
    }

    @Test
    func `the reconnect budget runs out and the next engine takes over`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory, policy: testPolicy(reconnects: 1))
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.failed(PlaybackError(code: .network)))
        try await waitForEngines(factory, .avPlayer, count: 2)
        try await waitFor { factory.lastEngine?.playCalls ?? 0 >= 1 }
        factory.lastEngine?.report(.failed(PlaybackError(code: .network)))

        #expect(await log.waitForStatus(.playing(.vlcKit)))
        #expect(factory.engines(.avPlayer).count == 2)
    }

    /// Playing steadily should give the budget back, or a channel that hiccups
    /// once an hour would eventually be abandoned.
    @Test
    func `stable playback refills the reconnect budget`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory, policy: testPolicy(reconnects: 1, resetAfter: .zero))
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.failed(PlaybackError(code: .network)))
        try await waitForEngines(factory, .avPlayer, count: 2)
        try await waitFor { factory.lastEngine?.playCalls ?? 0 >= 1 }
        factory.lastEngine?.report(.positionChanged(seconds: 5))
        try await waitFor { log.events.contains(.position(seconds: 5)) }
        factory.lastEngine?.report(.failed(PlaybackError(code: .network)))

        try await waitForEngines(factory, .avPlayer, count: 3)
        #expect(factory.engines(.vlcKit).isEmpty, "the budget was not refilled")
    }

    @Test
    func `a video stream resumes where it stopped and a live one does not`() async throws {
        // Video on demand: has a duration.
        let vod = EngineFactory([.avPlayer: [FakeEngine.Script(duration: 3600), FakeEngine.Script(duration: 3600)]])
        let vodCoordinator = makeCoordinator(vod)
        let vodLog = EventLog(vodCoordinator)
        vodCoordinator.play(PlaybackRequest(PlaybackItem(url: "http://h/movie.mkv", mediaKind: .movie)))
        #expect(await vodLog.waitForStatus(.playing(.avPlayer)))
        vod.lastEngine?.report(.positionChanged(seconds: 42))
        try await waitFor { vodLog.events.contains(.position(seconds: 42)) }
        vod.lastEngine?.report(.failed(PlaybackError(code: .network)))
        try await waitForEngines(vod, .avPlayer, count: 2)
        #expect(vod.engines(.avPlayer)[1].loadedItems.first?.startPosition == 42)

        // Live: no duration, so there is nothing to resume.
        let live = EngineFactory([:])
        let liveCoordinator = makeCoordinator(live)
        let liveLog = EventLog(liveCoordinator)
        liveCoordinator.play(stream)
        #expect(await liveLog.waitForStatus(.playing(.avPlayer)))
        live.lastEngine?.report(.positionChanged(seconds: 99))
        live.lastEngine?.report(.failed(PlaybackError(code: .network)))
        try await waitForEngines(live, .avPlayer, count: 2)
        #expect(live.engines(.avPlayer)[1].loadedItems.first?.startPosition == nil)
    }

    @Test
    func `a live stream ending is a dropped connection but a video ending is the end`() async {
        let live = EngineFactory([:])
        let liveCoordinator = makeCoordinator(live)
        let liveLog = EventLog(liveCoordinator)
        liveCoordinator.play(stream)
        #expect(await liveLog.waitForStatus(.playing(.avPlayer)))
        live.lastEngine?.report(.ended)
        #expect(await liveLog.waitForStatus(.reconnecting(.avPlayer)))

        let vod = EngineFactory([.avPlayer: [FakeEngine.Script(duration: 60)]])
        let vodCoordinator = makeCoordinator(vod)
        let vodLog = EventLog(vodCoordinator)
        vodCoordinator.play(PlaybackRequest(PlaybackItem(url: "http://h/m.mkv", mediaKind: .movie)))
        #expect(await vodLog.waitForStatus(.playing(.avPlayer)))
        vod.lastEngine?.report(.ended)
        #expect(await vodLog.waitForStatus(.ended))
    }

    @Test
    func `a stall that does not clear reconnects`() async {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory, policy: testPolicy(stall: .milliseconds(1)))
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.stalled(seconds: 12))

        #expect(await log.waitForStatus(.reconnecting(.avPlayer)))
    }

    @Test
    func `a stall that clears does not`() async {
        let factory = EngineFactory([:])
        // The stall timer hangs, so only recovery can end the stall.
        let coordinator = makeCoordinator(factory, policy: testPolicy(stall: .seconds(1000)))
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))

        factory.lastEngine?.report(.stalled(seconds: 12))
        factory.lastEngine?.report(.stateChanged(.playing))
        await log.settle()

        #expect(factory.created.count == 1)
        #expect(!log.statuses.contains(.reconnecting(.avPlayer)))
    }

    // MARK: - Zapping and stopping

    /// Zapping fast means the old channel's engine is still talking after the new
    /// one has started. What it says must not touch the new channel.
    @Test
    func `a superseded session cannot disturb the new one`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let old = try #require(factory.lastEngine)

        coordinator.play(PlaybackRequest(PlaybackItem(url: "http://host/live/2.ts", mediaKind: .live)))
        try await waitFor { factory.created.count == 2 }
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let engines = factory.created.count

        old.report(.failed(PlaybackError(code: .network)))
        old.report(.ended)
        await log.settle()

        #expect(factory.created.count == engines, "the old engine's failure started a reconnect")
        #expect(coordinator.status == .playing(.avPlayer))
        #expect(old.stopCalls >= 1, "the old engine must be torn down")
        #expect(factory.lastEngine?.loadedItems.first?.url == "http://host/live/2.ts")
    }

    @Test
    func `stopping releases the engine and goes idle`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let engine = try #require(factory.lastEngine)

        await coordinator.stop()

        #expect(coordinator.status == .idle)
        #expect(coordinator.activeEngine == nil)
        #expect(engine.stopCalls >= 1)
    }

    @Test
    func `stopping while an engine is still opening stops it from starting`() async throws {
        let factory = EngineFactory([.avPlayer: [FakeEngine.Script(load: .hang)]])
        let coordinator = makeCoordinator(factory)
        coordinator.play(stream)
        try await waitFor { factory.created.count == 1 }

        await coordinator.stop()
        try? await Task.sleep(for: .milliseconds(30))

        #expect(coordinator.status == .idle)
        #expect(coordinator.activeEngine == nil)
        #expect(factory.created.count == 1, "nothing may start after stop")
    }

    @Test
    func `controls pass through to the active engine`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let engine = try #require(factory.lastEngine)

        coordinator.pause()
        coordinator.seek(to: 30)
        coordinator.resume()

        #expect(engine.pauseCalls == 1)
        #expect(engine.seeks == [30])
        #expect(engine.playCalls >= 2)
    }

    // MARK: - Ordering

    @Test
    func `the preferred engine leads and the rest keep their default order`() {
        #expect(PlaybackEngineKind.order(preferred: nil) == PlaybackEngineKind.defaultPriority)
        #expect(PlaybackEngineKind.order(preferred: .vlcKit) == [.vlcKit, .avPlayer, .lumeEngine, .aetherEngine])
        #expect(PlaybackEngineKind.order(preferred: .avPlayer) == PlaybackEngineKind.defaultPriority)
        // An engine that is not linked cannot be preferred.
        #expect(!PlaybackEngineKind.order(preferred: .ksPlayer).contains(.ksPlayer))
    }

    @Test
    func `the backoff repeats its last delay`() {
        let policy = PlaybackPolicy(backoff: [.milliseconds(1), .milliseconds(5)])
        #expect(policy.delay(forAttempt: 1) == .milliseconds(1))
        #expect(policy.delay(forAttempt: 2) == .milliseconds(5))
        #expect(policy.delay(forAttempt: 9) == .milliseconds(5))
        #expect(PlaybackPolicy(backoff: []).delay(forAttempt: 1) == .zero)
    }

    // MARK: - Helpers

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting for a condition")
                return
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private func waitForEngines(_ factory: EngineFactory, _ kind: PlaybackEngineKind, count: Int) async throws {
        try await waitFor { factory.engines(kind).count >= count }
    }

    @Test
    func `tracks the engine reports are passed on, and a choice reaches the engine`() async throws {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        let german = TrackDescriptor(id: "1", label: "Deutsch", languageCode: "de")
        let english = TrackDescriptor(id: "2", label: "English", languageCode: "en")
        let forced = TrackDescriptor(id: "3", label: "Forced", languageCode: "de", isForced: true)

        factory.lastEngine?.report(.tracksChanged(audio: [german, english], subtitle: [forced]))
        try await waitFor { log.events.contains(.tracks(audio: [german, english], subtitle: [forced])) }

        coordinator.selectAudioTrack(id: "2")
        coordinator.selectSubtitleTrack(id: nil)
        #expect(factory.lastEngine?.audioSelections == ["2"])
        #expect(factory.lastEngine?.subtitleSelections == [nil])
    }

    @Test
    func `a secure connection failure is not retried, the next engine is tried at once`() async {
        let factory = EngineFactory([:])
        let coordinator = makeCoordinator(factory)
        let log = EventLog(coordinator)
        #expect(!PlaybackError(code: .secureConnectionFailed).isRetryable)

        coordinator.play(stream)
        #expect(await log.waitForStatus(.playing(.avPlayer)))
        factory.lastEngine?.report(.failed(PlaybackError(code: .secureConnectionFailed)))

        // Reconnecting the same engine would fail the same way; the coordinator moves on.
        #expect(await log.waitForStatus(.playing(.vlcKit)), "it never reached the next engine")
        #expect(factory.engines(.avPlayer).count == 1, "the failed engine was tried again")
    }
}
