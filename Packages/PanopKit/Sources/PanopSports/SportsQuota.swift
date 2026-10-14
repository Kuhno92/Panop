import Foundation

/// What the service says about the person's daily requests, in the headers of every reply:
/// `x-ratelimit-limit`, `x-ratelimit-remaining` and `x-ratelimit-reset` (the epoch second of the next 00:00 UTC).
/// The server counts, so the app does not: all of a person's devices share one key and so one budget.
public struct SportsQuota: Sendable, Equatable, Codable {
    public var limit: Int
    public var remaining: Int
    public var resetsAt: Date

    public init(limit: Int, remaining: Int, resetsAt: Date) {
        self.limit = limit
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    /// Nil when the reply carries none of it (a stub, or a reply that is not from the service).
    public init?(headers: [String: String]) {
        guard let limit = headers["x-ratelimit-limit"].flatMap({ Int($0) }),
              let remaining = headers["x-ratelimit-remaining"].flatMap({ Int($0) }),
              let reset = headers["x-ratelimit-reset"].flatMap({ TimeInterval($0) })
        else { return nil }
        self.init(limit: limit, remaining: remaining, resetsAt: Date(timeIntervalSince1970: reset))
    }

    public var used: Int {
        max(0, limit - remaining)
    }

    /// 0 to 1.
    public var fractionUsed: Double {
        limit > 0 ? min(1, Double(used) / Double(limit)) : 1
    }

    /// Whether the budget is spent for anything the person did not ask for. The last 5% is kept for what they did:
    /// pulling to refresh, opening a match.
    public var isReserved: Bool {
        fractionUsed >= 0.95
    }

    /// How long to wait between refreshes of a live screen: a minute, then slower as the day's budget goes, so a
    /// long evening of football does not leave the person without scores for the next one.
    public func refreshInterval(isLive: Bool) -> TimeInterval {
        if isReserved {
            return .infinity
        }
        if !isLive {
            return 600
        }
        return fractionUsed >= 0.8 ? 180 : 60
    }
}

/// A reply and what the service said about the budget with it.
public struct SportsReply<Value: Sendable>: Sendable {
    public var value: Value
    public var quota: SportsQuota?
    /// The reply as it came, for a cache to keep: reading it again with ``SportsParsing`` gives `value` back.
    public var raw: Data

    public init(value: Value, quota: SportsQuota?, raw: Data = Data()) {
        self.value = value
        self.quota = quota
        self.raw = raw
    }
}
