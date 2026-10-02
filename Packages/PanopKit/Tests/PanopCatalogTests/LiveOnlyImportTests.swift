import Foundation
@testable import PanopCatalog
import PanopCore
import PanopXtream
import Testing

@Suite("Live-only sources")
struct LiveOnlyImportTests {
    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [String] = []

        func add(_ action: String) {
            lock.withLock { actions.append(action) }
        }

        var all: [String] {
            lock.withLock { actions }
        }
    }

    private let login = #"{"user_info":{"username":"alice","auth":1,"status":"Active"}}"#
    private let credentials = ProviderCredentials(baseURL: "http://panel.example", username: "alice", password: "pw")

    private func panel(_ requests: Requests) -> StubTransport {
        let login = login
        return StubTransport { request in
            guard let action = query(request, "action") else { return (200, login) }
            requests.add(action)
            return switch action {
            case "get_live_streams": (200, #"[{"stream_id":1,"name":"Live 1","category_id":"1"}]"#)
            case "get_vod_streams": (200, #"[{"stream_id":2,"name":"Movie 2","category_id":"7"}]"#)
            case "get_series": (200, #"[{"series_id":3,"name":"Show 3","category_id":"9"}]"#)
            default: (200, "[]")
            }
        }
    }

    @Test
    func `an Xtream panel is never asked for its movies or series`() async throws {
        let store = InMemoryCatalogStore()
        let requests = Requests()
        let importer = CatalogImporter(store: store, transport: panel(requests))

        _ = try await importer.importXtream(playlist: "x", credentials: credentials, includeVOD: false)

        #expect(await store.allEntries(playlist: "x").map(\.id) == ["live:1"])
        #expect(!requests.all.contains { $0.contains("vod") || $0.contains("series") }, "asked for: \(requests.all)")
    }

    @Test
    func `by default every section is imported`() async throws {
        let store = InMemoryCatalogStore()
        let importer = CatalogImporter(store: store, transport: panel(Requests()))

        _ = try await importer.importXtream(playlist: "x", credentials: credentials)

        #expect(await Set(store.allEntries(playlist: "x").map(\.id)) == ["live:1", "movie:2", "series:3"])
    }

    @Test
    func `an M3U file keeps its channels and drops the films and episodes`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,Live One
        http://h/live/1.ts
        #EXTINF:5400,A Film
        http://h/movie/u/p/2.mp4
        #EXTINF:2400,Show S01E01
        http://h/series/u/p/3.mp4
        #EXTINF:-1,Live Two
        http://h/live/4.ts
        """
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })

        let report = try await importer.importM3U(
            playlist: "p",
            source: .file(path: writeTemporaryFile(text)),
            includeVOD: false
        )

        #expect(await store.allEntries(playlist: "p").map(\.name).sorted() == ["Live One", "Live Two"])
        #expect(report.skippedEntries == 0, "leaving them out by choice is not an unusable entry")
    }

    @Test
    func `the descriptor carries the choice through a sync`() async throws {
        let store = InMemoryCatalogStore()
        let requests = Requests()
        let importer = CatalogImporter(store: store, transport: panel(requests))
        let descriptor = PlaylistDescriptor(
            id: "x",
            source: .xtream(credentials),
            includeVOD: false
        )

        _ = try await importer.sync(descriptor, guide: false)

        #expect(await store.allEntries(playlist: "x").map(\.id) == ["live:1"])
    }
}

@Suite("Turning VOD off for a source")
struct DropVODTests {
    @Test
    func `movies, series and their categories go, and live channels stay`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="News",Live One
        http://h/live/1.ts
        #EXTINF:5400 group-title="Films",A Film
        http://h/movie/u/p/2.mp4
        #EXTINF:2400 group-title="Shows",Show S01E01
        http://h/series/u/p/3.mp4
        """
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
        _ = try await importer.importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))
        #expect(await store.allEntries(playlist: "p").count == 4, "the channel, the film, the episode and its show")

        try await importer.dropVOD(playlist: "p")

        #expect(await store.allEntries(playlist: "p").map(\.name) == ["Live One"])
        #expect(await store.allCategories(playlist: "p").map(\.name) == ["News"])
    }

    @Test
    func `more than a page of rows is removed`() async throws {
        let store = InMemoryCatalogStore()
        let lines = (0 ..< CatalogImporter.sweepPageSize + 50)
            .map { "#EXTINF:5400,Film \($0)\nhttp://h/movie/u/p/\($0).mp4" }
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
        _ = try await importer.importM3U(
            playlist: "p",
            source: .file(path: writeTemporaryFile("#EXTM3U\n" + lines.joined(separator: "\n")))
        )

        try await importer.dropVOD(playlist: "p")

        #expect(await store.allEntries(playlist: "p").isEmpty)
    }
}
