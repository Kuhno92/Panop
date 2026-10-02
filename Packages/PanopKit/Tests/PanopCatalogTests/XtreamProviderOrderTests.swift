import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("Xtream provider order")
struct XtreamProviderOrderTests {
    private let credentials = ProviderCredentials(baseURL: "http://panel.example", username: "u", password: "p")

    /// A panel that lists its items in an order that is neither alphabetical nor by id.
    private func panel() -> StubTransport {
        StubTransport { request in
            guard let action = query(request, "action") else {
                return (200, #"{"user_info":{"username":"u","auth":1,"status":"Active"}}"#)
            }
            return switch action {
            case "get_live_streams":
                (200, #"[{"stream_id":9,"num":2,"name":"Zulu"},{"stream_id":5,"num":1,"name":"Alpha"}]"#)
            case "get_vod_streams":
                (200, #"[{"stream_id":1,"num":2,"name":"Zorro"},{"stream_id":2,"num":1,"name":"Alien"}]"#)
            case "get_series":
                (200, #"[{"series_id":1,"num":"2","name":"Zed"},{"series_id":2,"num":1,"name":"Alf"}]"#)
            default: (200, "[]")
            }
        }
    }

    @Test
    func `every kind keeps the number the panel gave it`() async throws {
        let store = InMemoryCatalogStore()
        let importer = CatalogImporter(store: store, transport: panel())

        _ = try await importer.importXtream(playlist: "x", credentials: credentials)

        let entries = await store.allEntries(playlist: "x")
        let order = { (kind: MediaKind) in
            entries.filter { $0.kind == kind }.sorted { ($0.sortNumber ?? .max) < ($1.sortNumber ?? .max) }.map(\.name)
        }
        #expect(order(.live) == ["Alpha", "Zulu"])
        #expect(order(.movie) == ["Alien", "Zorro"])
        #expect(order(.series) == ["Alf", "Zed"], "series carried no number before, and fell back to the alphabet")
    }
}

@Suite("Category order")
struct CategoryOrderTests {
    private let credentials = ProviderCredentials(baseURL: "http://panel.example", username: "u", password: "p")

    @Test
    func `an Xtream panel's categories keep the order it listed them in`() async throws {
        let store = InMemoryCatalogStore()
        let panel = StubTransport { request in
            guard let action = query(request, "action") else {
                return (200, #"{"user_info":{"username":"u","auth":1,"status":"Active"}}"#)
            }
            return switch action {
            case "get_live_categories":
                (200, #"[{"category_id":"9","category_name":"Sport"},{"category_id":"2","category_name":"News"}]"#)
            case "get_live_streams":
                (200, #"[{"stream_id":1,"name":"A","category_id":"2"}]"#)
            default: (200, "[]")
            }
        }

        _ = try await CatalogImporter(store: store, transport: panel)
            .importXtream(playlist: "x", credentials: credentials)

        let live = await store.allCategories(playlist: "x").filter { $0.kind == .live }
            .sorted { ($0.sortNumber ?? .max) < ($1.sortNumber ?? .max) }
        #expect(live.map(\.name) == ["Sport", "News"], "not alphabetical, and not by id")
        #expect(live.map(\.sortNumber) == [1, 2])
    }

    @Test
    func `an M3U file's groups are ordered by first appearance`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="Zeta",One
        http://h/live/1.ts
        #EXTINF:-1 group-title="Alpha",Two
        http://h/live/2.ts
        #EXTINF:-1 group-title="Zeta",Three
        http://h/live/3.ts
        """
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })

        _ = try await importer.importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let live = await store.allCategories(playlist: "p").sorted { ($0.sortNumber ?? .max) < ($1.sortNumber ?? .max) }
        #expect(live.map(\.name) == ["Zeta", "Alpha"])
    }
}
