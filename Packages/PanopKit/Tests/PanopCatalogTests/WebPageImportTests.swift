import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("A web page is not a playlist")
struct WebPageImportTests {
    private let page = """
    <!DOCTYPE html>
    <html lang="en"><head><title>iptv/streams/de.m3u at master</title></head>
    <body>55937028\nplaylist.m3u</body></html>
    """

    @Test
    func `an address that returns a web page fails and leaves the catalog as it was`() async throws {
        let store = InMemoryCatalogStore()
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (200, "") })
        _ = try await importer.importM3U(
            playlist: "p",
            source: .file(path: writeTemporaryFile("#EXTM3U\n#EXTINF:-1,Das Erste\nhttp://h/live/1.ts\n"))
        )
        #expect(await store.allEntries(playlist: "p").map(\.name) == ["Das Erste"])

        await #expect(throws: CatalogError.notAPlaylist) {
            _ = try await importer.importM3U(playlist: "p", source: .file(path: writeTemporaryFile(page)), force: true)
        }

        #expect(await store.allEntries(playlist: "p").map(\.name) == ["Das Erste"], "the real channels were kept")
    }

    @Test
    func `a page served by a link is refused the same way`() async throws {
        let store = InMemoryCatalogStore()
        let importer = CatalogImporter(store: store, transport: StubTransport { _ in (200, page) })

        await #expect(throws: CatalogError.notAPlaylist) {
            _ = try await importer.importM3U(
                playlist: "p",
                source: .remote(#require(URL(string: "https://github.com/o/r/blob/master/a.m3u")))
            )
        }
        #expect(await store.allEntries(playlist: "p").isEmpty)
    }
}
