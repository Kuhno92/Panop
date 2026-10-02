import Foundation
import PanopCore
@testable import PanopXtream
import Testing

@Suite("Xtream film details")
struct XtreamMovieInfoTests {
    private func decode(_ json: String) throws -> XtreamMovieInfo {
        try JSONDecoder().decode(XtreamMovieInfo.self, from: Data(json.utf8))
    }

    @Test
    func `a full answer is read`() throws {
        let info = try decode("""
        {"info":{"movie_image":"http://i/p.jpg","backdrop_path":["http://i/b1.jpg","http://i/b2.jpg"],
        "plot":"A crew meets something.","cast":"Sigourney Weaver, Tom Skerritt","director":"Ridley Scott",
        "genre":"Horror, Sci-Fi","country":"UK","releasedate":"1979-05-25","rating":"8.5",
        "duration_secs":7020,"youtube_trailer":"abc123"},"movie_data":{"stream_id":7}}
        """)

        #expect(info.plot == "A crew meets something.")
        #expect(info.cast == "Sigourney Weaver, Tom Skerritt")
        #expect(info.director == "Ridley Scott")
        #expect(info.genre == "Horror, Sci-Fi")
        #expect(info.year == 1979)
        #expect(info.rating == 8.5)
        #expect(info.durationSeconds == 7020)
        #expect(info.coverURL == "http://i/p.jpg")
        #expect(info.backdropURLs == ["http://i/b1.jpg", "http://i/b2.jpg"])
        #expect(info.trailer == "abc123")
    }

    @Test
    func `numbers that arrive as strings, and a single backdrop as a bare string`() throws {
        let info =
            try decode(#"{"info":{"duration_secs":"5400","rating":7.2,"backdrop_path":"http://i/b.jpg","year":2021}}"#)

        #expect(info.durationSeconds == 5400)
        #expect(info.rating == 7.2)
        #expect(info.backdropURLs == ["http://i/b.jpg"])
        #expect(info.year == 2021)
    }

    @Test
    func `a panel with only a five-point rating and a clock duration`() throws {
        let info =
            try decode(#"{"info":{"rating":"0","rating_5based":3.5,"duration":"01:32:10","description":"Plain."}}"#)

        #expect(info.rating == 7.0)
        #expect(info.durationSeconds == 5530)
        #expect(info.plot == "Plain.")
    }

    @Test
    func `an unknown film, with info as an empty array, is an empty answer`() throws {
        let info = try decode(#"{"info":[],"movie_data":{}}"#)

        #expect(info == XtreamMovieInfo())
    }

    @Test(arguments: [("1979-05-25", 1979), ("05/25/1979", 1979), ("1979", 1979), ("sometime", nil)])
    func `the year is found in the usual date forms`(date: String, year: Int?) {
        #expect(XtreamMovieInfo(releaseDate: date).year == year)
    }

    @Test
    func `the client asks for the film by id`() async throws {
        let transport = StubTransport(body: #"{"info":{"plot":"P"}}"#)
        let client = try XtreamClient(
            credentials: ProviderCredentials(baseURL: "http://p.example", username: "u", password: "w"),
            transport: transport
        )

        let info = try await client.movieInfo(streamID: 42)

        #expect(info.plot == "P")
        #expect(transport.lastQuery("action") == "get_vod_info")
        #expect(transport.lastQuery("vod_id") == "42")
    }
}
