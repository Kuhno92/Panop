import Foundation
import PanopCore

/// Calls to sportapi.ai with the person's own key. Each call takes the key afresh from `key`, so none holds on to
/// it; with no key a call fails at once and costs no request.
///
/// Every reply carries what the service says about the day's budget (``SportsQuota``). A call returns it with the
/// value, so the caller always knows what is left without counting.
public struct SportsClient: Sendable {
    public static let defaultBase = "https://sportapi.ai/api"

    private let transport: any HTTPTransport
    private let base: String
    private let key: @Sendable () async -> String?

    public init(
        transport: any HTTPTransport,
        base: String = SportsClient.defaultBase,
        key: @escaping @Sendable () async -> String?
    ) {
        self.transport = transport
        self.base = base
        self.key = key
    }

    // MARK: - Matches

    /// The matches of one day, from every league at once. `day` is `YYYY-MM-DD` (see ``SportsDate/dayKey(for:in:)``).
    /// One call covers all leagues, so what it costs does not depend on how many the person follows.
    public func fixtures(on day: String) async throws -> SportsReply<[Fixture]> {
        let (data, quota) = try await call("/fixtures/date/" + Self.segment(day))
        let envelope = try decode(Envelope<Lossy<Fixture>>.self, data)
        return SportsReply(value: envelope.data?.elements ?? [], quota: quota)
    }

    /// One match with its events, stadium and coaches.
    public func fixture(id: Int) async throws -> SportsReply<Fixture> {
        let (data, quota) = try await call("/fixtures/\(id)")
        guard let reply = try? JSONDecoder().decode(FixtureReply.self, from: data), let fixture = reply.fixture else {
            throw SportsError.undecodable
        }
        return SportsReply(value: fixture, quota: quota)
    }

    public func events(fixture id: Int) async throws -> SportsReply<[MatchEvent]> {
        let (data, quota) = try await call("/fixtures/\(id)/events")
        let envelope = try decode(Envelope<Lossy<MatchEvent>>.self, data)
        return SportsReply(value: envelope.data?.elements ?? [], quota: quota)
    }

    /// Nil when the service has no teams for the match, which is common below the big leagues.
    public func lineups(fixture id: Int) async throws -> SportsReply<Lineup?> {
        let (data, quota) = try await call("/fixtures/\(id)/lineups")
        let envelope = try decode(Envelope<LineupData>.self, data)
        guard envelope.available != false, let teams = envelope.data else {
            return SportsReply(value: nil, quota: quota)
        }
        return SportsReply(value: Lineup(home: teams.home, away: teams.away), quota: quota)
    }

    public func stats(fixture id: Int) async throws -> SportsReply<MatchStats?> {
        let (data, quota) = try await call("/fixtures/\(id)/stats")
        let envelope = try decode(Envelope<StatsData>.self, data)
        guard envelope.available != false, let teams = envelope.data else {
            return SportsReply(value: nil, quota: quota)
        }
        return SportsReply(value: MatchStats(home: teams.home, away: teams.away), quota: quota)
    }

    // MARK: - Leagues

    /// Every league, grouped by country: what the picker offers.
    public func leagues() async throws -> SportsReply<[LeagueGroup]> {
        let (data, quota) = try await call("/leagues")
        let envelope = try decode(Envelope<Lossy<LeagueGroup>>.self, data)
        return SportsReply(value: envelope.data?.elements ?? [], quota: quota)
    }

    /// The table of a league. Empty for a cup, which has none.
    public func standings(league id: Int) async throws -> SportsReply<[StandingRow]> {
        let (data, quota) = try await call("/standings/\(id)")
        let envelope = try decode(Envelope<Lossy<StandingRow>>.self, data)
        return SportsReply(value: (envelope.data?.elements ?? []).sorted { $0.position < $1.position }, quota: quota)
    }

    /// Whether the key is accepted, and what is left of the day. The cheapest call there is: one request.
    public func validate() async throws -> SportsQuota? {
        let (_, quota) = try await call("/standings/leagues")
        return quota
    }

    // MARK: - Wire

    private func call(_ path: String) async throws -> (Data, SportsQuota?) {
        guard let key = await key(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: base + path)
        else { throw SportsError.unauthorized }
        let request = HTTPRequest(
            url: url,
            headers: [
                "X-Api-Key": key.trimmingCharacters(in: .whitespacesAndNewlines),
                "Accept": "application/json",
                "User-Agent": "Panop"
            ],
            timeout: 30
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // What the transport threw can name the address, and the request carries the key: say only that it failed.
            throw SportsError.network
        }
        let quota = SportsQuota(headers: response.headers)
        switch response.statusCode {
        case 200 ..< 300: return (response.body, quota)
        case 401, 403: throw SportsError.unauthorized
        case 429: throw SportsError.dailyLimit(resetsAt: quota?.resetsAt)
        default: throw SportsError.status(response.statusCode)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ data: Data) throws -> Value {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw SportsError.undecodable }
        return value
    }

    private static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }
}

private struct FixtureReply: Decodable {
    var fixture: Fixture?

    private enum Keys: String, CodingKey { case fixture }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        fixture = try? container.decodeIfPresent(Fixture.self, forKey: .fixture)
    }
}

private struct LineupData: Decodable {
    var home: TeamLineup
    var away: TeamLineup

    private enum Keys: String, CodingKey { case home, away }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        home = (try? container.decodeIfPresent(TeamLineup.self, forKey: .home)) ?? TeamLineup(starters: [])
        away = (try? container.decodeIfPresent(TeamLineup.self, forKey: .away)) ?? TeamLineup(starters: [])
    }
}

private struct StatsData: Decodable {
    var home: TeamStats
    var away: TeamStats

    private enum Keys: String, CodingKey { case home, away }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        home = try container.decode(TeamStats.self, forKey: .home)
        away = try container.decode(TeamStats.self, forKey: .away)
    }
}
