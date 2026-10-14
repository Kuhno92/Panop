import Foundation
import Observation
import PanopSports

/// The state of the sports hub: the day's matches the person follows, laid out, and how fresh they are.
///
/// It reads through `SportsFeed`, so it spends what the day's budget allows and no more: a live match is asked about
/// every minute, then more slowly as the budget goes, and a screen that is not on never asks at all.
@MainActor
@Observable
final class SportsHubModel {
    enum Day: Int, CaseIterable, Identifiable {
        case today, tomorrow

        var id: Int {
            rawValue
        }
    }

    var day: Day = .today
    private(set) var layout: HubLayout = .empty
    /// When the oldest of what is shown was fetched.
    private(set) var fetchedAt: Date?
    /// What went wrong with the last refresh, if something did. What was kept is still shown.
    private(set) var error: SportsError?
    private(set) var isLoading = false
    /// Whether a first answer (fresh or kept) has come: before it, the screen shows its skeleton.
    private(set) var hasLoaded = false
    private(set) var leagues: [SportsLeagueChoice] = []
    private(set) var teams: [SportsTeamChoice] = []
    /// The channels of the person's playlist that show a match, by the match's id, best first.
    private(set) var links: [Int: [MatchLink]] = [:]
    /// The playlist's channels behind `links`, by `ChannelCandidate.id`.
    private var channelRows: [String: CatalogRow] = [:]

    private let feed: SportsFeed
    private let account: SportsAccount
    private let sync: SportsSyncStore
    private let now: @Sendable () -> Date
    var profile: String

    /// Where the channels that show a match are looked for: the person's playlists and what they favour.
    struct ChannelSource {
        var reader: MatchChannelReader
        var playlists: @MainActor () -> [String]
        var favourites: @MainActor () -> Set<String>
    }

    private let channels: ChannelSource?
    /// What the channels were last looked for with, so a refresh that changed nothing does not read the guide again.
    private var linksKey = ""

    init(
        feed: SportsFeed, account: SportsAccount, sync: SportsSyncStore, profile: String,
        channels: ChannelSource? = nil, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.feed = feed
        self.account = account
        self.sync = sync
        self.profile = profile
        self.channels = channels
        self.now = now
    }

    var hasLive: Bool {
        layout.scoreboard.contains(where: \.isLive)
    }

    /// Whether there is anything the person follows yet.
    var hasSelection: Bool {
        !leagues.isEmpty || !teams.isEmpty
    }

    var followedTeamIDs: Set<Int> {
        Set(teams.map(\.id))
    }

    // MARK: - Loading

    /// Reads the day again: from the cache while it is fresh enough, else from the service. `force` is the person
    /// asking (pulling down), which may use the last requests of the day that a timer may not.
    func reload(force: Bool = false) async {
        readSelection()
        guard hasSelection else {
            layout = .empty
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        let date = day == .today ? now() : now().addingTimeInterval(24 * 3600)
        let maxAge = freshness(for: day)
        var fixtures: [Fixture] = []
        var oldest: Date?
        var failure: SportsError?
        for key in SportsDate.serviceDayKeys(coveringLocalDayOf: date) {
            let result = await feed.fixtures(day: key, maxAge: maxAge, force: force)
            fixtures += result.value ?? []
            if let fetched = result.fetchedAt {
                oldest = min(oldest ?? fetched, fetched)
            }
            failure = failure ?? result.error
        }
        // The service's day is not the person's day: only what kicks off on theirs is shown, once each.
        var seen = Set<Int>()
        fixtures = fixtures.filter { SportsDate.isOnLocalDay($0.kickoff, of: date) && seen.insert($0.id).inserted }

        layout = HubLayout.make(
            fixtures: fixtures, leagues: leagues.map(\.id), teams: teams.map(\.id), now: now()
        )
        fetchedAt = oldest
        error = failure
        hasLoaded = true
        await refreshLinks()
    }

    /// Looks for the channels that show the matches still to come or on now, when what is asked has changed or the
    /// guide
    /// may have: the guide moves slowly, so a match's channel is asked again at most every quarter of an hour.
    private func refreshLinks() async {
        guard let channels else { return }
        let fixtures = (layout.sections.flatMap(\.fixtures) + (layout.hero.map { [$0] } ?? []))
            .filter { $0.status == .scheduled || $0.isLive }
        var seen = Set<Int>()
        let unique = fixtures.filter { seen.insert($0.id).inserted }
        let playlists = channels.playlists()
        let key = "\(unique.map(\.id).sorted())|\(playlists)|\(Int(now().timeIntervalSince1970 / 900))|\(sync.revision)"
        guard key != linksKey else { return }
        linksKey = key
        guard !unique.isEmpty, !playlists.isEmpty else {
            setLinks([:], rows: [:])
            return
        }
        var remembered: [Int: Set<String>] = [:]
        for league in Set(unique.compactMap(\.leagueID)) {
            remembered[league] = Set(sync.channelChoices(league: league, profile: profile).keys)
        }
        let output = await channels.reader.read(MatchChannelReader.Request(
            fixtures: unique, playlists: playlists, remembered: remembered, favourites: channels.favourites()
        ))
        setLinks(output.links, rows: output.rows)
    }

    /// How old an answer may be before it is asked for again.
    private func freshness(for day: Day) -> TimeInterval {
        if day == .tomorrow {
            return 6 * 3600
        }
        return account.quota?.refreshInterval(isLive: hasLive) ?? (hasLive ? 60 : 600)
    }

    /// Keeps the hub current while it is on screen. Ends when the screen goes (the task is cancelled).
    func run() async {
        while !Task.isCancelled {
            await reload()
            let wait = min(600, account.quota?.refreshInterval(isLive: hasLive) ?? (hasLive ? 60 : 600))
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func readSelection() {
        leagues = sync.leagues(profile: profile)
        teams = sync.teams(profile: profile)
    }

    /// What to play to watch a match on a channel. The choice is remembered for the league, so the next match of it
    /// offers the same channel first.
    func target(for link: MatchLink, in fixture: Fixture) -> PlaybackTarget? {
        guard let row = channelRows[link.channel.id] else { return nil }
        if let league = fixture.leagueID {
            sync.rememberChannel(link.channel.id, league: league, profile: profile)
        }
        return PlaybackTarget(row: row)
    }

    func setLinks(_ links: [Int: [MatchLink]], rows: [String: CatalogRow]) {
        self.links = links
        channelRows = rows
    }

    // MARK: - What the screen says

    /// A one-line note for the top of the screen about the state of the data, or nil when all is well.
    enum Notice: Equatable {
        case limitReached(resetsAt: Date?)
        case keyRefused
        case offline(since: Date?)
        case unreadable
    }

    var notice: Notice? {
        switch account.effectiveState {
        case let .limitReached(resetsAt): return .limitReached(resetsAt: resetsAt)
        case .invalid: return .keyRefused
        default: break
        }
        switch error {
        case .network?: return .offline(since: fetchedAt)
        case .undecodable?: return .unreadable
        case let .dailyLimit(resetsAt)?: return .limitReached(resetsAt: resetsAt)
        case .unauthorized?: return .keyRefused
        default: return nil
        }
    }
}
