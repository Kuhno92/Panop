import Foundation
@testable import Panop
import PanopCatalog
import PanopEPG
import SwiftData
import Testing

@Suite("Guide grid model", .serialized, .engineGate)
@MainActor
struct GuideGridModelTests {
    private let now = Date.now

    private func populate(_ catalog: OnDiskCatalog) async throws {
        func programme(_ channel: String, _ title: String, from start: Double, to stop: Double) -> EPGProgramme {
            EPGProgramme(
                channelID: channel, start: now.addingTimeInterval(start * 60),
                stop: now.addingTimeInterval(stop * 60), title: title
            )
        }
        _ = try await catalog.store.upsertProgrammes([
            programme("news", "Headlines", from: -30, to: 30),
            programme("news", "Weather", from: 30, to: 45),
            programme("news", "Far Away", from: 24 * 60, to: 25 * 60),
            programme("sport", "Match", from: -10, to: 80)
        ], playlist: "p")
    }

    private var window: ClosedRange<Date> {
        now.addingTimeInterval(-3600) ... now.addingTimeInterval(6 * 3600)
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
    func `a channel is answered from memory, blank until the background read arrives`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = GuideGridModel()
        let news = GuideKey(playlist: "p", epgKey: "news")
        model.reset(window: window)

        #expect(model.programmes[news] == nil)
        #expect(!model.isLoaded(news))
        model.request(news, in: catalog.container)

        #expect(await settle { model.isLoaded(news) })
        #expect(model.programmes[news]?.map(\.title) == ["Headlines", "Weather"], "what is in the window, and no more")
    }

    @Test
    func `channels asked for together are read together, and one with no guide is loaded and empty`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = GuideGridModel()
        model.reset(window: window)
        let keys = ["news", "sport", "nobody"].map { GuideKey(playlist: "p", epgKey: $0) }

        keys.forEach { model.request($0, in: catalog.container) }

        #expect(await settle { keys.allSatisfy(model.isLoaded) })
        #expect(model.programmes[keys[1]]?.map(\.title) == ["Match"])
        #expect(model.programmes[keys[2]] == [])
    }

    @Test
    func `a channel that scrolled away before the read is not read`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = GuideGridModel()
        model.reset(window: window)
        let news = GuideKey(playlist: "p", epgKey: "news")
        let sport = GuideKey(playlist: "p", epgKey: "sport")

        model.request(news, in: catalog.container)
        model.request(sport, in: catalog.container)
        model.withdraw(news)

        #expect(await settle { model.isLoaded(sport) })
        #expect(!model.isLoaded(news))
    }

    @Test
    func `a new stretch of time forgets what was read for the old one`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let model = GuideGridModel()
        model.reset(window: window)
        let news = GuideKey(playlist: "p", epgKey: "news")
        model.request(news, in: catalog.container)
        #expect(await settle { model.isLoaded(news) })

        model.reset(window: now.addingTimeInterval(23 * 3600) ... now.addingTimeInterval(26 * 3600))
        #expect(!model.isLoaded(news))
        model.request(news, in: catalog.container)

        #expect(await settle { model.isLoaded(news) })
        #expect(model.programmes[news]?.map(\.title) == ["Far Away"])
    }

    @Test
    func `nothing is read before a stretch of time is chosen`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let model = GuideGridModel()

        model.request(GuideKey(playlist: "p", epgKey: "news"), in: catalog.container)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.programmes.isEmpty)
    }
}
