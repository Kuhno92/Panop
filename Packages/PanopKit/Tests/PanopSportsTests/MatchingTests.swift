import Foundation
@testable import PanopSports
import Testing

/// Guide lines as providers write them, in several languages. The clubs are plain strings here.
@Suite("team names in guide text")
struct TeamNameTests {
    private func named(_ team: TeamKey, in text: String) -> Bool {
        team.isNamed(in: TeamNames.tokens(text))
    }

    @Test
    func `the same club is found however a guide writes it`() {
        let bayern = TeamKey(name: "Bayern Munich", short: "Bayern")
        for text in [
            "Bundesliga: FC Bayern München - Borussia Dortmund", "Bayern Muenchen v Dortmund",
            "FC Bayern Munich vs BVB", "Fußball: Bayern gegen Dortmund", "BAYERN MÜNCHEN"
        ] {
            #expect(named(bayern, in: text), "\(text)")
        }
        #expect(!named(bayern, in: "Munich 1860 v Fürth"))
    }

    @Test
    func `abbreviations and nicknames come through the alias table`() {
        #expect(named(TeamKey(name: "Manchester United", short: "Man United"), in: "Premier League: Man Utd v Spurs"))
        #expect(named(TeamKey(name: "Tottenham Hotspur", short: "Tottenham"), in: "Man Utd v Spurs"))
        #expect(named(TeamKey(name: "Borussia Dortmund", short: "Dortmund"), in: "Bayern - BVB"))
        #expect(named(TeamKey(name: "Paris Saint-Germain", short: "PSG"), in: "Ligue 1: PSG - OM"))
        #expect(named(TeamKey(name: "1. FC Köln", short: "Köln"), in: "Koeln - Hamburger SV"))
        #expect(named(TeamKey(name: "Internazionale", short: "Inter"), in: "Serie A: Inter - Juve"))
    }

    @Test
    func `a word that names no one club finds no one`() {
        let city = TeamKey(name: "Manchester City", short: "Man City")
        #expect(!named(city, in: "Premier League: Manchester United v Arsenal"))
        let united = TeamKey(name: "Newcastle United", short: "Newcastle")
        #expect(!named(united, in: "Manchester United v Arsenal"))
        #expect(named(united, in: "Newcastle - Arsenal"))
        // A club that is only a common word and a place has no one-word name to be found by.
        let town = TeamKey(name: "Alder Town")
        #expect(!named(town, in: "Birch Town v Oak Town"))
        #expect(named(town, in: "Alder Town v Birch City"))
    }

    @Test
    func `dressing around a name is not part of it`() {
        let team = TeamKey(name: "1. FSV Mainz 05", short: "Mainz")
        #expect(named(team, in: "Mainz 05 - Freiburg"))
        #expect(named(TeamKey(name: "FC Augsburg"), in: "Augsburg v Wolfsburg"))
    }

    @Test
    func `a league is found by what the service calls it and by what a guide does`() {
        let mls = LeagueKey(name: "US Major League Soccer")
        #expect(mls.isNamed(in: TeamNames.tokens("MLS: Chicago v Vancouver")))
        let ucl = LeagueKey(name: "UEFA Champions League")
        #expect(ucl.isNamed(in: TeamNames.tokens("Champions League Live: Arsenal - PSG")))
        #expect(!LeagueKey(name: "Championship").isNamed(in: TeamNames.tokens("World Championship Darts")))
    }
}

@Suite("which channel shows the match")
struct ChannelMatchTests {
    /// Saturday 15:30 UTC.
    private let kickoff = Date(timeIntervalSince1970: 1_792_077_000)
    private var match: MatchSignature {
        MatchSignature(
            home: TeamKey(name: "Bayern Munich", short: "Bayern"),
            away: TeamKey(name: "Borussia Dortmund", short: "Dortmund"),
            league: LeagueKey(name: "Bundesliga"),
            kickoff: kickoff
        )
    }

    private let channels: [String: ChannelCandidate] = [
        "sky": ChannelCandidate(id: "sky", name: "Sky Sport Bundesliga 1 HD", group: "DE | SPORT", qualityRank: 2),
        "dazn": ChannelCandidate(id: "dazn", name: "DAZN 1", group: "DE | SPORT", qualityRank: 1),
        "ard": ChannelCandidate(id: "ard", name: "Das Erste", group: "DE | Vollprogramm"),
        "gen": ChannelCandidate(id: "gen", name: "Sport Channel", group: "Sports"),
        "movie": ChannelCandidate(id: "movie", name: "Movie Channel", group: "Films")
    ]

    private func line(
        _ channel: String, from minutes: Int = -5, for length: Int = 125, _ title: String,
        subtitle: String? = nil, details: String? = nil, categories: [String] = []
    ) -> PreparedProgramme {
        PreparedProgramme(ProgrammeSnippet(
            channelID: channel,
            start: kickoff.addingTimeInterval(TimeInterval(minutes * 60)),
            stop: kickoff.addingTimeInterval(TimeInterval((minutes + length) * 60)),
            title: title, subtitle: subtitle, details: details, categories: categories
        ))
    }

    private func resolve(_ lines: [PreparedProgramme], remembered: Set<String> = []) -> [MatchLink] {
        MatchChannelResolver.resolve(match, programmes: lines, channels: channels, remembered: remembered)
    }

    @Test
    func `a programme that names both teams is the match`() throws {
        let links = resolve([line("sky", "Bundesliga: FC Bayern München - Borussia Dortmund")])
        let link = try #require(links.first)
        #expect(link.channel.id == "sky")
        #expect(link.score.reason == .bothTeamsInTitle)
        #expect(link.score.tier == .watch)
        #expect(link.score.value >= 90)
    }

    @Test
    func `a generic title is still the match when the description names the teams`() throws {
        // What other apps miss: the title says only "Football Live".
        let links = resolve([line(
            "dazn", "Football Live",
            details: "Der Klassiker: FC Bayern gegen Borussia Dortmund aus der Allianz Arena. Bundesliga, 27. Spieltag."
        )])
        let link = try #require(links.first)
        #expect(link.score.reason == .bothTeamsInText)
        #expect(link.score.tier == .watch)
    }

    @Test
    func `the subtitle counts as part of what is on`() {
        let links = resolve([line("sky", "Bundesliga live", subtitle: "Bayern München v Dortmund")])
        #expect(links.first?.score.reason == .bothTeamsInTitle)
    }

    @Test
    func `a look back or a preview is not the match`() {
        let links = resolve([
            line("sky", from: -90, for: 100, "Highlights: Bayern München - Borussia Dortmund"),
            line("dazn", from: -20, for: 30, "Vorbericht: Bayern gegen Dortmund")
        ])
        for link in links {
            #expect(link.score.tier < .watch, "\(link.channel.id) \(link.score.value)")
        }
    }

    @Test
    func `a programme that is not on at the time is not the match`() {
        let links = resolve([
            line("sky", from: 200, for: 60, "Bayern München - Borussia Dortmund"),
            line("dazn", from: -400, for: 60, "Bayern München - Borussia Dortmund")
        ])
        #expect(links.isEmpty)
    }

    @Test
    func `one team alone is something to confirm, never something to start`() throws {
        let links = resolve([line("ard", "Sportschau: Bundesliga mit Bayern München")])
        let link = try #require(links.first)
        #expect(link.score.tier <= .likely)
        let other = resolve([line("ard", "Bayern München Magazin")])
        #expect(other.allSatisfy { $0.score.tier < .likely })
    }

    @Test
    func `channels are ordered by how sure, then favourites, then quality`() {
        var favourite = channels
        favourite["dazn"]?.isFavourite = true
        let links = MatchChannelResolver.resolve(
            match,
            programmes: [
                line("sky", "Bayern München - Dortmund"), line("dazn", "Bayern München - Dortmund"),
                line("ard", "Bundesliga: Bayern - Dortmund")
            ],
            channels: favourite
        )
        #expect(links.count == 3)
        // Sky and DAZN both name the teams and a Bundesliga channel is named for it; the favourite goes first.
        #expect(links.map(\.channel.id).first == "dazn" || links.map(\.channel.id).first == "sky")
        #expect(links.last?.channel.id == "ard")
    }

    @Test
    func `a channel the person chose before goes ahead of an equal one`() throws {
        let lines = [line("sky", "Bayern München - Dortmund"), line("ard", "Bayern München - Dortmund")]
        let first = try #require(resolve(lines, remembered: ["ard"]).first)
        #expect(first.channel.id == "ard")
    }

    @Test
    func `with no programme naming the match, sport at that time is offered to choose from`() throws {
        let links = resolve([
            line("gen", "Fußball Live", categories: ["Sports"]),
            line("movie", "Action Movie", categories: ["Film"])
        ])
        let link = try #require(links.first)
        #expect(links.count == 1)
        #expect(link.channel.id == "gen")
        #expect(link.score.reason == .genericSport)
        #expect(link.score.tier == .possible)
    }

    @Test
    func `sport at that time is not offered when a programme names the match`() {
        let links = resolve([
            line("sky", "Bayern München - Dortmund"),
            line("gen", "Fußball Live", categories: ["Sports"])
        ])
        #expect(links.map(\.channel.id) == ["sky"])
    }

    @Test
    func `the best line of a channel is the one kept`() {
        let links = resolve([
            line("sky", from: -120, for: 120, "Bundesliga Vorbericht"),
            line("sky", "Bayern München - Dortmund")
        ])
        #expect(links.count == 1)
        #expect(links.first?.programme.title == "Bayern München - Dortmund")
    }

    @Test
    func `a line for a channel that is not in the playlist is ignored`() {
        #expect(resolve([line("nowhere", "Bayern München - Dortmund")]).isEmpty)
    }

    @Test
    func `a match with no kick-off cannot be placed`() {
        let json = "{\"id\": 1, \"home_team\": \"A\", \"away_team\": \"B\"}"
        let fixture = try? JSONDecoder().decode(Fixture.self, from: Data(json.utf8))
        #expect(fixture.flatMap(MatchSignature.init) == nil)
    }
}

@Suite("the first look at a guide line")
struct PrefilterTests {
    private let kickoff = Date(timeIntervalSince1970: 1_792_077_000)
    private var match: MatchSignature {
        MatchSignature(
            home: TeamKey(name: "Bayern Munich", short: "Bayern"), away: TeamKey(
                name: "Borussia Dortmund",
                short: "Dortmund"
            ),
            league: LeagueKey(name: "Bundesliga"), kickoff: kickoff
        )
    }

    private func line(_ title: String, subtitle: String? = nil, categories: [String] = []) -> ProgrammeSnippet {
        ProgrammeSnippet(
            channelID: "c", start: kickoff, stop: kickoff.addingTimeInterval(7200), title: title,
            subtitle: subtitle, categories: categories
        )
    }

    @Test
    func `a line that names a team of the match is looked at`() {
        #expect(MatchChannelResolver.isCandidate(line("Bayern München - Leverkusen"), for: [match]))
        #expect(MatchChannelResolver.isCandidate(line("Bundesliga live", subtitle: "BVB gegen Mainz"), for: [match]))
    }

    @Test
    func `sport is looked at, so a generic title can still be found, and nothing else is`() {
        #expect(MatchChannelResolver.isCandidate(line("Football Live", categories: ["Sports"]), for: [match]))
        #expect(MatchChannelResolver.isCandidate(line("Fußball live aus Berlin"), for: [match]))
        #expect(!MatchChannelResolver.isCandidate(line("Tagesschau", categories: ["News"]), for: [match]))
        #expect(!MatchChannelResolver.isCandidate(line("Action Movie"), for: [match]))
    }
}
