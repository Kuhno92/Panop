import Foundation
@testable import PanopPlaylist
import Testing

@Suite("Episode titles")
struct EpisodeTitleTests {
    @Test(arguments: [
        ("Dark S01E05", "Dark", 1, 5, nil),
        ("Dark s1e5", "Dark", 1, 5, nil),
        ("Dark - S01E05 - Der Anfang", "Dark", 1, 5, "Der Anfang"),
        ("Dark.S01.E05.German.1080p", "Dark", 1, 5, "German.1080p"),
        ("Dark S01 E05", "Dark", 1, 5, nil),
        ("Dark S01-E05", "Dark", 1, 5, nil),
        ("Dark 1x05", "Dark", 1, 5, nil),
        ("Dark 12x105", "Dark", 12, 105, nil),
        ("Dark Season 1 Episode 5", "Dark", 1, 5, nil),
        ("Dark - Season 01 - Ep 05 - Title", "Dark", 1, 5, "Title"),
        ("Dark - season 2 episode 10", "Dark", 2, 10, nil),
        ("The Office (US) S09E23", "The Office (US)", 9, 23, nil),
        ("DE - Dark S02E01", "DE - Dark", 2, 1, nil),
        ("  Dark   S01E05  ", "Dark", 1, 5, nil),
        ("Marvel's Agents of S.H.I.E.L.D. S03E12", "Marvel's Agents of S.H.I.E.L.D.", 3, 12, nil)
    ])
    func `the usual ways of writing it`(
        name: String, series: String, season: Int, episode: Int, title: String?
    ) throws {
        let parsed = try #require(EpisodeTitle.parse(name), "no episode found in \(name)")

        #expect(parsed.series == series)
        #expect(parsed.season == season)
        #expect(parsed.episode == episode)
        #expect(parsed.title == title)
    }

    @Test(arguments: [
        "A Film (2019)",
        "Dark Matter 2",
        "Channel 5 HD",
        "S01E05",
        " - S01E05",
        "Mars1x05",
        "Dark S01",
        "Dark E05",
        "Mission 1x5",
        "Esperanza S1E",
        "Dune Part 2",
        ""
    ])
    func `names that are not episodes are left alone`(name: String) {
        #expect(EpisodeTitle.parse(name) == nil, "\(name) read as an episode")
    }

    @Test
    func `different spellings of one show share a key, different shows do not`() throws {
        let one = try #require(EpisodeTitle.parse("Dark S01E01"))
        let two = try #require(EpisodeTitle.parse("DARK  s02e07"))
        let other = try #require(EpisodeTitle.parse("Dark Matter S01E01"))

        #expect(one.seriesKey == two.seriesKey)
        #expect(one.seriesKey != other.seriesKey)
    }

    @Test
    func `a number inside a word is not a season`() {
        #expect(EpisodeTitle.parse("Crossfire S1E5") != nil)
        // "ts1e5" is a word with digits in it, not a season marker.
        #expect(EpisodeTitle.parse("Pets1e5") == nil)
    }

    @Test
    func `the leftmost reading wins`() throws {
        let parsed = try #require(EpisodeTitle.parse("Show 2x05 S09E09"))

        #expect(parsed.season == 2)
        #expect(parsed.episode == 5)
    }

    /// A playlist can have hundreds of thousands of these, and the parser runs on every one.
    @Test
    func `it is fast enough for a very large playlist`() {
        let names = (0 ..< 20000)
            .map { "Some Long Series Title Number \($0 % 500) S\($0 % 9 + 1)E\($0 % 30 + 1) - Episode Name Here" }
        let start = ContinuousClock.now

        var found = 0
        for name in names where EpisodeTitle.parse(name) != nil {
            found += 1
        }

        let elapsed = ContinuousClock.now - start
        #expect(found == 20000)
        #expect(elapsed < .seconds(1), "20,000 names took \(elapsed)")
    }
}
