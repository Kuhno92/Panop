import Foundation
import PanopSports

/// What a screen gets for a request: the data, how old it is, and what went wrong if something did. A failed refresh
/// still gives the data that was kept, so a screen shows the last scores with a note instead of nothing.
struct SportsFetched<Value: Sendable>: Sendable {
    var value: Value?
    var fetchedAt: Date?
    var error: SportsError?
    /// Whether this is what the service said just now (or within the age the caller allowed).
    var isFresh: Bool

    var isStale: Bool {
        value != nil && !isFresh
    }
}

/// Everything the sports screens read comes through here: from the cache while it is fresh enough, otherwise from the
/// service, within what the day's budget allows. Nothing here runs by itself: a screen asks, and decides how old an
/// answer may be.
@MainActor
final class SportsFeed {
    /// How long each kind of answer is good for, unless the caller knows better (a live match asks every minute).
    enum Age {
        static let leagues: TimeInterval = 14 * 24 * 3600
        static let standings: TimeInterval = 6 * 3600
        static let finishedMatch: TimeInterval = 30 * 24 * 3600
        static let lineupsBeforeKickoff: TimeInterval = 15 * 60
    }

    private let account: SportsAccount
    private let cache: SportsCacheStore
    private let now: @Sendable () -> Date
    private var inFlight: [String: Task<Result<Data, SportsError>, Never>] = [:]

    init(account: SportsAccount, cache: SportsCacheStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.account = account
        self.cache = cache
        self.now = now
    }

    // MARK: - Matches

    /// The matches of a day (`YYYY-MM-DD`), all leagues. With `maxAge` 0 only the cache can answer, and nothing is
    /// asked
    /// of the service: for a screen that must not spend the budget, such as the rail on Home.
    func fixtures(day: String, maxAge: TimeInterval, force: Bool = false) async -> SportsFetched<[Fixture]> {
        await load(
            name: "fixtures-\(day)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.fixtures(on: day); return (reply.raw, reply.quota) },
            parse: SportsParsing.fixtures
        )
    }

    func fixture(id: Int, maxAge: TimeInterval, force: Bool = false) async -> SportsFetched<Fixture> {
        await load(
            name: "fixture-\(id)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.fixture(id: id); return (reply.raw, reply.quota) },
            parse: SportsParsing.fixture
        )
    }

    func events(fixture id: Int, maxAge: TimeInterval, force: Bool = false) async -> SportsFetched<[MatchEvent]> {
        await load(
            name: "events-\(id)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.events(fixture: id); return (reply.raw, reply.quota) },
            parse: SportsParsing.events
        )
    }

    /// The value is nil, not missing, when the service has no teams for the match: `fetchedAt` says it was asked.
    func lineups(fixture id: Int, maxAge: TimeInterval, force: Bool = false) async -> SportsFetched<Lineup?> {
        await load(
            name: "lineups-\(id)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.lineups(fixture: id); return (reply.raw, reply.quota) },
            parse: SportsParsing.lineups
        )
    }

    func stats(fixture id: Int, maxAge: TimeInterval, force: Bool = false) async -> SportsFetched<MatchStats?> {
        await load(
            name: "stats-\(id)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.stats(fixture: id); return (reply.raw, reply.quota) },
            parse: SportsParsing.stats
        )
    }

    // MARK: - Leagues

    func leagues(force: Bool = false) async -> SportsFetched<[LeagueGroup]> {
        await load(
            name: "leagues", maxAge: Age.leagues, force: force,
            fetch: { client in let reply = try await client.leagues(); return (reply.raw, reply.quota) },
            parse: SportsParsing.leagues
        )
    }

    func standings(
        league id: Int,
        maxAge: TimeInterval = Age.standings,
        force: Bool = false
    ) async -> SportsFetched<[StandingRow]> {
        await load(
            name: "standings-\(id)", maxAge: maxAge, force: force,
            fetch: { client in let reply = try await client.standings(league: id); return (reply.raw, reply.quota) },
            parse: SportsParsing.standings
        )
    }

    // MARK: - Housekeeping

    /// What was fetched with a key that is gone.
    func clear() async {
        await cache.clear()
    }

    func prune() async {
        await cache.prune(olderThan: 7 * 24 * 3600)
    }

    // MARK: - The rule

    private func load<Value: Sendable>(
        name: String,
        maxAge: TimeInterval,
        force: Bool,
        fetch: @escaping @Sendable (SportsClient) async throws -> (Data, SportsQuota?),
        parse: (Data) throws -> Value
    ) async -> SportsFetched<Value> {
        let kept = await cache.read(name)
        let keptValue = kept.flatMap { try? parse($0.data) }
        if let kept, let keptValue, !force, now().timeIntervalSince(kept.fetchedAt) < maxAge {
            return SportsFetched(value: keptValue, fetchedAt: kept.fetchedAt, error: nil, isFresh: true)
        }
        let stale = SportsFetched<Value>(value: keptValue, fetchedAt: kept?.fetchedAt, error: nil, isFresh: false)

        // `maxAge` 0 says the caller will not have the budget spent for it.
        guard maxAge > 0 || force else { return stale }
        if let reason = refusal(force: force) {
            var result = stale
            result.error = reason
            return result
        }

        switch await fetchRaw(name, fetch) {
        case let .success(data):
            guard let value = try? parse(data) else {
                var result = stale
                result.error = .undecodable
                return result
            }
            return SportsFetched(value: value, fetchedAt: now(), error: nil, isFresh: true)
        case let .failure(error):
            var result = stale
            result.error = error
            return result
        }
    }

    /// Why no request may go out now, or nil when one may.
    private func refusal(force: Bool) -> SportsError? {
        switch account.effectiveState {
        case .noKey, .invalid:
            return .unauthorized
        case let .limitReached(resetsAt):
            return .dailyLimit(resetsAt: resetsAt)
        case .validating:
            return .network
        case .ready:
            // The last few requests of the day are for what the person asks for.
            if !force, !account.allowsBackgroundCalls {
                return .dailyLimit(resetsAt: account.quota?.resetsAt)
            }
            return nil
        }
    }

    /// One request at a time for the same thing: three screens asking for today's matches make one call.
    private func fetchRaw(
        _ name: String,
        _ fetch: @escaping @Sendable (SportsClient) async throws -> (Data, SportsQuota?)
    ) async -> Result<Data, SportsError> {
        if let running = inFlight[name] {
            return await running.value
        }
        let client = account.client
        let cache = cache
        let account = account
        let task = Task { @MainActor () -> Result<Data, SportsError> in
            do {
                let (data, quota) = try await fetch(client)
                await cache.write(name, data: data)
                account.note(quota)
                return .success(data)
            } catch let error as SportsError {
                account.noteFailure(error)
                return .failure(error)
            } catch {
                return .failure(.network)
            }
        }
        inFlight[name] = task
        let result = await task.value
        inFlight[name] = nil
        return result
    }
}
