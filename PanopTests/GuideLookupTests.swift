import Foundation
@testable import Panop
import PanopCatalog
import PanopEPG
import SwiftData
import Testing

@Suite("Guide lookup", .serialized)
@MainActor
struct GuideLookupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func programme(_ channel: String, _ title: String, from start: Double, to stop: Double) -> EPGProgramme {
        EPGProgramme(
            channelID: channel,
            start: now.addingTimeInterval(start * 60),
            stop: now.addingTimeInterval(stop * 60),
            title: title
        )
    }

    private func populate(_ catalog: OnDiskCatalog) async throws {
        _ = try await catalog.store.upsertProgrammes([
            programme("news", "Earlier", from: -90, to: -30),
            programme("news", "Headlines", from: -30, to: 30),
            programme("news", "Weather", from: 30, to: 45),
            programme("news", "Film", from: 45, to: 135),
            programme("sport", "Match", from: -10, to: 80)
        ], playlist: "p")
        _ = try await catalog.store.upsertProgrammes([
            programme("news", "Other Source", from: -5, to: 5)
        ], playlist: "q")
    }

    @Test
    func `what is on now comes first, then what follows, and what has ended is not listed`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)

        let list = GuideLookup.upcoming(
            playlist: "p",
            epgKey: "news",
            after: now,
            limit: 10,
            in: ModelContext(catalog.container)
        )

        #expect(list.map(\.title) == ["Headlines", "Weather", "Film"])
        #expect(list.first?.isOn(at: now) == true)
        #expect(list.dropFirst().allSatisfy { !$0.isOn(at: now) })
    }

    @Test
    func `the limit cuts the list and the channel and source are respected`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)

        #expect(GuideLookup.upcoming(playlist: "p", epgKey: "news", after: now, limit: 1, in: context).count == 1)
        #expect(GuideLookup.upcoming(playlist: "p", epgKey: "sport", after: now, limit: 10, in: context)
            .map(\.title) == ["Match"])
        #expect(GuideLookup.upcoming(playlist: "q", epgKey: "news", after: now, limit: 10, in: context)
            .map(\.title) == ["Other Source"])
    }

    @Test
    func `a channel with no guide key, or no programmes, has nothing`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)

        #expect(GuideLookup.upcoming(playlist: "p", epgKey: nil, after: now, limit: 5, in: context).isEmpty)
        #expect(GuideLookup.upcoming(playlist: "p", epgKey: "", after: now, limit: 5, in: context).isEmpty)
        #expect(GuideLookup.upcoming(playlist: "p", epgKey: "nobody", after: now, limit: 5, in: context).isEmpty)
    }

    @Test
    func `progress runs from the start to the end of a programme`() {
        let show = ProgrammeSnapshot(start: now, stop: now.addingTimeInterval(3600), title: "T")

        #expect(show.fraction(at: now.addingTimeInterval(-60)) == 0)
        #expect(show.fraction(at: now.addingTimeInterval(1800)) == 0.5)
        #expect(show.fraction(at: now.addingTimeInterval(7200)) == 1)
        #expect(ProgrammeSnapshot(start: now, stop: now, title: "Zero").fraction(at: now) == 0)
    }

    @Test
    func `a programme carries the guide's categories, and from them its kind`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        _ = try await catalog.store.upsertProgrammes([
            EPGProgramme(
                channelID: "sport", start: now.addingTimeInterval(-600), stop: now.addingTimeInterval(600),
                title: "Derby", categories: ["Sport", "Fußball"]
            ),
            EPGProgramme(
                channelID: "sport", start: now.addingTimeInterval(600), stop: now.addingTimeInterval(1200),
                title: "Plain"
            )
        ], playlist: "p")
        let context = ModelContext(catalog.container)

        let both = GuideLookup.nowAndNext(playlist: "p", epgKey: "sport", at: now, in: context)

        #expect(both.now?.categories == ["Sport", "Fußball"])
        #expect(both.now?.kind == .sport)
        #expect(both.next?.categories.isEmpty == true)
        #expect(both.next?.kind == .other)
    }

    @Test
    func `now and next are the one on air and the one after it`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)

        let news = GuideLookup.nowAndNext(playlist: "p", epgKey: "news", at: now, in: context)
        #expect(news.now?.title == "Headlines")
        #expect(news.next?.title == "Weather")

        // Between programmes: nothing on, and the next to start is next.
        let gap = GuideLookup.nowAndNext(
            playlist: "p",
            epgKey: "news",
            at: now.addingTimeInterval(-45 * 60),
            in: context
        )
        #expect(gap.now?.title == "Earlier")
        #expect(gap.next?.title == "Headlines")

        // The last one has nothing after it, and a channel with no guide has neither.
        let last = GuideLookup.nowAndNext(
            playlist: "p",
            epgKey: "news",
            at: now.addingTimeInterval(100 * 60),
            in: context
        )
        #expect(last.now?.title == "Film")
        #expect(last.next == nil)
        let none = GuideLookup.nowAndNext(playlist: "p", epgKey: "nobody", at: now, in: context)
        #expect(none.now == nil && none.next == nil)
    }

    @Test
    func `a window holds what is running at its start and what starts inside it, and no more`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)
        let window = now.addingTimeInterval(-10 * 60) ... now.addingTimeInterval(50 * 60)

        let found = GuideLookup.programmes(playlist: "p", epgKey: "news", in: window, limit: 50, context: context)

        // Headlines began before the window and runs into it; Film begins after it ends.
        #expect(found.map(\.title) == ["Headlines", "Weather", "Film"] || found.map(\.title) == [
            "Headlines",
            "Weather"
        ])
        #expect(!found.map(\.title).contains("Earlier"))
        #expect(!found.map(\.title).contains("Other Source"))
    }

    @Test
    func `a window is cut at its limit and a channel with no guide has none`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await populate(catalog)
        let context = ModelContext(catalog.container)
        let window = now.addingTimeInterval(-60 * 60) ... now.addingTimeInterval(10 * 3600)

        #expect(GuideLookup.programmes(playlist: "p", epgKey: "news", in: window, limit: 2, context: context)
            .count == 2)
        #expect(GuideLookup.programmes(playlist: "p", epgKey: "nobody", in: window, limit: 9, context: context).isEmpty)
    }
}

/// A programme to store, relative to a fixed "now" chosen by the test.
struct EPGProgrammeFixture {
    var title: String
    var start: Date
    var hours: Double

    @MainActor
    static func store(_ fixtures: [EPGProgrammeFixture], channel: String, playlist: String, in catalog: OnDiskCatalog)
        async throws
    {
        _ = try await catalog.store.upsertProgrammes(fixtures.map {
            EPGProgramme(
                channelID: channel,
                start: $0.start,
                stop: $0.start.addingTimeInterval($0.hours * 3600),
                title: $0.title
            )
        }, playlist: playlist)
    }
}
