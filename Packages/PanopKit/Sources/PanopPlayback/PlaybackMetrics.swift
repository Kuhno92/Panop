import Foundation
import PanopCore

/// What happened in one viewing session, in numbers. No address, no channel name, no account:
/// only how playback behaved, which is all the statistics need and nothing that could leak.
public struct PlaybackSessionRecord: Sendable, Equatable, Codable {
    public enum Outcome: Sendable, Equatable, Codable {
        /// It played, and the person watched until they left.
        case watched
        /// They left before there was a picture: the number zapping is judged on.
        case leftBeforeFirstFrame
        /// Every engine failed. The code is of the last error.
        case failed(code: PlaybackError.Code?)
        /// A video reached its end.
        case finished
    }

    public var startedAt: Date
    public var mediaKind: MediaKind
    /// The engine that played last, or nil if none did.
    public var engine: PlaybackEngineKind?
    /// Request to first frame, in seconds, or nil if there never was one.
    public var joinSeconds: Double?
    /// How many times playback stopped for want of data after it had started.
    public var rebuffers: Int
    public var rebufferSeconds: Double
    /// Seconds actually playing, not paused or waiting.
    public var playedSeconds: Double
    /// Engines given up on in favour of the next.
    public var fallbacks: Int
    /// Connections that dropped and were brought back.
    public var reconnects: Int
    public var outcome: Outcome

    public init(
        startedAt: Date,
        mediaKind: MediaKind,
        engine: PlaybackEngineKind? = nil,
        joinSeconds: Double? = nil,
        rebuffers: Int = 0,
        rebufferSeconds: Double = 0,
        playedSeconds: Double = 0,
        fallbacks: Int = 0,
        reconnects: Int = 0,
        outcome: Outcome
    ) {
        self.startedAt = startedAt
        self.mediaKind = mediaKind
        self.engine = engine
        self.joinSeconds = joinSeconds
        self.rebuffers = rebuffers
        self.rebufferSeconds = rebufferSeconds
        self.playedSeconds = playedSeconds
        self.fallbacks = fallbacks
        self.reconnects = reconnects
        self.outcome = outcome
    }
}

/// Turns the coordinator's events into one ``PlaybackSessionRecord``.
///
/// Time is passed in with each event, so the arithmetic is the same in a test as in the app and
/// no clock is read here. A session's numbers are only *kept* when it ends, never during
/// playback: a write per tick would hitch the picture it is measuring.
public struct PlaybackSessionRecorder: Sendable {
    private let startedAt: Date
    private let mediaKind: MediaKind

    private var engine: PlaybackEngineKind?
    private var joinSeconds: Double?
    private var rebuffers = 0
    private var rebufferSeconds = 0.0
    private var playedSeconds = 0.0
    private var fallbacks = 0
    private var reconnects = 0
    private var failure: PlaybackFailure?
    private var ended = false

    private enum Phase {
        case other
        case playing
        case rebuffering
    }

    private var phase = Phase.other
    private var phaseSince: Date

    public init(startedAt: Date, mediaKind: MediaKind) {
        self.startedAt = startedAt
        self.mediaKind = mediaKind
        phaseSince = startedAt
    }

    public mutating func apply(_ event: PlaybackCoordinatorEvent, at now: Date) {
        switch event {
        case let .status(status):
            apply(status, at: now)
        case let .joined(engine, seconds):
            self.engine = engine
            joinSeconds = joinSeconds ?? seconds
        case let .notice(notice):
            switch notice {
            case .fellBack: fallbacks += 1
            case .reconnecting: reconnects += 1
            }
        case .position, .tracks:
            break
        }
    }

    private mutating func apply(_ status: PlaybackStatus, at now: Date) {
        switch status {
        case let .playing(kind):
            engine = kind
            enter(.playing, at: now)
        case let .buffering(kind):
            engine = kind
            // Only waiting after the first frame is a rebuffer; before it, it is joining.
            enter(joinSeconds == nil ? .other : .rebuffering, at: now)
        case .reconnecting, .connecting, .paused, .idle:
            enter(.other, at: now)
        case .ended:
            ended = true
            enter(.other, at: now)
        case let .failed(failure):
            self.failure = failure
            enter(.other, at: now)
        }
    }

    /// Closes the stretch that was running and starts the next.
    private mutating func enter(_ next: Phase, at now: Date) {
        let elapsed = max(now.timeIntervalSince(phaseSince), 0)
        switch phase {
        case .playing: playedSeconds += elapsed
        case .rebuffering: rebufferSeconds += elapsed
        case .other: break
        }
        if next == .rebuffering, phase != .rebuffering {
            rebuffers += 1
        }
        phase = next
        phaseSince = now
    }

    /// The record, once the session is over.
    public mutating func finish(at now: Date) -> PlaybackSessionRecord {
        enter(.other, at: now)
        let outcome: PlaybackSessionRecord.Outcome = if let failure {
            .failed(code: failure.lastError?.code)
        } else if joinSeconds == nil {
            .leftBeforeFirstFrame
        } else if ended {
            .finished
        } else {
            .watched
        }
        return PlaybackSessionRecord(
            startedAt: startedAt,
            mediaKind: mediaKind,
            engine: engine,
            joinSeconds: joinSeconds,
            rebuffers: rebuffers,
            rebufferSeconds: rebufferSeconds,
            playedSeconds: playedSeconds,
            fallbacks: fallbacks,
            reconnects: reconnects,
            outcome: outcome
        )
    }
}

/// What a set of sessions adds up to.
public struct PlaybackStatistics: Sendable, Equatable {
    public struct EngineShare: Sendable, Equatable {
        public var engine: PlaybackEngineKind
        public var sessions: Int
        public var medianJoinSeconds: Double?
    }

    public var sessions: Int
    public var medianJoinSeconds: Double?
    public var p90JoinSeconds: Double?
    /// Waiting for data as a share of the time spent playing or waiting, 0 to 1.
    public var rebufferRatio: Double
    /// Share of sessions the person left before a picture appeared, 0 to 1.
    public var leftBeforeFirstFrame: Double
    /// Share of sessions in which at least one engine was given up on, 0 to 1.
    public var fellBack: Double
    /// Share of sessions that ended with every engine failing, 0 to 1.
    public var failed: Double
    public var byEngine: [EngineShare]

    public init(_ records: [PlaybackSessionRecord]) {
        sessions = records.count
        let joins = records.compactMap(\.joinSeconds).sorted()
        medianJoinSeconds = Self.percentile(joins, 0.5)
        p90JoinSeconds = Self.percentile(joins, 0.9)

        let played = records.reduce(0) { $0 + $1.playedSeconds }
        let waited = records.reduce(0) { $0 + $1.rebufferSeconds }
        rebufferRatio = played + waited > 0 ? waited / (played + waited) : 0

        func share(_ matches: (PlaybackSessionRecord) -> Bool) -> Double {
            records.isEmpty ? 0 : Double(records.filter(matches).count) / Double(records.count)
        }
        leftBeforeFirstFrame = share { $0.outcome == .leftBeforeFirstFrame }
        fellBack = share { $0.fallbacks > 0 }
        failed = share {
            if case .failed = $0.outcome {
                true
            } else {
                false
            }
        }

        let grouped = Dictionary(grouping: records.filter { $0.engine != nil }, by: { $0.engine! })
        byEngine = grouped
            .map { engine, list in
                EngineShare(
                    engine: engine,
                    sessions: list.count,
                    medianJoinSeconds: Self.percentile(list.compactMap(\.joinSeconds).sorted(), 0.5)
                )
            }
            .sorted { $0.sessions > $1.sessions }
    }

    /// Nearest-rank percentile of a sorted list.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((Double(sorted.count) * fraction).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
