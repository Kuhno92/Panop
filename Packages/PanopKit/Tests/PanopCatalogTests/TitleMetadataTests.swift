import Foundation
@testable import PanopCatalog
import PanopCore
import PanopXtream
import Testing

@Suite("Title metadata")
struct TitleMetadataTests {
    @Test(arguments: [
        ("Backrooms (2026)", 2026),
        ("DE - Backrooms (2026)", 2026),
        ("Widow's Bay (2026) (US)", 2026),
        ("Toy Story (1995)", 1995),
        ("2001: A Space Odyssey (1968)", 1968),
        ("Blade Runner (1982) (2049)", 2049)
    ])
    func `the year written at the end of a title is read`(title: String, year: Int) {
        #expect(TitleMetadata.year(fromTitle: title) == year)
    }

    @Test(arguments: ["Heat", "(US)", "Sunset Blvd (123)", "Film (0000)", "Film (9999)", "Unclosed (2020", ""])
    func `no year is invented when the title has none`(title: String) {
        #expect(TitleMetadata.year(fromTitle: title) == nil)
    }

    @Test(arguments: [("2026", 2026), ("2026-05-01", 2026), ("2026/05/01", 2026), (" 1999 ", 1999)])
    func `the year at the start of a date is read`(date: String, year: Int) {
        #expect(TitleMetadata.year(fromDate: date) == year)
    }

    @Test(arguments: ["", "May 2026", "20", "abcd", "9999"])
    func `a date with no usable year is nil`(date: String) {
        #expect(TitleMetadata.year(fromDate: date) == nil)
    }

    @Test(arguments: [
        "VOD - ADULT +18", "FOR ADULTS", "XXX Movies", "Adults Only", "Erotik", "Porn", "18+", "SRS - ADULT"
    ])
    func `a category named as adult content is recognised`(name: String) {
        #expect(TitleMetadata.isAdultCategory(name))
    }

    @Test(arguments: [
        "VOD - GERMANY KINDER [DE]", "Adult Swim", "ADULT SWIM [US]", "Comedy", "Sex Education Collection",
        "Madulthood", "News", ""
    ])
    func `an ordinary category is not`(name: String) {
        #expect(!TitleMetadata.isAdultCategory(name))
    }

    @Test
    func `no category is not adult`() {
        #expect(!TitleMetadata.isAdultCategory(nil))
    }
}

@Suite("Discovery fields from a provider")
struct DiscoveryFieldsTests {
    private let credentials = ProviderCredentials(baseURL: "http://p.example", username: "u", password: "w")

    private func panel() -> StubTransport {
        StubTransport { request in
            guard let action = query(request, "action") else {
                return (200, #"{"user_info":{"username":"u","auth":1,"status":"Active"}}"#)
            }
            return switch action {
            case "get_vod_categories":
                (
                    200,
                    #"[{"category_id":"1","category_name":"Films"},{"category_id":"9","category_name":"VOD - ADULT +18"}]"#
                )
            case "get_vod_streams":
                (200, """
                [{"stream_id":1,"name":"Backrooms (2026)","category_id":"1","tmdb_id":"123","year":"2026","is_adult":0},
                 {"stream_id":2,"name":"No Year Here","category_id":"1","tmdb_id":0,"year":""},
                 {"stream_id":3,"name":"Flagged","category_id":"1","is_adult":1},
                 {"stream_id":4,"name":"Named Adult","category_id":"9"},
                 {"stream_id":5,"name":"Old Film (1950)","category_id":"1","year":"","genre":"Drama","cast":"A, B"}]
                """)
            case "get_series_categories":
                (200, #"[{"category_id":"3","category_name":"Shows"}]"#)
            case "get_series":
                (200, """
                [{"series_id":10,"name":"Reacher","category_id":"3","tmdb_id":"108978","release_date":"2022-02-04",
                  "genre":"Krimi / Drama","cast":"Alan Ritchson"},
                 {"series_id":11,"name":"Show (2019)","category_id":"3","tmdb_id":""}]
                """)
            case "get_live_categories":
                (200, #"[{"category_id":"5","category_name":"FOR ADULTS"},{"category_id":"6","category_name":"News"}]"#)
            case "get_live_streams":
                (200, """
                [{"stream_id":20,"name":"Adult One","category_id":"5","is_adult":0},
                 {"stream_id":21,"name":"Tagesschau","category_id":"6"}]
                """)
            default: (200, "[]")
            }
        }
    }

    private func imported() async throws -> [String: CatalogEntry] {
        let store = InMemoryCatalogStore()
        _ = try await CatalogImporter(store: store, transport: panel())
            .importXtream(playlist: "x", credentials: credentials)
        return await Dictionary(uniqueKeysWithValues: store.allEntries(playlist: "x").map { ($0.name, $0) })
    }

    @Test
    func `a movie keeps its TMDB id, year and flags`() async throws {
        let entries = try await imported()

        let backrooms = try #require(entries["Backrooms (2026)"])
        #expect(backrooms.tmdbID == 123)
        #expect(backrooms.year == 2026)
        #expect(!backrooms.isAdult)
        #expect(entries["No Year Here"]?.tmdbID == nil, "a zero id is no id")
    }

    @Test
    func `the year falls back to the title, and an empty field is not a year`() async throws {
        let entries = try await imported()

        #expect(entries["Old Film (1950)"]?.year == 1950)
        #expect(entries["No Year Here"]?.year == nil)
    }

    @Test
    func `adult is the provider's flag or the category's name`() async throws {
        let entries = try await imported()

        #expect(entries["Flagged"]?.isAdult == true, "the flag")
        #expect(entries["Named Adult"]?.isAdult == true, "the category name, with no flag")
        #expect(entries["Backrooms (2026)"]?.isAdult == false)
        #expect(
            entries["Adult One"]?.isAdult == true,
            "a live channel in an adult category, which the panel did not flag"
        )
        #expect(entries["Tagesschau"]?.isAdult == false)
    }

    @Test
    func `a series keeps its genre, cast, TMDB id and the year of its release date`() async throws {
        let entries = try await imported()

        let reacher = try #require(entries["Reacher"])
        #expect(reacher.tmdbID == 108_978)
        #expect(reacher.genre == "Krimi / Drama")
        #expect(reacher.cast == "Alan Ritchson")
        #expect(reacher.year == 2022)
        #expect(entries["Show (2019)"]?.year == 2019, "from the title when the panel gives no date")
    }

    @Test
    func `movie genre and cast are kept when a panel fills them`() async throws {
        let entries = try await imported()

        #expect(entries["Old Film (1950)"]?.genre == "Drama")
        #expect(entries["Old Film (1950)"]?.cast == "A, B")
    }

    @Test
    func `an M3U entry gets its year from the title and adult from its group`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:5400 group-title="Films",Heat (1995)
        http://h/movie/u/p/1.mp4
        #EXTINF:5400 group-title="ADULT +18",Something
        http://h/movie/u/p/2.mp4
        """
        _ = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let entries = await Dictionary(uniqueKeysWithValues: store.allEntries(playlist: "p").map { ($0.name, $0) })
        #expect(entries["Heat (1995)"]?.year == 1995)
        #expect(entries["Heat (1995)"]?.isAdult == false)
        #expect(entries["Something"]?.isAdult == true)
    }
}
