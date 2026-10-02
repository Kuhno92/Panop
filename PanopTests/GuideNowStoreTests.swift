import Foundation
@testable import Panop
import PanopCatalog
import PanopEPG
import SwiftData
import Testing

@Suite("Guide now store", .serialized)
@MainActor
struct GuideNowStoreTests {
    private func populate(_ catalog: OnDiskCatalog) async throws {
        let now = Date.now
        _ = try await catalog.store.upsertProgrammes([
            EPGProgramme(
                channelID: "news",
                start: now.addingTimeInterval(-600),
                stop: now.addingTimeInterval(600),
                title: "Headlines"
            ),
            EPGProgramme(
                channelID: "news",
                start: now.addingTimeInterval(600),
                stop: now.addingTimeInterval(3600),
                title: "Weather"
            ),
            EPGProgramme(
                channelID: "sport",
                start: now.addingTimeInterval(-60),
                stop: now.addingTimeInterval(60),
                title: "Match"
            )
        ], playlist: "p")
    }

    private func settle(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test
    func `a row is answered from memory, blank until the background read arrives`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let store = GuideNowStore()

        #expect(store.current(playlist: "p", epgKey: "news") == nil, "nothing known yet, and nothing read to find out")
        #expect(store.needs(playlist: "p", epgKey: "news"))

        store.request(playlist: "p", epgKey: "news", in: catalog.container)

        #expect(await settle { store.current(playlist: "p", epgKey: "news")?.title == "Headlines" })
        #expect(!store.needs(playlist: "p", epgKey: "news"))
    }

    @Test
    func `rows asked for together are read together`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let store = GuideNowStore()

        store.request(playlist: "p", epgKey: "news", in: catalog.container)
        store.request(playlist: "p", epgKey: "sport", in: catalog.container)
        store.request(playlist: "p", epgKey: "nobody", in: catalog.container)

        #expect(await settle { store.current(playlist: "p", epgKey: "sport")?.title == "Match" })
        #expect(store.current(playlist: "p", epgKey: "news")?.title == "Headlines")
        #expect(store.current(playlist: "p", epgKey: "nobody") == nil)
        #expect(!store.needs(playlist: "p", epgKey: "nobody"), "looked up, and found nothing on")
    }

    @Test
    func `a row that scrolled away before the read is not read`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let store = GuideNowStore()

        store.request(playlist: "p", epgKey: "news", in: catalog.container)
        store.request(playlist: "p", epgKey: "sport", in: catalog.container)
        store.withdraw(playlist: "p", epgKey: "news")

        #expect(await settle { store.current(playlist: "p", epgKey: "sport") != nil })
        #expect(store.needs(playlist: "p", epgKey: "news"), "withdrawn, so never looked up")
    }

    @Test
    func `an answer runs out with its programme`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let store = GuideNowStore()
        store.request(playlist: "p", epgKey: "sport", in: catalog.container)
        #expect(await settle { store.current(playlist: "p", epgKey: "sport") != nil })

        let after = Date.now.addingTimeInterval(120)

        #expect(store.current(playlist: "p", epgKey: "sport", now: after) == nil)
        #expect(store.needs(playlist: "p", epgKey: "sport", now: after), "ended, so ask again")
    }

    @Test
    func `a channel with no guide key is never asked about`() {
        let store = GuideNowStore()

        #expect(!store.needs(playlist: "p", epgKey: nil))
        #expect(!store.needs(playlist: "p", epgKey: ""))
    }
}
