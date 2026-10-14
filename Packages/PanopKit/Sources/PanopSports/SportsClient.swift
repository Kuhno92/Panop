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
        return try SportsReply(value: SportsParsing.fixtures(data), quota: quota, raw: data)
    }

    /// One match with its events, stadium and coaches.
    public func fixture(id: Int) async throws -> SportsReply<Fixture> {
        let (data, quota) = try await call("/fixtures/\(id)")
        return try SportsReply(value: SportsParsing.fixture(data), quota: quota, raw: data)
    }

    public func events(fixture id: Int) async throws -> SportsReply<[MatchEvent]> {
        let (data, quota) = try await call("/fixtures/\(id)/events")
        return try SportsReply(value: SportsParsing.events(data), quota: quota, raw: data)
    }

    /// Nil when the service has no teams for the match, which is common below the big leagues.
    public func lineups(fixture id: Int) async throws -> SportsReply<Lineup?> {
        let (data, quota) = try await call("/fixtures/\(id)/lineups")
        return try SportsReply(value: SportsParsing.lineups(data), quota: quota, raw: data)
    }

    public func stats(fixture id: Int) async throws -> SportsReply<MatchStats?> {
        let (data, quota) = try await call("/fixtures/\(id)/stats")
        return try SportsReply(value: SportsParsing.stats(data), quota: quota, raw: data)
    }

    // MARK: - Leagues

    /// Every league, grouped by country: what the picker offers.
    public func leagues() async throws -> SportsReply<[LeagueGroup]> {
        let (data, quota) = try await call("/leagues")
        return try SportsReply(value: SportsParsing.leagues(data), quota: quota, raw: data)
    }

    /// The table of a league. Empty for a cup, which has none.
    public func standings(league id: Int) async throws -> SportsReply<[StandingRow]> {
        let (data, quota) = try await call("/standings/\(id)")
        return try SportsReply(value: SportsParsing.standings(data), quota: quota, raw: data)
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

    private static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }
}
