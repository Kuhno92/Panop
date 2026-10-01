import Foundation
import PanopCore
@testable import PanopPlayback
import Testing

@Suite("Playback metrics")
struct PlaybackMetricsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func recorder(_ kind: MediaKind = .live) -> PlaybackSessionRecorder {
        PlaybackSessionRecorder(startedAt: start, mediaKind: kind)
    }

    private func at(_ seconds: Double) -> Date {
        start + seconds
    }

    private func failure(_ code: PlaybackError.Code) -> PlaybackFailure {
        PlaybackFailure(attempts: [PlaybackAttempt(engine: .avPlayer, error: PlaybackError(code: code))])
    }

    // MARK: - One session

    @Test
    func `a session that played is watched, with its join time and its playing time`() {
        var session = recorder()
        session.apply(.status(.connecting(.avPlayer)), at: at(0))
        session.apply(.status(.playing(.avPlayer)), at: at(0.4))
        session.apply(.joined(engine: .avPlayer, seconds: 0.4), at: at(0.4))

        let record = session.finish(at: at(60.4))

        #expect(record.outcome == .watched)
        #expect(record.joinSeconds == 0.4)
        #expect(record.engine == .avPlayer)
        #expect(abs(record.playedSeconds - 60) < 0.001)
        #expect(record.rebuffers == 0)
    }

    @Test
    func `leaving before a picture is its own outcome`() {
        var session = recorder()
        session.apply(.status(.connecting(.avPlayer)), at: at(0))
        session.apply(.status(.buffering(.avPlayer)), at: at(0.2))

        let record = session.finish(at: at(5))

        #expect(record.outcome == .leftBeforeFirstFrame)
        #expect(record.joinSeconds == nil)
        #expect(record.rebuffers == 0, "waiting to start is joining, not rebuffering")
    }

    @Test
    func `waiting for data after the first frame is a rebuffer, and is timed`() {
        var session = recorder()
        session.apply(.status(.playing(.vlcKit)), at: at(0.5))
        session.apply(.joined(engine: .vlcKit, seconds: 0.5), at: at(0.5))
        session.apply(.status(.buffering(.vlcKit)), at: at(10.5))
        session.apply(.status(.playing(.vlcKit)), at: at(12.5))
        session.apply(.status(.buffering(.vlcKit)), at: at(20.5))
        session.apply(.status(.playing(.vlcKit)), at: at(21.5))

        let record = session.finish(at: at(31.5))

        #expect(record.rebuffers == 2)
        #expect(abs(record.rebufferSeconds - 3) < 0.001)
        #expect(abs(record.playedSeconds - 28) < 0.001, "10 + 8 + 10 seconds playing")
    }

    @Test
    func `paused time is neither playing nor waiting`() {
        var session = recorder(.movie)
        session.apply(.status(.playing(.avPlayer)), at: at(0.3))
        session.apply(.joined(engine: .avPlayer, seconds: 0.3), at: at(0.3))
        session.apply(.status(.paused(.avPlayer)), at: at(10.3))
        session.apply(.status(.playing(.avPlayer)), at: at(70.3))

        let record = session.finish(at: at(80.3))

        #expect(abs(record.playedSeconds - 20) < 0.001, "a minute paused is not watched")
        #expect(record.rebufferSeconds == 0)
    }

    @Test
    func `falling back and reconnecting are counted`() {
        var session = recorder()
        session.apply(
            .notice(.fellBack(from: .avPlayer, to: .vlcKit, reason: PlaybackError(code: .unsupportedFormat))),
            at: at(0.2)
        )
        session.apply(.status(.playing(.vlcKit)), at: at(0.9))
        session.apply(.joined(engine: .vlcKit, seconds: 0.9), at: at(0.9))
        session.apply(.notice(.reconnecting(engine: .vlcKit, reason: PlaybackError(code: .network))), at: at(30))
        session.apply(.notice(.reconnecting(engine: .vlcKit, reason: PlaybackError(code: .network))), at: at(50))

        let record = session.finish(at: at(60))

        #expect(record.fallbacks == 1)
        #expect(record.reconnects == 2)
        #expect(record.engine == .vlcKit, "the engine that played last")
    }

    @Test
    func `every engine failing is a failure with the last error's code`() {
        var session = recorder()
        session.apply(.status(.connecting(.avPlayer)), at: at(0))
        session.apply(.status(.failed(failure(.openFailed))), at: at(8))

        let record = session.finish(at: at(9))

        #expect(record.outcome == .failed(code: .openFailed))
        #expect(record.joinSeconds == nil)
    }

    @Test
    func `a video reaching its end is finished, not just watched`() {
        var session = recorder(.movie)
        session.apply(.status(.playing(.avPlayer)), at: at(0.3))
        session.apply(.joined(engine: .avPlayer, seconds: 0.3), at: at(0.3))
        session.apply(.status(.ended), at: at(3600))

        #expect(session.finish(at: at(3601)).outcome == .finished)
    }

    @Test
    func `the first join time is the one kept`() {
        var session = recorder()
        session.apply(.joined(engine: .avPlayer, seconds: 0.4), at: at(0.4))
        session.apply(.joined(engine: .vlcKit, seconds: 9), at: at(9))

        #expect(session.finish(at: at(10)).joinSeconds == 0.4)
    }

    @Test
    func `a record holds no address, name or account`() throws {
        var session = recorder()
        session.apply(.status(.playing(.avPlayer)), at: at(0.3))
        session.apply(.joined(engine: .avPlayer, seconds: 0.3), at: at(0.3))

        let encoded = try JSONEncoder().encode(session.finish(at: at(5)))
        let json = try #require(String(bytes: encoded, encoding: .utf8))

        #expect(!json.contains("http"))
        #expect(!json.contains("url"))
        #expect(!json.lowercased().contains("name"))
    }

    // MARK: - Many sessions

    private func record(
        join: Double?,
        engine: PlaybackEngineKind? = .avPlayer,
        played: Double = 60,
        waited: Double = 0,
        fallbacks: Int = 0,
        outcome: PlaybackSessionRecord.Outcome = .watched
    ) -> PlaybackSessionRecord {
        PlaybackSessionRecord(
            startedAt: start,
            mediaKind: .live,
            engine: engine,
            joinSeconds: join,
            rebufferSeconds: waited,
            playedSeconds: played,
            fallbacks: fallbacks,
            outcome: outcome
        )
    }

    @Test
    func `median and ninetieth percentile of the join time`() {
        let joins = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 5.0]
        let stats = PlaybackStatistics(joins.map { record(join: $0) })

        #expect(stats.sessions == 10)
        #expect(stats.medianJoinSeconds == 0.5)
        #expect(stats.p90JoinSeconds == 0.9)
    }

    @Test
    func `the rebuffer ratio is waiting over playing plus waiting`() {
        let stats = PlaybackStatistics([
            record(join: 0.3, played: 90, waited: 10),
            record(join: 0.3, played: 100, waited: 0)
        ])

        #expect(abs(stats.rebufferRatio - 10.0 / 200.0) < 0.0001)
    }

    @Test
    func `shares of sessions that left early, fell back and failed`() {
        let stats = PlaybackStatistics([
            record(join: 0.3),
            record(join: nil, played: 0, outcome: .leftBeforeFirstFrame),
            record(join: 1.0, fallbacks: 1),
            record(join: nil, engine: nil, played: 0, outcome: .failed(code: .network))
        ])

        #expect(stats.leftBeforeFirstFrame == 0.25)
        #expect(stats.fellBack == 0.25)
        #expect(stats.failed == 0.25)
    }

    @Test
    func `engines are ranked by how often they played, with their own median join`() {
        let stats = PlaybackStatistics([
            record(join: 0.2, engine: .avPlayer), record(join: 0.4, engine: .avPlayer), record(
                join: 0.3,
                engine: .avPlayer
            ),
            record(join: 0.9, engine: .vlcKit)
        ])

        #expect(stats.byEngine.map(\.engine) == [.avPlayer, .vlcKit])
        #expect(stats.byEngine.first?.sessions == 3)
        #expect(stats.byEngine.first?.medianJoinSeconds == 0.3)
    }

    @Test
    func `no sessions is all zeros, not a division by zero`() {
        let stats = PlaybackStatistics([])

        #expect(stats.sessions == 0)
        #expect(stats.medianJoinSeconds == nil)
        #expect(stats.rebufferRatio == 0)
        #expect(stats.leftBeforeFirstFrame == 0)
        #expect(stats.byEngine.isEmpty)
    }
}
