import Foundation
@testable import Panop
import PanopCore
import PanopPlayback
import SwiftData
import Testing

private let credentials = ProviderCredentials(baseURL: "http://panel.example:8080", username: "alice", password: "pw")

/// 2026-05-01 18:30 UTC.
private let start = Date(timeIntervalSince1970: 1_777_660_200)

@Suite("Catch-up")
struct CatchupTests {
    private func target(zone: String? = "Europe/Berlin") -> PlaybackTarget {
        PlaybackTarget(
            playlist: "p",
            entryID: "live:42",
            kind: .live,
            name: "Channel · Show",
            remoteID: "42",
            catchup: CatchupWindow(start: start, minutes: 45, timeZoneID: zone)
        )
    }

    @Test
    func `an aired programme plays from the archive address, for every engine`() throws {
        let request = try PlaybackRequestBuilder.request(
            for: target(),
            source: .xtream(credentials),
            transport: StubTransport { _ in (200, "") }
        )

        let expected = "http://panel.example:8080/timeshift/alice/pw/45/2026-05-01:20-30/42.ts"
        #expect(request.item(.avPlayer).url == expected)
        #expect(request.item(.vlcKit).url == expected)
        #expect(request.item(.avPlayer).mediaKind == .live)
    }

    @Test
    func `a window's value carries the programme but no address, and ignores the catalog's live one`() throws {
        let window = PlayerWindowRequest(target())

        #expect(window.catchup?.minutes == 45)
        let rebuilt = window.target(streamURL: "http://panel.example:8080/live/alice/pw/42.ts")
        #expect(rebuilt.streamURL == nil, "the live address would play the wrong thing")
        #expect(rebuilt.catchup == target().catchup)
        let saved = try String(bytes: JSONEncoder().encode(window), encoding: .utf8) ?? ""
        #expect(!saved.contains("pw"))
    }

    @Test
    func `a window saved before this existed still opens`() throws {
        let old = #"{"playlist":"p","entryID":"e","kind":"live","name":"X"}"#

        let window = try JSONDecoder().decode(PlayerWindowRequest.self, from: Data(old.utf8))

        #expect(window.catchup == nil)
    }
}

@Suite("Aired programmes", .serialized)
@MainActor
struct AiredLookupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func programme(_ title: String, hoursAgo: Double, hours: Double) -> EPGProgrammeFixture {
        EPGProgrammeFixture(title: title, start: now.addingTimeInterval(-hoursAgo * 3600), hours: hours)
    }

    @Test
    func `only what ended within the archive window is listed, newest first`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        let fixtures = [
            programme("Two days ago", hoursAgo: 48, hours: 1),
            programme("Yesterday", hoursAgo: 25, hours: 1),
            programme("This morning", hoursAgo: 5, hours: 1),
            programme("On now", hoursAgo: 0.5, hours: 1),
            programme("Later", hoursAgo: -2, hours: 1)
        ]
        try await EPGProgrammeFixture.store(fixtures, channel: "news", playlist: "p", in: catalog)

        let list = GuideLookup.aired(
            playlist: "p",
            epgKey: "news",
            days: 1,
            before: now,
            limit: 10,
            in: ModelContext(catalog.container)
        )

        #expect(list.map(\.title) == ["This morning"], "yesterday started more than a day ago")
    }

    @Test
    func `a longer window reaches further back, and no window or key lists nothing`() async throws {
        let catalog = try OnDiskCatalog()
        defer { catalog.cleanUp() }
        try await EPGProgrammeFixture.store(
            [programme("Two days ago", hoursAgo: 48, hours: 1), programme("This morning", hoursAgo: 5, hours: 1)],
            channel: "news",
            playlist: "p",
            in: catalog
        )
        let context = ModelContext(catalog.container)

        let week = GuideLookup.aired(playlist: "p", epgKey: "news", days: 7, before: now, limit: 10, in: context)
        #expect(week.map(\.title) == ["This morning", "Two days ago"])
        #expect(GuideLookup.aired(playlist: "p", epgKey: "news", days: 0, before: now, limit: 10, in: context).isEmpty)
        #expect(GuideLookup.aired(playlist: "p", epgKey: nil, days: 7, before: now, limit: 10, in: context).isEmpty)
    }
}
