import Foundation
@testable import Panop
import PanopCatalog
import PanopCore
import PanopEPG
import PanopSports
import SwiftData
import Testing

@Suite("Finding the channel that shows a match, in the guide")
struct MatchChannelReaderTests {
    private let kickoff = Date(timeIntervalSince1970: 1_792_077_000)

    private func container() throws -> ModelContainer {
        try PanopContainers.makeCatalog(inMemory: true)
    }

    private func fixture(
        _ id: Int = 1,
        home: String = "Bayern Munich",
        away: String = "Borussia Dortmund"
    ) throws -> Fixture {
        let json: [String: Any] = [
            "id": id, "league_id": 54, "league_name": "Bundesliga", "home_id": 17, "away_id": 18,
            "home_team": home, "home_short": home.split(separator: " ").first.map(String.init) ?? home,
            "away_team": away, "away_short": away.split(separator: " ").last.map(String.init) ?? away,
            "kickoff_utc": ISO8601DateFormatter().string(from: kickoff), "status": "Scheduled"
        ]
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func addChannel(
        _ context: ModelContext, playlist: String = "p1", id: String, name: String, epg: String,
        group: String = "DE | SPORT"
    ) {
        context.insert(CatalogEntryRecord(playlist: playlist, entry: CatalogEntry(
            id: id, kind: .live, name: name, groupName: group, epgKey: epg,
            streamURL: "http://127.0.0.1:9/live/\(id).ts"
        )))
    }

    private func addProgramme(
        _ context: ModelContext, playlist: String = "p1", channel: String, from minutes: Int = -5,
        for length: Int = 125,
        _ title: String, subtitle: String? = nil, details: String? = nil, categories: [String] = []
    ) {
        context.insert(EPGProgrammeRecord(playlist: playlist, programme: EPGProgramme(
            channelID: channel,
            start: kickoff.addingTimeInterval(TimeInterval(minutes * 60)),
            stop: kickoff.addingTimeInterval(TimeInterval((minutes + length) * 60)),
            title: title, subtitle: subtitle, details: details, categories: categories
        )))
    }

    private func read(
        _ container: ModelContainer, _ fixtures: [Fixture], remembered: [Int: Set<String>] = [:],
        favourites: Set<String> = []
    ) async -> MatchChannelReader.Output {
        await MatchChannelReader(container: container).read(MatchChannelReader.Request(
            fixtures: fixtures, playlists: ["p1", "p2"], remembered: remembered, favourites: favourites
        ))
    }

    @Test
    func `a channel whose guide names both teams is the match, and its row comes back to be played`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "sky1", name: "Sky Sport Bundesliga 1 HD", epg: "skybl1.de")
        addChannel(context, id: "movie", name: "Movie Channel", epg: "movie.de", group: "Films")
        addProgramme(context, channel: "SkyBL1.de", "Bundesliga: FC Bayern München - Borussia Dortmund")
        addProgramme(context, channel: "movie.de", "Action Movie", categories: ["Film"])
        try context.save()

        let output = try await read(catalog, [fixture()])
        let link = try #require(output.links[1]?.first)
        #expect(link.channel.name == "Sky Sport Bundesliga 1 HD")
        #expect(link.score.tier == .watch)
        #expect(output.rows[link.channel.id]?.streamURL == "http://127.0.0.1:9/live/sky1.ts")
        #expect(output.links[1]?.count == 1)
    }

    @Test
    func `of several versions of a channel the best is offered`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "sd", name: "Sky Sport 1 SD", epg: "sky1.de")
        addChannel(context, id: "uhd", name: "Sky Sport 1 UHD", epg: "sky1.de")
        addChannel(context, id: "hd", name: "Sky Sport 1 HD", epg: "sky1.de")
        addProgramme(context, channel: "sky1.de", "Bayern München - Dortmund")
        try context.save()

        let output = try await read(catalog, [fixture()])
        #expect(output.links[1]?.count == 1)
        #expect(output.links[1]?.first?.channel.name == "Sky Sport 1 UHD")
    }

    @Test
    func `a generic title is the match when the description names the teams`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "dazn", name: "DAZN 1", epg: "dazn1.de")
        addProgramme(
            context, channel: "dazn1.de", "Football Live",
            details: "Der Klassiker: FC Bayern gegen Borussia Dortmund. Bundesliga, 27. Spieltag.",
            categories: ["Sports"]
        )
        try context.save()
        let output = try await read(catalog, [fixture()])
        #expect(output.links[1]?.first?.score.reason == .bothTeamsInText)
    }

    @Test
    func `sport that names no team is offered to choose from`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "gen", name: "Sport Channel", epg: "sport.de")
        addProgramme(context, channel: "sport.de", "Fußball Live", categories: ["Sports"])
        try context.save()
        let link = try #require(await read(catalog, [fixture()]).links[1]?.first)
        #expect(link.score.reason == .genericSport)
        #expect(link.score.tier == .possible)
    }

    @Test
    func `nothing in the guide, or only other programmes, finds nothing`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "news", name: "News", epg: "news.de", group: "News")
        addProgramme(context, channel: "news.de", "Tagesschau", categories: ["News"])
        try context.save()
        #expect(try await read(catalog, [fixture()]).links.isEmpty)
        #expect(try await read(catalog, []).links.isEmpty)
    }

    @Test
    func `the guide of a playlist that is not asked about is not read`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, playlist: "other", id: "sky1", name: "Sky Sport 1", epg: "sky1.de")
        addProgramme(context, playlist: "other", channel: "sky1.de", "Bayern München - Dortmund")
        try context.save()
        #expect(try await read(catalog, [fixture()]).links.isEmpty)
    }

    @Test
    func `a channel chosen before, and a favourite, go ahead of an equal one`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "a", name: "Alpha Sport", epg: "a.de")
        addChannel(context, id: "b", name: "Beta Sport", epg: "b.de")
        addProgramme(context, channel: "a.de", "Bayern München - Dortmund")
        addProgramme(context, channel: "b.de", "Bayern München - Dortmund")
        try context.save()
        let plain = try await read(catalog, [fixture()])
        #expect(plain.links[1]?.map(\.channel.name) == ["Alpha Sport", "Beta Sport"])
        let chosen = try await read(catalog, [fixture()], remembered: [54: ["p1|b"]])
        #expect(chosen.links[1]?.first?.channel.name == "Beta Sport")
    }

    @Test
    func `several matches are found in one pass, each with its own channels`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        addChannel(context, id: "a", name: "Alpha Sport", epg: "a.de")
        addChannel(context, id: "b", name: "Beta Sport", epg: "b.de")
        addProgramme(context, channel: "a.de", "Bayern München - Dortmund")
        addProgramme(context, channel: "b.de", "Mainz 05 - Freiburg")
        try context.save()
        let second = try fixture(2, home: "1. FSV Mainz 05", away: "SC Freiburg")
        let output = try await read(catalog, [fixture(), second])
        #expect(output.links[1]?.first?.channel.name == "Alpha Sport")
        #expect(output.links[2]?.first?.channel.name == "Beta Sport")
    }

    @Test
    func `the quality of a channel is read from its name`() {
        #expect(MatchChannelReader.quality(of: "Sky Sport 1 UHD") == 3)
        #expect(MatchChannelReader.quality(of: "DAZN 4K") == 3)
        #expect(MatchChannelReader.quality(of: "Sky Sport 1 FHD") == 2)
        #expect(MatchChannelReader.quality(of: "Sky Sport 1 HD") == 1)
        #expect(MatchChannelReader.quality(of: "Sky Sport 1") == 1)
        #expect(MatchChannelReader.quality(of: "Sky Sport 1 SD") == 0)
    }

    @Test
    func `a big guide is read in a fraction of a second`() async throws {
        let catalog = try container()
        let context = ModelContext(catalog)
        for channel in 0 ..< 400 {
            addChannel(context, id: "c\(channel)", name: "Channel \(channel)", epg: "ch\(channel).de", group: "DE | TV")
            // A day's guide for each channel: dozens of lines, of which only those at the match's time matter.
            for slot in 0 ..< 60 {
                addProgramme(
                    context, channel: "ch\(channel).de", from: (slot - 30) * 40, for: 40,
                    channel % 100 == 7 && slot == 30 ? "Bundesliga: Bayern München - Dortmund" : "Programme \(channel)-\(slot)"
                )
            }
        }
        try context.save()
        let clock = ContinuousClock()
        var output = MatchChannelReader.Output()
        let match = try fixture()
        let elapsed = await clock.measure { output = await read(catalog, [match]) }
        #expect(output.links[1]?.count == 4)
        // 24,000 guide lines in a debug build with a store on disk; the real figure is measured in Release.
        #expect(elapsed < .seconds(5), "took \(elapsed)")
    }
}
