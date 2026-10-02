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
}
