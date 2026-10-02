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
