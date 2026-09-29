import Foundation
@testable import PanopCatalog
import PanopCore
import PanopXtream
import Testing

private let playlistID = "x1"
private let credentials = ProviderCredentials(baseURL: "http://panel.example", username: "alice", password: "s3cret")

private let loginOK = #"{"user_info":{"username":"alice","auth":1,"status":"Active"}}"#

/// A panel that serves the given rows for each action.
private struct Panel {
    var live = 3
    var movies = 2
    var series = 2
    var failing: Set<String> = []
    var truncated: Set<String> = []
    var loginBody = loginOK

    func transport() -> StubTransport {
        let panel = self
        return StubTransport(chunkSize: 512) { request in
            let action = query(request, "action")
            if action == nil {
                return (200, panel.loginBody)
            }
            if panel.failing.contains(action ?? "") {
                return (500, "")
            }
            return (200, panel.body(for: action ?? "", truncated: panel.truncated.contains(action ?? "")))
        }
    }

    func body(for action: String, truncated: Bool) -> String {
        switch action {
        case "get_live_categories": #"[{"category_id":"1","category_name":"News"}]"#
        case "get_vod_categories": #"[{"category_id":"7","category_name":"Action"}]"#
        case "get_series_categories": #"[{"category_id":"9","category_name":"Drama"}]"#
        case "get_live_streams":
            list(live, truncated) {
                #"{"stream_id":\#($0),"name":"Live \#($0)","category_id":"1","epg_channel_id":"Chan.\#($0)"}"#
            }
        case "get_vod_streams":
            list(movies, truncated) {
                #"{"stream_id":\#($0),"name":"Movie \#($0)","category_id":"7","container_extension":"mkv"}"#
            }
        case "get_series":
            list(series, truncated) { #"{"series_id":\#($0),"name":"Show \#($0)","category_id":"9"}"# }
        default: "[]"
        }
    }

    private func list(_ count: Int, _ truncated: Bool, _ row: (Int) -> String) -> String {
        let text = "[" + (0 ..< count).map(row).joined(separator: ",") + "]"
        return truncated ? String(text.prefix(text.count / 2)) : text
    }
}

private func importer(_ store: any CatalogStore, _ panel: Panel, batchSize: Int = 1000) -> CatalogImporter {
    CatalogImporter(store: store, transport: panel.transport(), batchSize: batchSize)
}

@Suite("Xtream import")
struct XtreamImportTests {
    @Test
    func `imports every section with categories resolved to names`() async throws {
        let store = InMemoryCatalogStore()
        let report = try await importer(store, Panel()).importXtream(playlist: playlistID, credentials: credentials)

        #expect(report.failures.isEmpty)
        #expect(report.kinds.map(\.imported) == [3, 2, 2])

        let entries = await store.allEntries(playlist: playlistID)
        #expect(entries.count == 7)

        let live = try #require(entries.first { $0.id == "live:1" })
        #expect(live.kind == .live)
        #expect(live.groupName == "News")
        #expect(live.epgKey == "chan.1")
        #expect(live.remoteID == "1")

        let movie = try #require(entries.first { $0.id == "movie:0" })
        #expect(movie.containerExtension == "mkv")
        #expect(movie.groupName == "Action")

        #expect(entries.first { $0.id == "series:1" }?.kind == .series)
        #expect(await store.allCategories(playlist: playlistID).count == 3)
    }

    @Test
    func `identity comes from the provider's id`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel()).importXtream(playlist: playlistID, credentials: credentials)
        #expect(await Set(store.allEntries(playlist: playlistID).map(\.id)) == [
            "live:0", "live:1", "live:2", "movie:0", "movie:1", "series:0", "series:1"
        ])
    }

    @Test
    func `bad credentials fail before anything is written`() async {
        let store = InMemoryCatalogStore()
        let panel = Panel(loginBody: #"{"user_info":{"auth":0}}"#)
        await #expect(throws: XtreamError.authenticationFailed) {
            _ = try await importer(store, panel).importXtream(playlist: playlistID, credentials: credentials)
        }
        #expect(await store.allEntries(playlist: playlistID).isEmpty)
        #expect(await store.syncState(playlist: playlistID) == nil)
    }

    @Test
    func `an unchanged re-import writes nothing`() async throws {
        let store = InMemoryCatalogStore()
        let sut = importer(store, Panel(live: 40, movies: 30, series: 20), batchSize: 7)
        _ = try await sut.importXtream(playlist: playlistID, credentials: credentials)
        let writes = await store.writeCount

        let report = try await sut.importXtream(playlist: playlistID, credentials: credentials)

        #expect(await store.writeCount == writes)
        #expect(report.kinds.map(\.summary.unchanged) == [40, 30, 20])
    }

    // MARK: - Sections fail independently

    /// One list timing out must not block the others, and must not touch the
    /// rows of the section that failed.
    @Test
    func `a failed section leaves its rows alone and the others import`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel()).importXtream(playlist: playlistID, credentials: credentials)

        let panel = Panel(live: 4, failing: ["get_vod_streams"])
        let report = try await importer(store, panel).importXtream(playlist: playlistID, credentials: credentials)

        let movie = try #require(report.kinds.first { $0.kind == .movie })
        #expect(movie.failure != nil)
        #expect(report.kinds.first { $0.kind == .live }?.imported == 4)
        #expect(await store.allEntries(playlist: playlistID).filter { $0.kind == .movie }.count == 2)
    }

    @Test
    func `a partial failure is not recorded as a completed import`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(failing: ["get_series"])).importXtream(
            playlist: playlistID,
            credentials: credentials
        )
        #expect(try #require(await store.syncState(playlist: playlistID)).lastCompleted == nil)
    }

    @Test
    func `every section failing is an error`() async {
        let panel = Panel(failing: ["get_live_streams", "get_vod_streams", "get_series"])
        await #expect(throws: CatalogError.self) {
            _ = try await importer(InMemoryCatalogStore(), panel).importXtream(
                playlist: playlistID,
                credentials: credentials
            )
        }
    }

    // MARK: - Removal and its safety

    /// A list cut off mid-download must fail that section, never shrink it.
    @Test
    func `a truncated list removes nothing`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(live: 200)).importXtream(playlist: playlistID, credentials: credentials)

        let report = try await importer(store, Panel(live: 200, truncated: ["get_live_streams"]))
            .importXtream(playlist: playlistID, credentials: credentials)

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.failure != nil)
        #expect(live.removed == 0)
        #expect(await store.allEntries(playlist: playlistID).filter { $0.kind == .live }.count == 200)
    }

    /// Panels under load answer `[]`. That parses, so it is not a failure, and
    /// only the gate stands between it and an empty catalog.
    @Test
    func `an empty answer does not wipe a full section`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(live: 150)).importXtream(playlist: playlistID, credentials: credentials)

        let report = try await importer(store, Panel(live: 0)).importXtream(
            playlist: playlistID,
            credentials: credentials
        )

        let live = try #require(report.kinds.first { $0.kind == .live })
        #expect(live.removed == 0)
        #expect(live.deferredRemoval?.ids.count == 150)
        #expect(await store.allEntries(playlist: playlistID).filter { $0.kind == .live }.count == 150)
    }

    @Test
    func `channels the provider dropped are removed`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(live: 10)).importXtream(playlist: playlistID, credentials: credentials)

        let report = try await importer(store, Panel(live: 8)).importXtream(
            playlist: playlistID,
            credentials: credentials
        )

        #expect(report.kinds.first { $0.kind == .live }?.removed == 2)
        #expect(await store.allEntries(playlist: playlistID).filter { $0.kind == .live }.count == 8)
    }

    @Test
    func `a stale confirmation is refused after another import`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(live: 150)).importXtream(playlist: playlistID, credentials: credentials)
        let held = try await importer(store, Panel(live: 0)).importXtream(
            playlist: playlistID,
            credentials: credentials
        )
        let removal = try #require(held.deferredRemovals.first)

        _ = try await importer(store, Panel(live: 150)).importXtream(playlist: playlistID, credentials: credentials)

        await #expect(throws: CatalogError.staleConfirmation) {
            try await importer(store, Panel()).confirm(removal, playlist: playlistID)
        }
        #expect(await store.allEntries(playlist: playlistID).filter { $0.kind == .live }.count == 150)
    }

    @Test
    func `playlists do not affect each other`() async throws {
        let store = InMemoryCatalogStore()
        _ = try await importer(store, Panel(live: 5)).importXtream(playlist: "a", credentials: credentials)
        _ = try await importer(store, Panel(live: 2)).importXtream(playlist: "b", credentials: credentials)

        #expect(await store.allEntries(playlist: "a").filter { $0.kind == .live }.count == 5)
        #expect(await store.allEntries(playlist: "b").filter { $0.kind == .live }.count == 2)
    }
}
