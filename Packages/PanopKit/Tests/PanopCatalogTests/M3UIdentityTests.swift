import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

/// What names an M3U channel. The whole address, query string included, on purpose.
///
/// The roadmap wondered whether to strip query parameters before hashing, in case a provider
/// adds a rotating token to every address. Checked against a real playlist (the iptv-org German
/// list): 11 of about 245 addresses carry a query, and every parameter in them *identifies the
/// channel* (`network_id`, `ref`, `profile`, `account` and `file`). Two of its entries differ only
/// in `?network_id=16660` against `?network_id=535`. Stripping would merge channels that are
/// different. No rotating token appears anywhere in it.
@Suite("M3U identity")
struct M3UIdentityTests {
    @Test
    func `addresses that differ only by their query are different channels`() {
        let one = CatalogID.m3u(url: "https://stream.ads.ottera.tv/playlist.m3u8?network_id=16660")
        let two = CatalogID.m3u(url: "https://stream.ads.ottera.tv/playlist.m3u8?network_id=535")

        #expect(one != two)
    }

    @Test
    func `the same address is the same channel every time`() {
        let address = "http://178.27.12.3:9981/stream/channelid/269948147?profile=pass"

        #expect(CatalogID.m3u(url: address) == CatalogID.m3u(url: address))
    }

    @Test
    func `two channels that differ only by query both survive an import`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1,Channel A
        https://stream.ads.ottera.tv/playlist.m3u8?network_id=16660
        #EXTINF:-1,Channel B
        https://stream.ads.ottera.tv/playlist.m3u8?network_id=535
        """
        let path = try writeTemporaryFile(text)

        _ = try await CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
            .importM3U(playlist: "p", source: .file(path: path))

        let names = await store.allEntries(playlist: "p").map(\.name).sorted()
        #expect(names == ["Channel A", "Channel B"], "one was taken for the other")
    }
}
