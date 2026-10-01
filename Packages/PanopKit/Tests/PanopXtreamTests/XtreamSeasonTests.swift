import Foundation
@testable import PanopXtream
import Testing

@Suite("Series seasons")
struct XtreamSeasonTests {
    private func episode(_ season: Int, _ number: Int) -> XtreamEpisode {
        XtreamEpisode(
            id: "\(season)\(number)",
            seasonNumber: season,
            episodeNumber: number,
            title: "S\(season)E\(number)"
        )
    }

    private func info(_ episodes: [XtreamEpisode]) -> XtreamSeriesInfo {
        XtreamSeriesInfo(name: "Show", episodes: episodes)
    }

    @Test
    func `episodes group by season, each in order`() {
        let seasons = info([episode(2, 2), episode(1, 3), episode(1, 1), episode(2, 1), episode(1, 2)]).seasons

        #expect(seasons.map(\.number) == [1, 2])
        #expect(seasons[0].episodes.map(\.episodeNumber) == [1, 2, 3])
        #expect(seasons[1].episodes.map(\.episodeNumber) == [1, 2])
    }

    @Test
    func `specials come last, not first`() {
        let seasons = info([episode(0, 1), episode(1, 1), episode(2, 1)]).seasons

        #expect(seasons.map(\.number) == [1, 2, 0])
        #expect(seasons.last?.title == "Specials")
        #expect(seasons.first?.title == "Season 1")
    }

    @Test
    func `a series with no episodes has no seasons`() {
        #expect(info([]).seasons.isEmpty)
    }

    @Test
    func `seasons come out of a real panel response in order`() throws {
        let json = """
        {"info": {"name": "Show"},
         "episodes": {"2": [{"id": "20", "season": 2, "episode_num": 1, "title": "B"}],
                      "1": [{"id": "11", "season": 1, "episode_num": 2, "title": "A2"},
                            {"id": "10", "season": 1, "episode_num": 1, "title": "A1"}]}}
        """
        let decoded = try JSONDecoder().decode(XtreamSeriesInfo.self, from: Data(json.utf8))

        #expect(decoded.seasons.map(\.number) == [1, 2])
        #expect(decoded.seasons[0].episodes.map(\.title) == ["A1", "A2"])
    }
}
