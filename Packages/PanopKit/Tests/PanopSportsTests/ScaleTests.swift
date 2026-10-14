import Foundation
@testable import PanopSports
import Testing

@Suite("matching at the size of a real guide")
struct ScaleTests {
    @Test
    func `twenty matches against thousands of guide lines is quick`() {
        let kickoff = Date(timeIntervalSince1970: 1_792_077_000)
        let clubs = [
            "Bayern",
            "Dortmund",
            "Leverkusen",
            "Leipzig",
            "Stuttgart",
            "Freiburg",
            "Mainz",
            "Bremen",
            "Köln",
            "Hertha"
        ]
        // A guide for 600 channels: mostly programmes that are not football, a few that are.
        var lines: [PreparedProgramme] = []
        var channels: [String: ChannelCandidate] = [:]
        for channel in 0 ..< 600 {
            let id = "c\(channel)"
            channels[id] = ChannelCandidate(
                id: id,
                name: "Channel \(channel)",
                group: channel % 9 == 0 ? "DE | SPORT" : "DE | TV"
            )
            for slot in 0 ..< 9 {
                let title = slot == 4 && channel % 40 == 0
                    ? "Bundesliga: \(clubs[channel % 10]) - \(clubs[(channel + 3) % 10])"
                    : "Programme \(channel)-\(slot) mit Nachrichten und Wetter"
                lines.append(PreparedProgramme(ProgrammeSnippet(
                    channelID: id,
                    start: kickoff.addingTimeInterval(TimeInterval((slot - 4) * 40 * 60)),
                    stop: kickoff.addingTimeInterval(TimeInterval((slot - 3) * 40 * 60)),
                    title: title, details: "Eine Sendung. " + String(repeating: "Text ", count: 40)
                )))
            }
        }
        let matches = (0 ..< 20).map { number in
            MatchSignature(
                home: TeamKey(name: clubs[number % 10]), away: TeamKey(name: clubs[(number + 3) % 10]),
                league: LeagueKey(name: "Bundesliga"), kickoff: kickoff
            )
        }
        let clock = ContinuousClock()
        var found = 0
        let elapsed = clock.measure {
            for match in matches {
                found += MatchChannelResolver.resolve(match, programmes: lines, channels: channels).count
            }
        }
        // Generous for an unoptimised test build: a release build takes about a tenth of a second.
        #expect(elapsed < .seconds(8), "took \(elapsed)")
        #expect(found > 0)
    }
}
