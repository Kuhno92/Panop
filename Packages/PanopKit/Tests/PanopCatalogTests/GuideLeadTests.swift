import Foundation
@testable import PanopCatalog
import PanopCore
import Testing

@Suite("Channels with the same guide")
struct GuideLeadTests {
    private func importer(_ store: InMemoryCatalogStore) -> CatalogImporter {
        CatalogImporter(store: store, transport: StubTransport { _ in (404, "") })
    }

    private func leads(_ store: InMemoryCatalogStore) async -> [String: (guide: Bool, category: Bool)] {
        await Dictionary(
            uniqueKeysWithValues: store.allEntries(playlist: "p").map { ($0.name, ($0.isGuideLead, $0.isCategoryLead)) }
        )
    }

    @Test
    func `the first channel of a guide leads and the others do not`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="ard.de" group-title="Germany",Das Erste HD
        http://h/live/1.ts
        #EXTINF:-1 tvg-id="ard.de" group-title="Germany",Das Erste SD
        http://h/live/2.ts
        #EXTINF:-1 tvg-id="zdf.de" group-title="Germany",ZDF
        http://h/live/3.ts
        #EXTINF:-1 group-title="Germany",No Guide One
        http://h/live/4.ts
        #EXTINF:-1 group-title="Germany",No Guide Two
        http://h/live/5.ts
        """
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let found = await leads(store)
        #expect(found["Das Erste HD"]?.guide == true)
        #expect(found["Das Erste SD"]?.guide == false)
        #expect(found["ZDF"]?.guide == true)
        #expect(found["No Guide One"]?.guide == true, "a channel with no guide key is its own group")
        #expect(found["No Guide Two"]?.guide == true)
    }

    @Test
    func `within a category the first of a guide leads, and a variant in another category still shows there`(
    ) async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="ard.de" group-title="Germany SD",Das Erste SD
        http://h/live/1.ts
        #EXTINF:-1 tvg-id="ard.de" group-title="Germany HD",Das Erste HD
        http://h/live/2.ts
        #EXTINF:-1 tvg-id="ard.de" group-title="Germany HD",Das Erste HD+
        http://h/live/3.ts
        """
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let found = await leads(store)
        #expect(found["Das Erste SD"]?.guide == true)
        #expect(found["Das Erste HD"]?.guide == false, "overall, the SD one came first")
        #expect(
            found["Das Erste HD"]?.category == true,
            "but it is the first in its own category, so that category lists it"
        )
        #expect(found["Das Erste HD+"]?.category == false)
    }

    @Test
    func `films never lead or follow: only live channels are grouped`() async throws {
        let store = InMemoryCatalogStore()
        let text = """
        #EXTM3U
        #EXTINF:5400 tvg-id="same" group-title="Films",One
        http://h/movie/u/p/1.mp4
        #EXTINF:5400 tvg-id="same" group-title="Films",Two
        http://h/movie/u/p/2.mp4
        """
        _ = try await importer(store).importM3U(playlist: "p", source: .file(path: writeTemporaryFile(text)))

        let found = await leads(store)
        #expect(found["One"]?.guide == true)
        #expect(found["Two"]?.guide == true)
    }
}

@Suite("Guide grouping key")
struct GuideGroupingTests {
    @Test func `a shared guide key is the key`() {
        #expect(GuideGrouping.key(epgKey: "daserste.de", name: "Das Erste HD") == "epg:daserste.de")
    }

    @Test func `a number of the panel's own groups by name, without the quality words`() {
        let hdKey = GuideGrouping.key(epgKey: "6567", name: "DE - DAS ERSTE HD")
        let uhdKey = GuideGrouping.key(epgKey: "6568", name: "DE - DAS ERSTE UHD")
        #expect(hdKey == uhdKey)
        #expect(hdKey == "name:de - das erste")
        #expect(hdKey != GuideGrouping.key(epgKey: "1", name: "AT - DAS ERSTE HD"))
        #expect(GuideGrouping.key(epgKey: "1", name: "ZDF") != GuideGrouping.key(epgKey: "2", name: "ZDF neo"))
    }

    @Test func `a divider has nothing to group by`() {
        #expect(GuideGrouping.key(epgKey: "", name: "#####") == nil)
    }
}
