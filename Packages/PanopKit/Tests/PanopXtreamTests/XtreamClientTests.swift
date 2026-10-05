import Foundation
import PanopCore
@testable import PanopXtream
import Testing

private let credentials = ProviderCredentials(
    baseURL: "http://panel.example:8080",
    username: "alice",
    password: "s3cret"
)

private func client(
    _ transport: StubTransport,
    credentials: ProviderCredentials = credentials
) throws -> XtreamClient {
    try XtreamClient(credentials: credentials, transport: transport)
}

private func collect<Item>(_ batches: XtreamBatches<Item>) async throws -> [[Item]] {
    var result: [[Item]] = []
    for try await batch in batches {
        result.append(batch)
    }
    return result
}

@Suite("Xtream client")
struct XtreamClientTests {
    // MARK: - Base URL and request building

    @Test(arguments: [
        "http://host:8080/",
        "http://host:8080",
        "  http://host:8080/  ",
        "http://host:8080/get.php?username=a&password=b&type=m3u_plus",
        "http://host:8080/player_api.php?username=a"
    ])
    func `normalizes pasted base URLs`(raw: String) throws {
        let transport = StubTransport(body: "[]")
        let sut = try client(transport, credentials: .init(baseURL: raw, username: "u", password: "p"))
        #expect(sut.liveURL(streamID: 1)?.absoluteString == "http://host:8080/live/u/p/1.m3u8")
    }

    @Test
    func `keeps a path prefix`() throws {
        let sut = try client(
            StubTransport(body: "[]"),
            credentials: .init(baseURL: "https://host/panel/", username: "u", password: "p")
        )
        #expect(sut.liveURL(streamID: 1)?.absoluteString == "https://host/panel/live/u/p/1.m3u8")
    }

    @Test(arguments: ["", "host:8080", "ftp://host", "http://", "not a url"])
    func `rejects unusable base URLs`(raw: String) {
        #expect(throws: XtreamError.invalidBaseURL) {
            _ = try client(StubTransport(body: "[]"), credentials: .init(baseURL: raw, username: "u", password: "p"))
        }
    }

    /// URLComponents leaves `+` and `&` alone in a query value, which would
    /// silently corrupt this password. The panel would answer auth failure and
    /// the user would blame their credentials.
    @Test
    func `escapes reserved characters in credentials`() async throws {
        let transport = StubTransport(body: "[]")
        let sut = try client(
            transport,
            credentials: .init(baseURL: "http://h", username: "a b", password: "p&ss+w=rd/#")
        )
        _ = try await sut.liveCategories()

        let query = try #require(transport.requests.last?.url.query)
        #expect(query.contains("username=a%20b"))
        #expect(query.contains("password=p%26ss%2Bw%3Drd%2F%23"))
        #expect(transport.lastQuery("password") == "p&ss+w=rd/#")
    }

    @Test
    func `builds stream URLs for each kind`() throws {
        let sut = try client(StubTransport(body: "[]"))
        #expect(sut.liveURL(streamID: 7, format: .transportStream)?.absoluteString
            == "http://panel.example:8080/live/alice/s3cret/7.ts")
        #expect(sut.movieURL(streamID: 9, containerExtension: "mkv")?.absoluteString
            == "http://panel.example:8080/movie/alice/s3cret/9.mkv")
        #expect(sut.movieURL(streamID: 9, containerExtension: nil)?.absoluteString.hasSuffix("/9.mp4") == true)
        #expect(sut.episodeURL(episodeID: "551", containerExtension: "mp4")?.absoluteString
            == "http://panel.example:8080/series/alice/s3cret/551.mp4")
    }

    // MARK: - Authentication

    @Test
    func `authenticates and reads account details`() async throws {
        let body = """
        {"user_info":{"username":"alice","auth":1,"status":"Active","exp_date":"1893456000",
        "is_trial":"0","active_cons":"1","max_connections":"2","allowed_output_formats":["m3u8","ts"]},
        "server_info":{"url":"panel.example"}}
        """
        let account = try await client(StubTransport(body: body)).authenticate()
        #expect(account.username == "alice")
        #expect(account.status == "Active")
        #expect(account.maxConnections == 2)
        #expect(account.activeConnections == 1)
        #expect(account.isTrial == false)
        #expect(account.allowedFormats == ["m3u8", "ts"])
        #expect(account.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test(arguments: [#"{"user_info":{"auth":0}}"#, #"{"user_info":{"auth":"0"}}"#, #"{"user_info":{}}"#])
    func `bad credentials fail even on HTTP 200`(body: String) async {
        await #expect(throws: XtreamError.authenticationFailed) {
            _ = try await client(StubTransport(body: body)).authenticate()
        }
    }

    @Test
    func `a non-Xtream reply is an unexpected response`() async {
        await #expect(throws: XtreamError.unexpectedResponse) {
            _ = try await client(StubTransport(body: "<html>hello</html>")).authenticate()
        }
    }

    @Test
    func `non-2xx status is reported`() async {
        await #expect(throws: XtreamError.http(status: 503)) {
            _ = try await client(StubTransport(status: 503, body: "")).liveCategories()
        }
    }

    // MARK: - Categories

    @Test
    func `decodes categories with mixed types`() async throws {
        let body = """
        [{"category_id":"1","category_name":"News","parent_id":0},
         {"category_id":2,"category_name":"Sport","parent_id":"1"},
         {"category_name":"No id, dropped"}]
        """
        let categories = try await client(StubTransport(body: body)).liveCategories()
        #expect(categories == [
            XtreamCategory(id: "1", name: "News"),
            XtreamCategory(id: "2", name: "Sport", parentID: "1")
        ])
    }

    // MARK: - Big lists

    @Test
    func `decodes live streams whatever the JSON types`() async throws {
        let body = """
        [{"num":1,"name":"Das Erste","stream_id":"101","stream_icon":"http://i/1.png",
          "epg_channel_id":"ard.de","added":"1700000000","category_id":"5",
          "tv_archive":1,"tv_archive_duration":"3","direct_source":""},
         {"num":"2","name":null,"stream_id":102,"stream_icon":null,"epg_channel_id":null,
          "added":0,"category_id":5,"tv_archive":"0","tv_archive_duration":0}]
        """
        let batches = try await collect(client(StubTransport(body: body)).liveStreams())
        let streams = batches.flatMap(\.self)
        #expect(streams.count == 2)

        #expect(streams[0].streamID == 101)
        #expect(streams[0].name == "Das Erste")
        #expect(streams[0].epgChannelID == "ard.de")
        #expect(streams[0].categoryID == "5")
        #expect(streams[0].added == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(streams[0].hasArchive)
        #expect(streams[0].archiveDays == 3)
        #expect(streams[0].directSource == nil)

        #expect(streams[1].streamID == 102)
        #expect(streams[1].name.isEmpty)
        #expect(streams[1].number == 2)
        #expect(streams[1].added == nil)
        #expect(!streams[1].hasArchive)
    }

    @Test
    func `decodes movies and series`() async throws {
        let movies = try await collect(client(StubTransport(
            body: #"[{"stream_id":"9","name":"Heat","rating":"7.9","container_extension":"mkv","category_id":"3"}]"#
        )).movies()).flatMap(\.self)
        #expect(movies == [XtreamMovie(
            streamID: 9,
            name: "Heat",
            rating: 7.9,
            categoryID: "3",
            containerExtension: "mkv"
        )])

        let series = try await collect(client(StubTransport(
            body: """
            [{"series_id":"40","name":"Lost","cover":"c.jpg","rating":8,"releaseDate":"2004-09-22",
              "backdrop_path":["b1.jpg","b2.jpg"],"last_modified":"1700000000"}]
            """
        )).series()).flatMap(\.self)
        #expect(series.first?.seriesID == 40)
        #expect(series.first?.releaseDate == "2004-09-22")
        #expect(series.first?.backdropURLs == ["b1.jpg", "b2.jpg"])
        #expect(series.first?.rating == 8)
    }

    @Test(arguments: [1, 7, 4096])
    func `batches large lists at every chunk size`(chunkSize: Int) async throws {
        let rows = (1 ... 1200).map { #"{"stream_id":\#($0),"name":"Channel \#($0)"}"# }
        let body = "[" + rows.joined(separator: ",") + "]"
        let transport = StubTransport(chunkSize: chunkSize, body: body)

        let batches = try await collect(client(transport).liveStreams(batchSize: 500))
        #expect(batches.map(\.count) == [500, 500, 200])
        #expect(batches.flatMap(\.self).map(\.streamID) == Array(1 ... 1200))
    }

    @Test
    func `a category filter is sent as a query parameter`() async throws {
        let transport = StubTransport(body: "[]")
        _ = try await collect(client(transport).liveStreams(categoryID: "42"))
        #expect(transport.lastQuery("action") == "get_live_streams")
        #expect(transport.lastQuery("category_id") == "42")
    }

    @Test
    func `nothing is requested until iteration starts`() async throws {
        let transport = StubTransport(body: "[]")
        let batches = try client(transport).liveStreams()
        #expect(transport.requests.isEmpty)
        _ = try await collect(batches)
        #expect(transport.requests.count == 1)
    }

    /// One bad row in an 80,000-row catalog costs one row.
    @Test
    func `rows without an identifier are dropped`() async throws {
        let body = #"[{"stream_id":1,"name":"a"},{"name":"orphan"},{"stream_id":3,"name":"c"}]"#
        let streams = try await collect(client(StubTransport(chunkSize: 5, body: body)).liveStreams()).flatMap(\.self)
        #expect(streams.map(\.streamID) == [1, 3])
    }

    @Test
    func `an empty list yields no batches`() async throws {
        #expect(try await collect(client(StubTransport(body: "[]")).liveStreams()).isEmpty)
        #expect(try await collect(client(StubTransport(body: "null")).liveStreams()).isEmpty)
    }

    /// If this ever returned the rows read so far, a reconcile would delete
    /// everything past the cut as "removed by the provider".
    @Test
    func `a truncated download fails instead of returning a partial list`() async {
        let body = #"[{"stream_id":1,"name":"a"},{"stream_id":2,"na"#
        await #expect(throws: XtreamError.truncatedResponse) {
            _ = try await collect(client(StubTransport(chunkSize: 8, body: body)).liveStreams())
        }
    }

    @Test
    func `an error object is not mistaken for an empty list`() async {
        await #expect(throws: XtreamError.unexpectedResponse) {
            _ = try await collect(client(StubTransport(body: #"{"error":"rate limited"}"#)).liveStreams())
        }
    }

    @Test
    func `HTTP failure on a big list is reported`() async {
        await #expect(throws: XtreamError.http(status: 403)) {
            _ = try await collect(client(StubTransport(status: 403, body: "")).movies())
        }
    }

    // MARK: - Detail endpoints

    @Test
    func `decodes series info with episodes grouped by season`() async throws {
        let body = """
        {"info":{"name":"Lost","plot":"Island.","cover":"c.jpg","genre":"Drama"},
         "episodes":{
           "2":[{"id":"12","season":2,"episode_num":"1","title":"S2E1","container_extension":"mkv",
                 "info":{"duration_secs":2700,"plot":"p","movie_image":"e.jpg"}}],
           "1":[{"id":13,"season":1,"episode_num":2,"title":"S1E2","container_extension":"mp4","info":[]},
                {"id":11,"season":1,"episode_num":1,"title":"S1E1","container_extension":"mp4","info":[]},
                {"title":"no id, dropped"}]
         }}
        """
        let info = try await client(StubTransport(body: body)).seriesInfo(seriesID: 40)
        #expect(info.name == "Lost")
        #expect(info.genre == "Drama")
        // Season keys arrive in arbitrary order; the result must not.
        #expect(info.episodes.map(\.id) == ["11", "13", "12"])
        #expect(info.episodes.last?.durationSeconds == 2700)
        #expect(info.episodes.last?.imageURL == "e.jpg")
    }

    @Test
    func `decodes the series' rating, people, dates, trailer and each episode's picture and file details`(
    ) async throws {
        let body = """
        {"info":{"name":"Lost","plot":"Island.","cover":"c.jpg","genre":"Drama, Mystery","cast":"A, B","director":"C",
                 "release_date":"2004-09-22","rating":"8.4","episode_run_time":"43","backdrop_path":["b1.jpg","b2.jpg"],
                 "youtube_trailer":"abc123"},
         "episodes":{"1":[{"id":"11","season":1,"episode_num":1,"title":"Pilot","container_extension":"mkv",
            "info":{"air_date":"2004-09-22","rating":7.5,"duration_secs":2700,
                    "video":{"height":1080,"codec_name":"hevc"},"audio":{"codec_name":"ac3"}}},
           {"id":"12","season":1,"episode_num":2,"title":"Two","container_extension":"mkv",
            "info":{"video":[],"audio":[]}}]}}
        """
        let info = try await client(StubTransport(body: body)).seriesInfo(seriesID: 40)
        #expect(info.cast == "A, B")
        #expect(info.director == "C")
        #expect(info.releaseDate == "2004-09-22")
        #expect(info.rating == 8.4)
        #expect(info.episodeRunTime == 43)
        #expect(info.backdropURLs == ["b1.jpg", "b2.jpg"])
        #expect(info.trailer == "abc123")
        let pilot = try #require(info.episodes.first)
        #expect(pilot.airDate == "2004-09-22")
        #expect(pilot.rating == 7.5)
        #expect(pilot.videoHeight == 1080)
        #expect(pilot.videoCodec == "hevc")
        #expect(pilot.audioCodec == "ac3")
        let two = try #require(info.episodes.last)
        #expect(two.videoHeight == nil, "a panel that has not probed the file sends [] for it")
        #expect(two.audioCodec == nil)
    }

    /// A show with no episodes yet has `"episodes": []`, not `{}`.
    @Test
    func `series info tolerates an empty episode array and info`() async throws {
        let info = try await client(StubTransport(body: #"{"info":[],"episodes":[]}"#)).seriesInfo(seriesID: 1)
        #expect(info.episodes.isEmpty)
    }

    @Test
    func `decodes short EPG including base64 text`() async throws {
        let title = Data("Tagesschau".utf8).base64EncodedString()
        let plain = "Not encoded"
        let body = """
        {"epg_listings":[
          {"title":"\(title)","description":"\(Data("News".utf8).base64EncodedString())",
           "start_timestamp":"1700000000","stop_timestamp":"1700003600","channel_id":"ard.de"},
          {"title":"\(plain)","start_timestamp":1700003600,"stop_timestamp":1700007200},
          {"title":"no times"}]}
        """
        let transport = StubTransport(body: body)
        let listings = try await client(transport).shortEPG(streamID: 101, limit: 2)

        #expect(listings.count == 2)
        #expect(listings[0].title == "Tagesschau")
        #expect(listings[0].details == "News")
        #expect(listings[0].channelID == "ard.de")
        #expect(listings[0].end.timeIntervalSince(listings[0].start) == 3600)
        #expect(listings[1].title == plain)
        #expect(transport.lastQuery("stream_id") == "101")
        #expect(transport.lastQuery("limit") == "2")
    }

    // MARK: - Errors

    /// Errors get logged, and the request URL they come from holds the password.
    @Test
    func `transport errors never carry credentials`() async {
        let transport = StubTransport { request in
            throw NSError(
                domain: "test",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not connect to \(request.url.absoluteString) as alice with s3cret"
                ]
            )
        }
        do {
            _ = try await client(transport).liveCategories()
            Issue.record("expected a throw")
        } catch let XtreamError.transport(message) {
            #expect(!message.contains("s3cret"))
            #expect(!message.contains("alice"))
            #expect(message.contains("<redacted>"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
