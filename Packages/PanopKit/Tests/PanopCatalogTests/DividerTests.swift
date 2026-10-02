import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("Provider dividers")
struct DividerTests {
    @Test(arguments: [
        "##### DE ALLGEMEINES #####",
        "#####  AMAZON PRIME VIP  #####",
        "### DYN PPV 4K ###",
        "####### SPORT DEUTSCHLAND PPV #######",
        "  ##### 24/7 GERMANY #####  ",
        "=== NEWS ===",
        "----- SPORT -----",
        "*** KIDS ***",
        "___ MOVIES ___",
        "★★★ FAVOURITES ★★★",
        "▬▬▬ MUSIC ▬▬▬",
        "+++ RADIO +++",
        "[[[ DOCS ]]]",
        "==========",
        "-----"
    ])
    func `a name fenced by the same decoration at both ends is a divider`(name: String) {
        #expect(EntryMapping.isDivider(name))
    }

    @Test(arguments: [
        "Das Erste",
        "#1 Hits",
        "## Two Hashes ##",
        "CNN #####",
        "##### Only the start",
        "# News #",
        "- NO EVENT STREAMING - | 8K EXCLUSIVE | DE: SPORT DEUTSCHLAND PPV 1",
        "...And Then There Were None...",
        "--",
        "---",
        "- Kids -",
        "3sat",
        "9Live",
        "ARD HD",
        ""
    ])
    func `a real channel, however odd its name, is not`(name: String) {
        #expect(!EntryMapping.isDivider(name))
    }

    @Test
    func `an Xtream import leaves dividers out, with the order of the rest unbroken`() async throws {
        let store = InMemoryCatalogStore()
        let panel = StubTransport { request in
            guard let action = query(request, "action") else {
                return (200, #"{"user_info":{"username":"u","auth":1,"status":"Active"}}"#)
            }
            return action == "get_live_streams"
                ? (200, """
                [{"stream_id":1,"num":1,"name":"##### NEWS #####"},{"stream_id":2,"num":2,"name":"Das Erste"},
                 {"stream_id":3,"num":3,"name":"##### SPORT #####"},{"stream_id":4,"num":4,"name":"Eurosport"}]
                """)
                : (200, "[]")
        }
        let importer = CatalogImporter(store: store, transport: panel)

        _ = try await importer.importXtream(
            playlist: "x",
            credentials: ProviderCredentials(baseURL: "http://p.example", username: "u", password: "w")
        )

        let live = await store.allEntries(playlist: "x").sorted { ($0.sortNumber ?? 0) < ($1.sortNumber ?? 0) }
        #expect(live.map(\.name) == ["Das Erste", "Eurosport"])
    }

    @Test
    func `an M3U import leaves dividers out and does not count them as unusable`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,##### NEWS #####
        http://h/live/1.ts
        #EXTINF:-1,Das Erste
        http://h/live/2.ts
        """
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })

        let report = try await importer.importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let entries = await store.allEntries(playlist: "p")
        #expect(entries.map(\.name) == ["Das Erste"])
        #expect(entries.first?.sortNumber == 1, "no gap where the divider was")
        #expect(report.skippedEntries == 0)
    }

    @Test
    func `a divider already stored is removed by the next import`() async throws {
        let store = InMemoryCatalogStore()
        let transport = StubTransport { _ in (404, "") }
        let importer = CatalogImporter(store: store, transport: transport)
        let before = "#EXTM3U\n#EXTINF:-1,A\nhttp://h/live/1.ts\n#EXTINF:-1,##### X #####\nhttp://h/live/2.ts\n"
        // What an older version stored: the divider as an entry.
        _ = try await store.upsertEntries(
            [CatalogEntry(id: CatalogID.m3u(url: "http://h/live/2.ts"), kind: .live, name: "##### X #####")],
            playlist: "p"
        )

        _ = try await importer.importM3U(playlist: "p", source: .file(path: writeTemporaryFile(before)), force: true)

        #expect(await store.allEntries(playlist: "p").map(\.name) == ["A"])
    }
}
